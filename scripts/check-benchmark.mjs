#!/usr/bin/env node
// Per-call overhead regression gate.
//
// WHAT THIS CAN AND CANNOT DETECT — read this before trusting a green run.
//
// It runs on shared GitHub runners with noisy neighbours, so it is calibrated
// to catch an ORDER-OF-MAGNITUDE regression, not a 10% one. That is not a
// consolation prize: the regression this repo actually has to fear is
// structural — reintroducing a per-call `OwnedDLHandle()` + dlsym, which is
// what the whole cached-NapiBindings design exists to avoid, and which costs
// 10-100x per call. A gate that reliably catches that and honestly admits it
// cannot see 10% is worth more than one tuned so tight it cries wolf and gets
// ignored.
//
// Ceilings are per platform (scripts/benchmark-ceilings.json), because
// darwin-arm64 and linux-x64 are not comparable, and are set well above the
// measured value. Every run prints observed/ceiling as a percentage even when
// passing, so a slow creep is visible to a human reading the log before it
// ever trips the gate.
//
// It compares MEDIAN ns/call, not mean: the mean is dragged around by GC
// pauses and runner preemption, and on a shared runner that noise is the
// dominant term.
//
// This is a NON-REQUIRED job. A timing measurement must never be able to block
// a merge — see the required-checks note in .github/workflows/test.yml.
//
// Usage:
//   node scripts/check-benchmark.mjs           # measure and check
//   node scripts/check-benchmark.mjs --update  # rewrite this platform's ceilings
//   node scripts/check-benchmark.mjs --print   # measure only

import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, existsSync } from 'node:fs';

const CEILINGS_FILE = 'scripts/benchmark-ceilings.json';

// Headroom applied to a measured median when seeding a ceiling. Generous on
// purpose: see the note at the top about what this gate is for.
//
// SEED FROM A NOISY RUN, NEVER A LUCKY ONE. Two runs of the SAME COMMIT on
// ubuntu-latest differed by 1.5-1.8x (hello() 149.4 then 263.7 ns). Seeding
// from the fast one left barely 2.3x of real margin while the file said "4x".
// If you reseed, run it a few times and keep the highest, or re-check that the
// resulting percentages below sit near 25%, not near 50%.
const HEADROOM = 4;

// Warn (do not fail) above this fraction of ceiling. Run-to-run noise puts a
// healthy benchmark around 25-45%; sustained 75%+ means either a real creep or
// a ceiling seeded from a lucky run. Both want a human, neither wants a red X.
const WARN_AT = 0.75;

const args = process.argv.slice(2);
const mode = args.includes('--update') ? 'update' : args.includes('--print') ? 'print' : 'check';

let raw;
try {
  raw = execFileSync(process.execPath, ['scripts/benchmark.mjs', '--json'], {
    encoding: 'utf8',
    maxBuffer: 16 * 1024 * 1024,
  });
} catch (err) {
  console.error('benchmark.mjs failed to run:\n');
  console.error(err.stderr || err.message);
  console.error('\nIs build/index.node present? Run `pixi run bash build.sh` first.');
  process.exit(1);
}

const measured = JSON.parse(raw);
const { platform, results } = measured;
const names = Object.keys(results);

if (names.length === 0) {
  console.error('benchmark.mjs reported no results — nothing was measured.');
  process.exit(1);
}

if (mode === 'print') {
  console.log(raw);
  process.exit(0);
}

const all = existsSync(CEILINGS_FILE) ? JSON.parse(readFileSync(CEILINGS_FILE, 'utf8')) : {};

if (mode === 'update') {
  all[platform] = Object.fromEntries(
    names.map((n) => [n, Math.ceil((results[n].median * HEADROOM) / 10) * 10])
  );
  writeFileSync(CEILINGS_FILE, `${JSON.stringify(all, null, 2)}\n`);
  console.log(`wrote ${CEILINGS_FILE} for ${platform} (${names.length} benchmarks, ${HEADROOM}x headroom)`);
  process.exit(0);
}

