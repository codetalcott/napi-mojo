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
// A file `mojo doc` cannot open at all is a separate case from an undocumented
// one, and is handled by KNOWN_UNDOCUMENTABLE below rather than by a zero count.
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

// `mojo doc` compiles the file NAMED ON THE COMMAND LINE as a main module, even
// with -I src. That is the exact context in which an explicit
//   def __moveinit__(out self, deinit take: Self)
// fails with `'None' has no attributes` on `self` — a Mojo bug CLAUDE.md already
// documents, and which does not fire when the same file is compiled as part of
// the package (build.sh compiles all three of these every run).
//
// So these are not undocumentable code; they are files the doc tool cannot open.
// They are excluded from the counts, and the script FAILS if one of them starts
// succeeding — that is the signal to delete its entry here and fold the file
// back into the floor.
const KNOWN_UNDOCUMENTABLE = {
  'src/napi/framework/js_string.mojo': "explicit __moveinit__ on Latin1Buf",
  'src/napi/framework/js_mojo_array.mojo': "explicit __moveinit__ on MojoFloat64Array",
  'src/napi/framework/register.mojo': "explicit __moveinit__ on ClassRegistry",
};

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

// Two invocation constraints, both verified on the 1.0.0 pin:
//   -I src   — without it the package imports do not resolve at all. It does
//              NOT make the target file itself a package member; see
//              KNOWN_UNDOCUMENTABLE above.
//   a file   — a directory argument produces no output whatsoever.
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
//
// The diagnostic prints an ABSOLUTE path (`/…/napi-mojo/src/napi/…`), so the
// repo-relative path is matched as a path *suffix* — hence `/` in the leading
// character class alongside line-start and whitespace. Requiring the whole
// relative path keeps that unambiguous: no target here is a path-suffix of
// another. (A first version anchored on line-start only, measured 0 everywhere
// in CI, and looked like perfect coverage.)
function countFor(file, output) {
  const escaped = file.replaceAll('.', '\\.').replaceAll('/', '[/\\\\]');
  const re = new RegExp(
    `(?:^|[\\s'"/])${escaped}:\\d+:\\d+: warning: public symbol .* is missing a doc string`,
    'gm'
  );
  return [...output.matchAll(re)].length;
}

const runs = await pool(targets, Math.max(2, cpus().length - 1), run);

// Show the diagnostics that actually stopped it, not a blind tail: `mojo doc`
// emits every missing-docstring warning first, so the tail is all warnings and
// the error that matters has scrolled off.
function errorLines(out) {
  const lines = out.split('\n').filter((l) => /: error: /.test(l));
  return lines.length > 0 ? lines.join('\n') : out.trim().split('\n').slice(-10).join('\n');
}

const brokeUnexpectedly = runs.filter((r) => r.code !== 0 && !(r.file in KNOWN_UNDOCUMENTABLE));
if (brokeUnexpectedly.length > 0) {
  console.error(`\`${mojoCmd} doc\` failed on ${brokeUnexpectedly.length} file(s):\n`);
  for (const r of brokeUnexpectedly) {
    console.error(`--- ${r.file} (exit ${r.code}) ---`);
    console.error(errorLines(r.out));
    console.error('');
  }
  console.error(
    'A doc failure is a real finding, not gate noise: it type-checks declarations\n' +
      'the build never elaborates. If it is genuinely the main-module __moveinit__\n' +
      'bug, add the file to KNOWN_UNDOCUMENTABLE with that reason.\n'
  );
  process.exit(1);
}

const skipHealed = runs.filter((r) => r.code === 0 && r.file in KNOWN_UNDOCUMENTABLE);
// Only a gate concern; --print and --update stay usable while a skip is stale.
if (mode === 'check' && skipHealed.length > 0) {
  console.error(`${skipHealed.length} file(s) in KNOWN_UNDOCUMENTABLE now document cleanly:\n`);
  for (const r of skipHealed) console.error(`  ${r.file}  (was: ${KNOWN_UNDOCUMENTABLE[r.file]})`);
  console.error(
    '\nDelete those entries from scripts/check-docstring-coverage.mjs and run\n' +
      '  node scripts/check-docstring-coverage.mjs --update\n' +
      'so the files enter the floor.\n'
  );
  process.exit(1);
}

const counts = Object.fromEntries(
  runs
    .filter((r) => !(r.file in KNOWN_UNDOCUMENTABLE))
    .map((r) => [r.file, countFor(r.file, r.out)])
    .sort((a, b) => a[0].localeCompare(b[0]))
);
const total = Object.values(counts).reduce((a, b) => a + b, 0);

// Self-check on the parser, not a heuristic. If mojo doc printed the phrase
// anywhere and countFor matched none of it, the regex is broken — which is
// exactly what a path-format change does, and the resulting all-zeros reads as
// PERFECT coverage. (It happened: the first CI run measured 0 everywhere
// because the diagnostic prints absolute paths and the pattern was anchored on
// line-start.) When the repo really is fully documented the phrase is absent
// and this stays quiet.
const sawPhrase = runs.some(
  (r) => !(r.file in KNOWN_UNDOCUMENTABLE) && r.out.includes('is missing a doc string')
);
if (total === 0 && sawPhrase) {
  console.error(
    'Parser check failed: `mojo doc` reported missing docstrings, but this script\n' +
      'matched none of them. countFor() has drifted from the diagnostic format —\n' +
      'fix the pattern rather than committing a floor of zeros.\n\nSample:\n'
  );
  const sample = runs
    .flatMap((r) => r.out.split('\n'))
    .filter((l) => l.includes('is missing a doc string'))
    .slice(0, 3);
  console.error(sample.join('\n'));
  process.exit(1);
}

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

const nSkipped = Object.keys(KNOWN_UNDOCUMENTABLE).length;
console.log(
  `docstring coverage: ${total} undocumented public symbols across ` +
    `${Object.keys(counts).length} consumer-facing modules, at or below the floor in ` +
    `${FLOOR_FILE} (${floorTotal}). ${nSkipped} module(s) skipped — mojo doc cannot ` +
    `open them (see KNOWN_UNDOCUMENTABLE).`
);
