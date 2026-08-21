// The set of framework modules that `mojo doc` is pointed at, shared by the
// two callers that must not disagree about it:
//
//   - scripts/check-docstring-coverage.mjs  — the ratcheting coverage gate
//   - scripts/generate-api-reference.mjs    — the Markdown renderer
//
// One definition, two callers, for the same reason scripts/toml-dts.js is one
// emitter with two callers: a reference that silently covers a different set of
// modules than the gate measures would let an undocumented module look
// documented, or drop a documented one from the published reference.

import { readdirSync } from 'node:fs';

export const FRAMEWORK_DIR = 'src/napi/framework';

// Beyond framework/, these carry public defs a consumer calls directly.
// DELIBERATELY OUT OF SCOPE, and this list is the whole argument:
//   - raw.mojo      147 thin FFI wrappers over cached symbol slots. An
//                   implementation detail; documenting each would be
//                   restating its N-API name. Out of the reference too
//                   (docs/plan-api-reference.md, step 3).
//   - bindings.mojo the symbol cache; consumers hold the pointer, never
//                   touch the fields.
//   - types.mojo    aliases and constants, no def bodies.
export const EXTRA_FILES = ['src/napi/error.mojo', 'src/napi/module.mojo'];

// `mojo doc` compiles the file NAMED ON THE COMMAND LINE as a main module, even
// with -I src. That is the exact context in which an explicit
//   def __moveinit__(out self, deinit take: Self)
// fails with `'None' has no attributes` on `self` — a Mojo bug CLAUDE.md already
// documents, and which does not fire when the same file is compiled as part of
// the package (build.sh compiles all three of these every run).
//
// So these are not undocumentable code; they are files the doc tool cannot
// open. The coverage gate FAILS if one of them starts succeeding — that is the
// signal to delete its entry here and fold the file back into the floor and
// into the reference.
export const KNOWN_UNDOCUMENTABLE = {
  'src/napi/framework/js_string.mojo': 'explicit __moveinit__ on Latin1Buf',
  'src/napi/framework/js_mojo_array.mojo': 'explicit __moveinit__ on MojoFloat64Array',
  'src/napi/framework/register.mojo': 'explicit __moveinit__ on ClassRegistry',
};

/** Every module the doc tooling considers, sorted and stable. */
export function docTargets() {
  return [
    ...readdirSync(FRAMEWORK_DIR)
      .filter((f) => f.endsWith('.mojo'))
      .map((f) => `${FRAMEWORK_DIR}/${f}`),
    ...EXTRA_FILES,
  ].sort();
}

/** Resolve the Mojo driver the same way every script in this repo does. */
export function resolveMojo(argv = process.argv.slice(2)) {
  const i = argv.indexOf('--mojo');
  return (
    (i >= 0 ? argv[i + 1] : undefined) ??
    process.env.NAPI_MOJO_MOJO ??
    'pixi run mojo'
  );
}