const ceilings = all[platform];
if (!ceilings) {
  console.error(
    `No ceilings recorded for platform "${platform}" in ${CEILINGS_FILE}.\n\n` +
      `Seed them on a runner of that platform:\n\n` +
      `  node scripts/check-benchmark.mjs --update\n\n` +
      `Measured now (median ns/call):\n`
  );
  console.error(
    JSON.stringify(
      Object.fromEntries(names.map((n) => [n, results[n].median])),
      null,
      2
    )
  );
  process.exit(1);
}

const over = [];
const rows = [];
for (const name of names) {
  const median = results[name].median;
  const ceiling = ceilings[name];
  if (ceiling === undefined) {
    over.push({ name, median, ceiling: null });
    continue;
  }
  const pct = (median / ceiling) * 100;
  rows.push({ name, median, ceiling, pct });
  if (median > ceiling) over.push({ name, median, ceiling });
}

// Always print the table. A passing run that shows 70% of ceiling is a signal
// a human should see; only printing on failure hides the creep.
console.log(`per-call overhead on ${platform} (${measured.node}), median ns/call:\n`);
for (const r of rows.sort((a, b) => b.pct - a.pct)) {
  const bar = r.pct > 100 ? 'OVER' : `${r.pct.toFixed(0)}%`;
  console.log(
    `  ${r.name.padEnd(26)} ${String(r.median).padStart(8)}  ceiling ${String(r.ceiling).padStart(6)}  ${bar}`
  );
}

const warm = rows.filter((r) => r.pct >= WARN_AT * 100 && r.pct <= 100);
if (warm.length > 0) {
  console.log(
    `\n::warning::${warm.length} benchmark(s) above ${WARN_AT * 100}% of ceiling — ` +
      `either overhead is creeping or the ceiling was seeded from a lucky run: ` +
      warm.map((r) => `${r.name} ${r.pct.toFixed(0)}%`).join(', ')
  );
}

const missing = names.filter((n) => ceilings[n] === undefined);
const stale = Object.keys(ceilings).filter((n) => !names.includes(n));

if (missing.length > 0) {
  console.error(`\n${missing.length} benchmark(s) have no ceiling for ${platform}:\n`);
  // Print the observed median alongside, so a platform you cannot get an
  // interactive shell on (a CI runner) can still be seeded: read the numbers
  // out of this log and write them in with the same HEADROOM the updater uses.
  for (const n of missing) {
    const median = results[n].median;
    console.error(
      `  ${n.padEnd(26)} observed ${String(median).padStart(8)}  ` +
        `suggested ceiling ${Math.ceil((median * HEADROOM) / 10) * 10}`
    );
  }
  console.error(`\nRun --update on a ${platform} runner and commit ${CEILINGS_FILE}.`);
}
if (stale.length > 0) {
  console.error(`\n${stale.length} ceiling(s) for ${platform} no longer correspond to a benchmark:\n`);
  for (const n of stale) console.error(`  ${n}`);
  console.error(`\nRun --update and commit ${CEILINGS_FILE}.`);
}

const exceeded = over.filter((o) => o.ceiling !== null);
if (exceeded.length > 0) {
  console.error(`\n${exceeded.length} benchmark(s) exceeded their ceiling:\n`);
  for (const o of exceeded) {
    console.error(
      `  ${o.name}: ${o.median} ns/call > ${o.ceiling} (${((o.median / o.ceiling) * 100).toFixed(0)}%)`
    );
  }
  console.error(
    `\nThe ceilings carry ${HEADROOM}x headroom, so this is very unlikely to be runner\n` +
      `noise. The regression to suspect first is a per-call OwnedDLHandle() + dlsym\n` +
      `that should have used the cached NapiBindings — check whether the callback\n` +
      `path reaches a raw_* wrapper without a Bindings argument.\n`
  );
}

if (exceeded.length > 0 || missing.length > 0 || stale.length > 0) process.exit(1);

console.log(`\nAll ${rows.length} benchmarks within ceiling.`);
