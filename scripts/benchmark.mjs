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
 * Usage:
 *   node scripts/benchmark.mjs           # human-readable table
 *   node scripts/benchmark.mjs --json    # machine-readable, for the CI gate
 *
 * Iteration counts are overridable via $NAPI_MOJO_BENCH_BATCHES so CI can trade
 * precision for wall-clock without editing this file.
 */

import { createRequire } from 'module';
import { measure, WARMUP, BATCH_SIZE, BATCHES } from './bench-harness.mjs';
const require = createRequire(import.meta.url);
const addon = require('../build/index.node');

const JSON_MODE = process.argv.includes('--json');
const TOTAL = BATCH_SIZE * BATCHES;

// name -> stats, in declaration order. The gate reads this; the table prints it.
const results = {};

function bench(name, fn) {
  // Timing lives in bench-harness.mjs so the napi-rs comparison can use the
  // identical code path rather than a copy of it.
  const { mean, median, p95, p99, stddev } = measure(fn);
  results[name] = { mean, median, p95, p99, stddev };

  if (JSON_MODE) return;
  const stats = [
    `mean=${mean.toFixed(0)}`,
    `median=${median.toFixed(0)}`,
    `p95=${p95.toFixed(0)}`,
    `p99=${p99.toFixed(0)}`,
    `stddev=${stddev.toFixed(0)}`,
  ].join('  ');
  console.log(`${name.padEnd(30)} ${stats} ns/call`);
}

// Headings are part of the table, not the data.
function section(title) {
  if (!JSON_MODE) console.log(title);
}

section(`Node.js ${process.version} (${process.platform} ${process.arch})`);
section(`Benchmark: ${TOTAL.toLocaleString()} iterations (${BATCHES} batches of ${BATCH_SIZE})\n`);

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

section('\n--- Class operations ---\n');

const counter = new addon.Counter(0);
bench('counter.increment()', () => counter.increment());
bench('counter.value (getter)', () => counter.value);

section('\n--- Property access ---\n');

const obj = { x: 42, y: 'hello' };
bench('getProperty(obj, "x")', () => addon.getProperty(obj, 'x'));
bench('strictEquals(1, 1)', () => addon.strictEquals(1, 1));

section('\n--- Mojo -> JS (host direction) ---\n');

// These measure the OTHER direction: Mojo calling back into JavaScript. Each
// figure is a full JS -> Mojo -> JS -> Mojo -> JS round trip, so the marginal
// Mojo -> JS cost is the difference against a forward-only call of similar
// shape (compare `callN(fn, [])` against `hello()`).
//
// The callees are deliberately trivial: this is overhead, not callee work.
const noop = () => 0;
const adder = (a, b, c) => a + b + c;
const methodObj = { base: 1, m(x) { return this.base + x; } };

bench('callN(fn, [])', () => addon.callN(noop, []));
bench('callN(fn, [1,2,3])', () => addon.callN(adder, [1, 2, 3]));
bench('callMethod(obj, "m", [1])', () => addon.callMethod(methodObj, 'm', [1]));
bench('scopedCall(1, fn)', () => addon.scopedCall(1, noop));

if (JSON_MODE) {
  console.log(
    JSON.stringify(
      {
        platform: `${process.platform}-${process.arch}`,
        node: process.version,
        batches: BATCHES,
        batchSize: BATCH_SIZE,
        results,
      },
      null,
      2
    )
  );
} else {
  console.log();
}
