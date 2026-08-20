#!/usr/bin/env node
/**
 * compare.mjs — napi-mojo vs napi-rs, per-call boundary overhead.
 *
 * README.md has listed "performance benchmarking against napi-rs" as missing
 * since the project started. For a framework whose one-line pitch is "the Mojo
 * equivalent of napi-rs", this is the number people actually want.
 *
 * METHOD, and why it is fair
 *
 *  - Both addons are loaded into ONE Node process and timed by the SAME code:
 *    measure() from scripts/bench-harness.mjs, which scripts/benchmark.mjs
 *    also uses. Not a copy of the harness — the same import.
 *  - Every function pair has verified-identical semantics (see --verify): same
 *    argument types, same return values, same string lengths. What is measured
 *    is the boundary, not the callee.
 *  - Runs are INTERLEAVED and repeated (--rounds, default 3), taking the
 *    per-pair minimum of medians. Thermal drift and scheduler noise on a
 *    laptop are slow relative to a round, so alternating A/B/A/B and taking
 *    minima removes the drift that running all of A then all of B would bake
 *    straight into the comparison.
 *  - The Rust side is idiomatic #[napi] macro code built with `napi build
 *    --release`, i.e. what a napi-rs user actually ships. Hand-rolling raw
 *    napi_ calls there would beat the framework being compared.
 *
 * WHAT THIS IS NOT: a throughput benchmark. It measures the cost of crossing
 * the JS/native boundary and nothing else. Neither framework's compute
 * performance is in evidence here — that is the language's business, not the
 * binding layer's.
 *
 * Usage:
 *   node compare.mjs [--rounds N] [--json] [--verify]
 */
import { createRequire } from 'node:module';
import { existsSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { measure, BATCH_SIZE, BATCHES } from '../../scripts/bench-harness.mjs';

const require = createRequire(import.meta.url);
const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..', '..');

const JSON_MODE = process.argv.includes('--json');
const VERIFY_ONLY = process.argv.includes('--verify');
const ROUNDS = Number(
  process.argv[process.argv.indexOf('--rounds') + 1] > 0
    ? process.argv[process.argv.indexOf('--rounds') + 1]
    : 3
);

const mojoPath = join(ROOT, 'build', 'index.node');
if (!existsSync(mojoPath)) {
  console.error('build/index.node not found — run `pixi run bash build.sh`.');
  process.exit(1);
}
const rustName = readdirSync(HERE).find(
  (f) => f.startsWith('baseline.') && f.endsWith('.node')
);
if (!rustName) {
  console.error(
    'napi-rs baseline not built — run `npm install && npx napi build --release --platform` in bench/napi-rs.'
  );
  process.exit(1);
}

const mojo = require(mojoPath);
const rust = require(join(HERE, rustName));

// name -> [mojoCall, rustCall, description]. Semantics verified identical.
const PAIRS = [
  ['hello()', () => mojo.hello(), () => rust.hello(), 'fixed 16-byte string return'],
  ['greet("world")', () => mojo.greet('world'), () => rust.greet('world'), 'string in, string out'],
  ['add(1, 2)', () => mojo.add(1, 2), () => rust.add(1, 2), 'two f64 in, f64 out'],
  ['addInts(1, 2)', () => mojo.addInts(1, 2), () => rust.addInts(1, 2), 'two i32 in, i32 out'],
  ['isPositive(42)', () => mojo.isPositive(42), () => rust.isPositive(42), 'f64 in, bool out'],
  ['getNull()', () => mojo.getNull(), () => rust.getNull(), 'null return (minimal work)'],
  ['createObject()', () => mojo.createObject(), () => rust.createObject(), 'empty object'],
  ['makeGreeting()', () => mojo.makeGreeting(), () => rust.makeGreeting(), 'object with one string prop'],
  ['getProperty(obj, "x")', () => mojo.getProperty(OBJ, 'x'), () => rust.getProperty(OBJ, 'x'), 'named property read'],
  ['strictEquals(1, 1)', () => mojo.strictEquals(1, 1), () => rust.strictEquals(1, 1), 'two unknowns compared'],
];
const OBJ = { x: 42, y: 'hello' };

// --- semantic equivalence: the comparison is meaningless without it --------
const mismatches = [];
for (const [name, m, r] of PAIRS) {
  const a = JSON.stringify(m() ?? null);
  const b = JSON.stringify(r() ?? null);
  // hello() returns a framework-specific string; equal LENGTH is the fair test.
  const ok = name.startsWith('hello') ? a.length === b.length : a === b;
  if (!ok) mismatches.push(`  ${name}: mojo=${a} rust=${b}`);
}
if (mismatches.length > 0) {
  console.error('Semantics differ — the comparison would be invalid:\n');
  console.error(mismatches.join('\n'));
  process.exit(1);
}
if (VERIFY_ONLY) {
  console.log(`all ${PAIRS.length} function pairs have matching semantics`);
  process.exit(0);
}

// --- interleaved rounds ----------------------------------------------------
const best = new Map(PAIRS.map(([n]) => [n, { mojo: Infinity, rust: Infinity }]));
for (let round = 0; round < ROUNDS; round++) {
  if (!JSON_MODE) process.stderr.write(`round ${round + 1}/${ROUNDS}\r`);
  for (const [name, mojoFn, rustFn] of PAIRS) {
    const slot = best.get(name);
    // A/B within the pair, so the two sides sit adjacent in time.
    slot.mojo = Math.min(slot.mojo, measure(mojoFn).median);
    slot.rust = Math.min(slot.rust, measure(rustFn).median);
  }
}

const results = {};
for (const [name, , , desc] of PAIRS) {
  const { mojo: m, rust: r } = best.get(name);
  results[name] = { mojo: m, rust: r, ratio: Number((m / r).toFixed(2)), desc };
}

if (JSON_MODE) {
  console.log(JSON.stringify({
    platform: `${process.platform}-${process.arch}`,
    node: process.version,
    rounds: ROUNDS, batches: BATCHES, batchSize: BATCH_SIZE,
    napiMojo: require(join(ROOT, 'package.json')).version,
    results,
  }, null, 2));
} else {
  const ratios = Object.values(results).map((r) => r.ratio).sort((a, b) => a - b);
  console.log(`\nnapi-mojo vs napi-rs — per-call overhead, ${process.platform}-${process.arch}, Node ${process.version}`);
  console.log(`best of ${ROUNDS} interleaved rounds, median ns/call\n`);
  console.log(`  ${'call'.padEnd(23)} ${'napi-mojo'.padStart(10)} ${'napi-rs'.padStart(10)}   ratio`);
  console.log(`  ${'-'.repeat(23)} ${'-'.repeat(10)} ${'-'.repeat(10)}   -----`);
  for (const [name, r] of Object.entries(results)) {
    console.log(`  ${name.padEnd(23)} ${String(r.mojo).padStart(10)} ${String(r.rust).padStart(10)}   ${r.ratio.toFixed(2)}x`);
  }
  const mid = ratios[Math.floor(ratios.length / 2)];
  console.log(`\n  median ratio ${mid.toFixed(2)}x  (range ${ratios[0].toFixed(2)}x–${ratios[ratios.length - 1].toFixed(2)}x)`);
  console.log(`  <1.00x means napi-mojo is faster.\n`);
}
