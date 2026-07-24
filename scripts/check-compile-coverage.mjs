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

const defined = new Map(); // name -> Set of files declaring it
for (const file of readdirSync(FRAMEWORK_DIR).filter((f) => f.endsWith('.mojo'))) {
  const src = readFileSync(`${FRAMEWORK_DIR}/${file}`, 'utf8');
  for (const m of src.matchAll(/^\s*def ([a-z][a-z0-9_]*)\s*[[(]/gm)) {
    if (!defined.has(m[1])) defined.set(m[1], new Set());
    defined.get(m[1]).add(file);
  }
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
