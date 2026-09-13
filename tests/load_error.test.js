'use strict';
// load-error.js turns the loader's raw dlopen message into one that says what
// to do. The people who hit these are often users of SOMEONE ELSE'S addon, in
// a container log, who have never heard of napi-mojo — so the message is the
// documentation. These tests pin each failure class to its advice, and pin the
// docs anchors the advice links to.
const fs = require('fs');
const path = require('path');
const { explainLoadError } = require('../load-error.js');

// The loader's own phrasing, as Bun, Deno and Node surface it on glibc.
const MESSAGES = {
  noCxx: 'libstdc++.so.6: cannot open shared object file: No such file or directory',
  noGccS: 'Error loading: libgcc_s.so.1: cannot open shared object file: No such file or directory',
  oldCxx: "/lib/x86_64-linux-gnu/libstdc++.so.6: version `GLIBCXX_3.4.30' not found (required by /w/libKGENCompilerRTShared.so)",
  oldGlibc: "/lib/x86_64-linux-gnu/libc.so.6: version `GLIBC_2.35' not found (required by /w/libAsyncRTRuntimeGlobals.so)",
  musl: 'Error loading shared library libstdc++.so.6: No such file or directory (needed by /app/node_modules/x-linux-x64/libKGENCompilerRTShared.so)',
};
const explain = (message, opts = {}) =>
  explainLoadError(new Error(message), { name: 'my-addon', musl: false, ...opts });

describe('explainLoadError', () => {
  test('a missing C++ runtime names the images and the fix', () => {
    for (const m of [MESSAGES.noCxx, MESSAGES.noGccS]) {
      const e = explain(m);
      expect(e.code).toBe('ERR_NATIVE_NO_CXX_RUNTIME');
      expect(e.message).toMatch(/^my-addon: /);
      expect(e.message).toContain('oven/bun:*-slim');
      expect(e.message).toContain('denoland/deno:distroless');
      expect(e.message).toContain('#missing-cpp-runtime');
    }
  });

  test('an old libstdc++ reports the version it needs', () => {
    const e = explain(MESSAGES.oldCxx);
    expect(e.code).toBe('ERR_NATIVE_LIBSTDCXX_TOO_OLD');
    expect(e.message).toContain('GLIBCXX_3.4.30');
  });

  test('an old glibc reports the floor and that it cannot be bundled', () => {
    const e = explain(MESSAGES.oldGlibc);
    expect(e.code).toBe('ERR_NATIVE_GLIBC_TOO_OLD');
    expect(e.message).toContain('GLIBC_2.35');
    expect(e.message).toMatch(/Ubuntu 22\.04/);
  });

  test('musl is reported as musl, even though the message names libstdc++', () => {
    const e = explain(MESSAGES.musl, { musl: true });
    expect(e.code).toBe('ERR_NATIVE_MUSL');
    expect(e.message).toMatch(/musl/);
  });

  test('the original error is kept as the cause and quoted', () => {
    const original = new Error(MESSAGES.noCxx);
    const e = explainLoadError(original, { name: 'my-addon', musl: false });
    expect(e.cause).toBe(original);
    expect(e.message).toContain(MESSAGES.noCxx);
  });

  test('anything unrecognised comes back untouched', () => {
    const notFound = Object.assign(new Error("Cannot find module 'my-addon-linux-x64'"), { code: 'MODULE_NOT_FOUND' });
    expect(explainLoadError(notFound, { musl: true })).toBe(notFound);
    const other = new Error('napi_register_module_v1 threw');
    expect(explainLoadError(other, { musl: false })).toBe(other);
    // musl alone is not evidence: only a LOAD failure on musl is.
    expect(explainLoadError(other, { musl: true })).toBe(other);
  });

  test('every docs link resolves to an anchor that exists', () => {
    const doc = fs.readFileSync(path.join(__dirname, '..', 'docs', 'TROUBLESHOOTING.md'), 'utf8');
    const src = fs.readFileSync(path.join(__dirname, '..', 'load-error.js'), 'utf8');
    const anchors = [...src.matchAll(/anchor: '([a-z0-9-]+)'/g)].map((m) => m[1]);
    expect(anchors.length).toBeGreaterThanOrEqual(4);
    for (const a of anchors) expect(doc).toContain(`<a id="${a}"></a>`);
    // Bun exits 0 on `bun -e "require(x)"` when x throws, so a documented
    // Bun check using require can never fail. publish.yml builds the doc's
    // own line; this keeps a require form from being written back in.
    const bunChecks = doc.match(/^RUN \["bun", [^\n]*$/gm) || [];
    expect(bunChecks.length).toBeGreaterThanOrEqual(1);
    for (const line of bunChecks) expect(line).not.toMatch(/require\(/);
    // The exact loader strings users search for are in the doc verbatim.
    for (const s of ['libstdc++.so.6: cannot open shared object file', "version `GLIBC_", "version `GLIBCXX_"]) {
      expect(doc).toContain(s);
    }
  });

  test('the images the doc calls checked are the ones the release job checks', () => {
    const read = (...p) => fs.readFileSync(path.join(__dirname, '..', ...p), 'utf8');
    const doc = read('docs', 'TROUBLESHOOTING.md');
    const publish = read('.github', 'workflows', 'publish.yml');
    const testYml = read('.github', 'workflows', 'test.yml');

    // One version per runtime, and the same one everywhere: the doc's
    // images, publish.yml's env pins, and the runtimes job in test.yml.
    const pins = {
      BUN_VERSION: { image: 'oven/bun', testYml: /bun-version:\s*'?([\d.]+)/ },
      DENO_VERSION: { image: 'denoland/deno', testYml: /deno-version:\s*'?v?([\d.]+)/ },
    };
    for (const [envVar, { image, testYml: re }] of Object.entries(pins)) {
      const inPublish = [...publish.matchAll(new RegExp(`${envVar}: '([\\d.]+)'`, 'g'))].map((m) => m[1]);
      expect(inPublish.length).toBeGreaterThan(0);
      expect(new Set(inPublish).size).toBe(1);
      expect(re.exec(testYml)[1]).toBe(inPublish[0]);
      for (const m of doc.matchAll(new RegExp(`${image.replace('/', '\\/')}:([\\w.-]+)`, 'g'))) {
        if (/\d/.test(m[1])) expect(m[1]).toContain(inPublish[0]);
      }
    }

    // Every row marked "checked on every release" names an image publish.yml
    // actually runs — written there with the version as its env var.
    const rows = [...doc.matchAll(/^\| `([^`]+)` \|([^|\n]*)\| checked on every release \|$/gm)];
    expect(rows.length).toBeGreaterThanOrEqual(4);
    for (const [, image, runtime] of rows) {
      const templated = image
        .replace(/oven\/bun:[\d.]+/, 'oven/bun:${BUN_VERSION}')
        .replace(/denoland\/deno:(\w+-)?[\d.]+/, (_, v) => `denoland/deno:${v || ''}\${DENO_VERSION}`);
      if (/fix/.test(runtime)) {
        // The fix is built from the doc's own recipe, extracted by heading.
        expect(publish).toContain('Fix: copy the C\\+\\+ runtime in');
        expect(publish).toContain(`FROM ${templated}`);
      } else {
        expect(publish).toContain(templated);
      }
    }
  });
});
