#!/usr/bin/env node
// Ratcheting docstring-coverage gate for the consumer-facing framework surface.
//
// `mojo doc --diagnose-missing-doc-strings` emits one warning per undocumented
// public symbol:
//
//   src/napi/framework/js_object.mojo:98:9: warning: public symbol
//     'set_named_property' is missing a doc string
//
// This script runs that over the modules a consumer actually imports, counts
// the warnings per file, and compares against a floor committed at
// scripts/docstring-floor.json. The count may go DOWN (which requires lowering
// the floor in the same commit) but never UP.
//
// Why the compiler's notion and not a regex: `"""` placement rules are the
// language's, and a hand-rolled scanner would drift from them silently. This
// gate cannot — it is asking Mojo itself.
//
// Why per-file and not one total: a single number lets documenting one module
// pay for regressing another. Per-file also makes the failure message name the
// file, which is the only thing the author needs.
//
// Usage:
//   node scripts/check-docstring-coverage.mjs            # check against floor
//   node scripts/check-docstring-coverage.mjs --update   # rewrite the floor
//   node scripts/check-docstring-coverage.mjs --print    # emit counts, no check
//
// The Mojo driver defaults to `pixi run mojo`, matching the rest of CI.
// Override with $NAPI_MOJO_MOJO or --mojo "<command>".

import { execFile } from 'node:child_process';
import { readFileSync, writeFileSync, existsSync, readdirSync, mkdtempSync } from 'node:fs';
import { tmpdir, cpus } from 'node:os';
import { join } from 'node:path';

const FLOOR_FILE = 'scripts/docstring-floor.json';
const FRAMEWORK_DIR = 'src/napi/framework';

// Beyond framework/, these carry public defs a consumer calls directly.
// DELIBERATELY OUT OF SCOPE, and this list is the whole argument:
//   - raw.mojo      147 thin FFI wrappers over cached symbol slots. An
//                   implementation detail; documenting each would be
//                   restating its N-API name. Out of the reference too
//                   (docs/plan-api-reference.md, step 3).
//   - bindings.mojo the symbol cache; consumers hold the pointer, never
//                   touch the fields.
//   - types.mojo    aliases and constants, no def bodies.
const EXTRA_FILES = ['src/napi/error.mojo', 'src/napi/module.mojo'];

const args = process.argv.slice(2);
const mode = args.includes('--update')
  ? 'update'
  : args.includes('--print')
    ? 'print'
    : 'check';
const mojoIdx = args.indexOf('--mojo');
const mojoCmd =
  (mojoIdx >= 0 ? args[mojoIdx + 1] : undefined) ??
  process.env.NAPI_MOJO_MOJO ??
  'pixi run mojo';

const targets = [
  ...readdirSync(FRAMEWORK_DIR)
    .filter((f) => f.endsWith('.mojo'))
    .map((f) => `${FRAMEWORK_DIR}/${f}`),
  ...EXTRA_FILES,
].sort();

const scratch = mkdtempSync(join(tmpdir(), 'napi-mojo-doc-'));

// `mojo doc` needs -I src (a bare path is treated as a main module, which
// fails on explicit __moveinit__) and needs a file, not a directory (a
// directory produces no output at all). Both verified on the 1.0.0 pin.
function run(file) {
  const [bin, ...rest] = mojoCmd.split(/\s+/);
  const argv = [
    ...rest,
    'doc',
    '--diagnose-missing-doc-strings',
    '-I',
    'src',
    file,
    '-o',
    join(scratch, `${file.replaceAll('/', '_')}.json`),
  ];
  return new Promise((resolve) => {
    execFile(bin, argv, { maxBuffer: 64 * 1024 * 1024 }, (err, stdout, stderr) => {
      resolve({ file, code: err?.code ?? 0, out: `${stdout}${stderr}` });
    });
  });
}

async function pool(items, limit, worker) {
  const results = new Array(items.length);
  let next = 0;
  await Promise.all(
    Array.from({ length: Math.min(limit, items.length) }, async () => {
      while (next < items.length) {
        const i = next++;
        results[i] = await worker(items[i]);
      }
    })
  );
  return results;
}

// Only count warnings attributed to the file under test. With -I src the
// driver walks imported modules too, and without this filter a symbol in
// js_string.mojo would be charged to every file that imports it.
function countFor(file, output) {
  const escaped = file.replaceAll('.', '\\.').replaceAll('/', '[/\\\\]');
  const re = new RegExp(
    `(?:^|[\\s'"])${escaped}:\\d+:\\d+: warning: public symbol .* is missing a doc string`,
    'gm'
  );
  return [...output.matchAll(re)].length;
}

