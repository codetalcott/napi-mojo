'use strict';
// load-error.js — turn a native-addon load failure into an error that says
// what to do about it.
//
// When a prebuilt binary cannot load, the dynamic loader's message is all the
// user gets — often one line in a container log, read by someone using an
// addon built with napi-mojo who has never heard of napi-mojo or Mojo:
//
//   libstdc++.so.6: cannot open shared object file: No such file or directory
//
// The fix is almost always a different base image, but nothing in that line
// says so. explainLoadError() recognises the few failures a Linux prebuild
// actually has and rethrows with the fix and a docs link, keeping the original
// as `cause`. Anything it does not recognise is returned untouched.
//
// Self-contained on purpose: `napi-mojo release --scaffold` copies this file
// verbatim into addon projects, whose runtime must not depend on napi-mojo.

const { readdirSync } = require('fs');

const DOCS = 'https://github.com/codetalcott/napi-mojo/blob/main/docs/TROUBLESHOOTING.md';

// A load failure, as opposed to the package not being installed or the
// module's own initialisation throwing. glibc's and musl's phrasings both.
const LOAD_FAILURE = /cannot open shared object file|Error loading shared library|Error relocating|version `[A-Z_]+[\d.]+' not found|symbol not found/;

const CASES = [
  {
    // Checked first: on musl every failure also names a missing library, and
    // "install libstdc++" would be the wrong advice — the binary needs glibc.
    code: 'ERR_NATIVE_MUSL',
    anchor: 'musl',
    applies: (message, musl) => musl,
    text: () =>
      'this is a musl system (such as Alpine), and the prebuilt binary is built for glibc. ' +
      'There is no musl build of the Mojo runtime. Use a Debian- or Ubuntu-based image — ' +
      'for example oven/bun:*-slim, denoland/deno:distroless or node:22-bookworm-slim.',
  },
  {
    code: 'ERR_NATIVE_NO_CXX_RUNTIME',
    anchor: 'missing-cpp-runtime',
    applies: (message) => /(libstdc\+\+\.so\.6|libgcc_s\.so\.1): cannot open shared object file/.test(message),
    text: () =>
      'the prebuilt binary needs the C++ runtime (libstdc++.so.6 and libgcc_s.so.1), and this ' +
      'system does not have it. Minimal container images leave it out — oven/bun:*-distroless ' +
      'and denoland/deno:alpine among them. Use oven/bun:*-slim or denoland/deno:distroless ' +
      'instead, or copy the two libraries into your image (two Dockerfile lines, in the link below).',
  },
  {
    code: 'ERR_NATIVE_LIBSTDCXX_TOO_OLD',
    anchor: 'libstdcxx-too-old',
    applies: (message) => /version `GLIBCXX_[\d.]+' not found/.test(message),
    text: (message) =>
      `this system's libstdc++ is too old: the prebuilt binary needs ${/GLIBCXX_[\d.]+/.exec(message)[0]}, ` +
      'which GCC 12 and later provide (Ubuntu 22.04, Debian 12 and newer ship it).',
  },
  {
    code: 'ERR_NATIVE_GLIBC_TOO_OLD',
    anchor: 'glibc-too-old',
    applies: (message) => /version `GLIBC_[\d.]+' not found/.test(message),
    text: (message) =>
      `this system's glibc is too old: the prebuilt binary needs ${/GLIBC_[\d.]+/.exec(message)[0]} or newer ` +
      '(Ubuntu 22.04, Debian 12, RHEL 9 and later). glibc is the system loader itself, so a ' +
      'package cannot bring its own — the host or base image has to be newer.',
  },
];

function isMusl() {
  if (process.platform !== 'linux') return false;
  try {
    return readdirSync('/lib').some((f) => f.startsWith('ld-musl-'));
  } catch {
    return false;
  }
}

/**
 * @param {unknown} err  what require() threw
 * @param {{ name?: string, musl?: boolean }} [options]
 *   name: the package users installed, so the message starts with something
 *   they recognise. musl: override detection (tests).
 * @returns {unknown} an explained Error with `code` and `cause`, or `err` itself
 */
function explainLoadError(err, { name = 'native addon', musl } = {}) {
  if (!err || err.code === 'MODULE_NOT_FOUND') return err;
  const message = String(err.message || err);
  if (!LOAD_FAILURE.test(message)) return err;
  const onMusl = musl === undefined ? isMusl() : musl;
  const match = CASES.find((c) => c.applies(message, onMusl));
  if (!match) return err;
  const explained = new Error(
    `${name}: ${match.text(message)}\n  See ${DOCS}#${match.anchor}\n  Loader said: ${message}`,
    { cause: err }
  );
  explained.code = match.code;
  return explained;
}

module.exports = { explainLoadError };
