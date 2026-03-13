#!/usr/bin/env node
/**
 * benchmark.mjs — Measure per-call overhead of Mojo N-API callbacks
 *
 * Tests the hot path: JS → Mojo callback → N-API calls → JS return.
 * Each callback uses cached NapiBindings (1 dlsym to bootstrap,
 * then all subsequent N-API calls use cached function pointers).
 *
 * Reports mean, median, P95, P99, and stddev per call (ns).
 *
 * Usage: node scripts/benchmark.mjs
 */

import { createRequire } from 'module';
const require = createRequire(import.meta.url);
const addon = require('../build/index.node');

const WARMUP = 1000;
const BATCH_SIZE = 1000;
const BATCHES = 1000;
const TOTAL = BATCH_SIZE * BATCHES;

function bench(name, fn) {
  // Warmup
  for (let i = 0; i < WARMUP; i++) fn();

  // Collect per-batch timings (ns/call for each batch)
  const timings = new Float64Array(BATCHES);
  for (let b = 0; b < BATCHES; b++) {
    const start = process.hrtime.bigint();
    for (let i = 0; i < BATCH_SIZE; i++) fn();
    timings[b] = Number(process.hrtime.bigint() - start) / BATCH_SIZE;
  }

  timings.sort();
  const mean = timings.reduce((a, b) => a + b) / BATCHES;
  const median = timings[Math.floor(BATCHES / 2)];
  const p95 = timings[Math.floor(BATCHES * 0.95)];
  const p99 = timings[Math.floor(BATCHES * 0.99)];
  const variance = timings.reduce((s, t) => s + (t - mean) ** 2, 0) / BATCHES;
  const stddev = Math.sqrt(variance);

  const stats = [
    `mean=${mean.toFixed(0)}`,
    `median=${median.toFixed(0)}`,
    `p95=${p95.toFixed(0)}`,
    `p99=${p99.toFixed(0)}`,
    `stddev=${stddev.toFixed(0)}`,
  ].join('  ');
  console.log(`${name.padEnd(30)} ${stats} ns/call`);
}

console.log(`Node.js ${process.version} (${process.platform} ${process.arch})`);
console.log(`Benchmark: ${TOTAL.toLocaleString()} iterations (${BATCHES} batches of ${BATCH_SIZE})\n`);

// Simple return (no args, no N-API reads)
bench('hello()', () => addon.hello());

// String arg + string return
bench('greet("world")', () => addon.greet('world'));

// Two number args + number return
bench('add(1, 2)', () => addon.add(1, 2));

// Boolean return
bench('isPositive(42)', () => addon.isPositive(42));

// Null return (minimal work)
bench('getNull()', () => addon.getNull());

// Object creation
bench('createObject()', () => addon.createObject());

// Object with property
bench('makeGreeting()', () => addon.makeGreeting());

// Int32 addition (type-checked)
bench('addInts(1, 2)', () => addon.addInts(1, 2));

// Generated callback (same bindings path)
bench('exampleAdd(1, 2)', () => addon.exampleAdd(1, 2));

// Generated string callback
bench('exampleGreet("x")', () => addon.exampleGreet('x'));

console.log('\n--- Class operations ---\n');

const counter = new addon.Counter(0);
bench('counter.increment()', () => counter.increment());
bench('counter.value (getter)', () => counter.value);

console.log('\n--- Property access ---\n');

const obj = { x: 42, y: 'hello' };
bench('getProperty(obj, "x")', () => addon.getProperty(obj, 'x'));
bench('strictEquals(1, 1)', () => addon.strictEquals(1, 1));

console.log();