const runs = await pool(targets, Math.max(2, cpus().length - 1), run);

const failed = runs.filter((r) => r.code !== 0);
if (failed.length > 0) {
  console.error(`\`${mojoCmd} doc\` failed on ${failed.length} file(s):\n`);
  for (const r of failed) {
    console.error(`--- ${r.file} (exit ${r.code}) ---`);
    console.error(r.out.trim().split('\n').slice(-20).join('\n'));
  }
  process.exit(1);
}

const counts = Object.fromEntries(
  runs.map((r) => [r.file, countFor(r.file, r.out)]).sort((a, b) => a[0].localeCompare(b[0]))
);
const total = Object.values(counts).reduce((a, b) => a + b, 0);

if (mode === 'print') {
  console.log(JSON.stringify(counts, null, 2));
  console.log(`\ntotal undocumented public symbols: ${total}`);
  process.exit(0);
}

if (mode === 'update') {
  writeFileSync(FLOOR_FILE, `${JSON.stringify(counts, null, 2)}\n`);
  console.log(`wrote ${FLOOR_FILE} (${total} undocumented public symbols)`);
  process.exit(0);
}

if (!existsSync(FLOOR_FILE)) {
  console.error(
    `${FLOOR_FILE} does not exist. Seed it from a machine (or CI job) that has ` +
      `the Mojo toolchain:\n\n  node scripts/check-docstring-coverage.mjs --update\n\n` +
      `Measured now:\n`
  );
  console.error(JSON.stringify(counts, null, 2));
  process.exit(1);
}

const floor = JSON.parse(readFileSync(FLOOR_FILE, 'utf8'));
const floorTotal = Object.values(floor).reduce((a, b) => a + b, 0);

const regressed = [];
const improved = [];
const added = [];
for (const [file, n] of Object.entries(counts)) {
  if (!(file in floor)) {
    added.push([file, n]);
  } else if (n > floor[file]) {
    regressed.push([file, floor[file], n]);
  } else if (n < floor[file]) {
    improved.push([file, floor[file], n]);
  }
}
const removed = Object.keys(floor).filter((f) => !(f in counts));

let bad = false;

if (regressed.length > 0) {
  bad = true;
  console.error('Docstring coverage regressed — new public symbols without a `"""` docstring:\n');
  for (const [file, was, now] of regressed) {
    console.error(`  ${file}: ${was} -> ${now}  (+${now - was})`);
  }
  console.error(
    '\nAdd a `"""…"""` docstring under each new public def. The convention and\n' +
      'an example are in CONTRIBUTING.md. To see the exact symbols:\n\n' +
      `  ${mojoCmd} doc --diagnose-missing-doc-strings -I src <file> -o /dev/null\n`
  );
}

if (added.length > 0) {
  bad = true;
  console.error(`\n${added.length} module(s) are not in ${FLOOR_FILE}:\n`);
  for (const [file, n] of added) console.error(`  ${file}: ${n} undocumented`);
  console.error(
    '\nA new module enters the gate at whatever it measures. Run\n' +
      '  node scripts/check-docstring-coverage.mjs --update\n' +
      'and commit the floor — but a brand-new module should be documented, so\n' +
      'prefer writing the docstrings over admitting a large number.\n'
  );
}

if (improved.length > 0) {
  bad = true;
  console.error(
    `\nThe floor is stale — ${improved.length} module(s) are now BETTER than it records:\n`
  );
  for (const [file, was, now] of improved) {
    console.error(`  ${file}: ${was} -> ${now}  (${now - was})`);
  }
  console.error(
    '\nThat is the good direction, but the floor has to move with it or the\n' +
      'coverage you just added can be silently undone. Run\n' +
      '  node scripts/check-docstring-coverage.mjs --update\n' +
      'and commit the result in the same change.\n'
  );
}

if (removed.length > 0) {
  bad = true;
  console.error(`\n${removed.length} module(s) in ${FLOOR_FILE} no longer exist:\n`);
  for (const f of removed) console.error(`  ${f}`);
  console.error('\nRun --update and commit the floor.\n');
}

if (bad) process.exit(1);

console.log(
  `docstring coverage: ${total} undocumented public symbols across ` +
    `${targets.length} consumer-facing modules, at or below the floor in ${FLOOR_FILE} ` +
    `(${floorTotal}).`
);
