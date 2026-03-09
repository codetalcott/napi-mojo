#!/usr/bin/env node
/**
 * benchmark.mjs — Measure per-call overhead of Mojo N-API callbacks
 *
 * Tests the hot path: JS → Mojo callback → N-API calls → JS return.
 * Each callback uses cached NapiBindings (1 dlsym to bootstrap,
 * then all subsequent N-API calls use cached function pointers).
 *
 * Usage: node scripts/benchmark.mjs
 */

import { createRequire } from 'module';
const require = createRequire(import.meta.url);
const addon = require('../build/index.node');

const WARMUP = 1000;
const ITERATIONS = 1_000_000;

function bench(name, fn) {
  // Warmup
  for (let i = 0; i < WARMUP; i++) fn();

  const start = process.hrtime.bigint();
  for (let i = 0; i < ITERATIONS; i++) fn();
  const elapsed = Number(process.hrtime.bigint() - start);

  const totalMs = elapsed / 1e6;
  const perCallNs = elapsed / ITERATIONS;
  console.log(`${name.padEnd(30)} ${perCallNs.toFixed(0).padStart(6)} ns/call  (${totalMs.toFixed(1)} ms total)`);
}

console.log(`Benchmark: ${ITERATIONS.toLocaleString()} iterations each\n`);

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
