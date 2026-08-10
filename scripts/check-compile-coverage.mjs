#!/usr/bin/env node
// Drift guard for tests/compile/framework_coverage.mojo.
//
// Every public `def` name in src/napi/framework/ must be referenced by the
// coverage target, so a newly added framework method cannot slip in without a
// cover call. Run after the coverage build in CI.
//
// KNOWN LIMIT, stated plainly because it matters: this checks NAMES, not
// overloads. If a method already covered gains a second (env-only or Bindings)
// overload, this script stays silent — and that is precisely the case that bit
// 0.5.1, where both JsArrayBuffer.create overloads were broken. Covering each
// overload is a rule for the author and the reviewer (see the header of
// framework_coverage.mojo); the compiler enforces it only once the call exists.
//
// Underscore-private helpers are excluded by the leading [a-z] class: they
// elaborate transitively through the public methods that call them.

import { readFileSync, readdirSync } from 'node:fs';

const FRAMEWORK_DIR = 'src/napi/framework';
const COVERAGE_FILE = 'tests/compile/framework_coverage.mojo';

// Beyond framework/, these top-level src/napi files carry public defs that
// are just as lazily elaborated. They were originally outside this gate's
// scope, which is how a dead get_bindings() with a broken body sat in
// bindings.mojo unchecked for months. NOT scanned, with reasons:
//   - raw.mojo: its 270+ raw_* wrappers elaborate transitively through the
//     framework methods (and addon except-blocks) that call them; listing
//     them here would demand 270 redundant cover calls.
//   - bindings.mojo: init_bindings is called from src/lib.mojo, which is the
//     eagerly-checked main module — everything live in that file is rooted.
//   - types.mojo: type aliases and constants, no def bodies worth rooting.
const EXTRA_FILES = ['src/napi/error.mojo', 'src/napi/module.mojo'];

const defined = new Map(); // name -> Set of files declaring it
function scanFile(displayName, srcPath) {
  const src = readFileSync(srcPath, 'utf8');
  for (const m of src.matchAll(/^\s*def ([a-z][a-z0-9_]*)\s*[[(]/gm)) {
    if (!defined.has(m[1])) defined.set(m[1], new Set());
    defined.get(m[1]).add(displayName);
  }
}
for (const file of readdirSync(FRAMEWORK_DIR).filter((f) => f.endsWith('.mojo'))) {
  scanFile(file, `${FRAMEWORK_DIR}/${file}`);
}
for (const path of EXTRA_FILES) {
  scanFile(path, path);
}

const coverage = readFileSync(COVERAGE_FILE, 'utf8');
// A cover call reads `Type.name(`, `.name(`, `name(` or `name[T](`, so match the
// bare identifier preceded by a non-identifier character.
const missing = [...defined.keys()]
  .filter((name) => !new RegExp(`[^A-Za-z0-9_]${name}\\s*[[(]`).test(coverage))
  .sort();

if (missing.length > 0) {
  console.error(
    `${COVERAGE_FILE} is missing a call for ${missing.length} public framework ` +
      `method name(s).\nMojo type-checks a method body only when something calls ` +
      `it, so an uncovered method can ship broken:\n`
  );
  for (const name of missing) {
    console.error(`  ${name}  (${[...defined.get(name)].sort().join(', ')})`);
  }
  console.error(
    `\nAdd a call to the matching cover_<module>() function — one per overload.`
  );
  process.exit(1);
}

console.log(
  `compile coverage: all ${defined.size} public framework method names are called ` +
    `by ${COVERAGE_FILE}`
);
