#!/usr/bin/env node
/**
 * benchmark-compare.mjs — A/B comparison: cached NapiBindings vs OwnedDLHandle per-call
 *
 * Compares callbacks that use cached bindings (the hot path) against
 * inner callbacks that still use the old OwnedDLHandle+dlsym path.
 *
 * A/B pairs:
 *   hello()           vs createCallback()()    — return a string (~1 N-API call)
 *   add(1, 2)         vs createAdder(5)(3)     — read args + return number (~4-6 N-API calls)
 *   addInts(1, 2)     vs createAdder(5)(3)     — int32 read + return (~4-6 N-API calls)
 *
 * Usage: node scripts/benchmark-compare.mjs
 */

import { createRequire } from 'module';
const require = createRequire(import.meta.url);
const addon = require('../build/index.node');

const WARMUP = 5000;
const ITERATIONS = 2_000_000;

function bench(name, fn) {
  for (let i = 0; i < WARMUP; i++) fn();

  const start = process.hrtime.bigint();
  for (let i = 0; i < ITERATIONS; i++) fn();
  const elapsed = Number(process.hrtime.bigint() - start);

  const perCallNs = elapsed / ITERATIONS;
  return { name, perCallNs };
}

function compare(label, newResult, oldResult) {
  const diff = oldResult.perCallNs - newResult.perCallNs;
  const pct = ((diff / oldResult.perCallNs) * 100).toFixed(1);
  const faster = diff > 0 ? 'faster' : 'slower';
  console.log(`  ${label}`);
  console.log(`    Cached bindings:  ${newResult.perCallNs.toFixed(0).padStart(5)} ns/call`);
  console.log(`    OwnedDLHandle:    ${oldResult.perCallNs.toFixed(0).padStart(5)} ns/call`);
  console.log(`    Delta:            ${Math.abs(diff).toFixed(0).padStart(5)} ns (${Math.abs(pct)}% ${faster})`);
  console.log();
}

console.log(`NapiBindings A/B comparison: ${ITERATIONS.toLocaleString()} iterations each\n`);

// --- Test 1: Return string (~1 N-API call in body) ---
const innerFn = addon.createCallback(); // old-path callback

const helloNew = bench('hello() [cached]', () => addon.hello());
const helloOld = bench('createCallback()() [dlsym]', () => innerFn());
compare('String return (~1 N-API call)', helloNew, helloOld);

// --- Test 2: Add numbers (~4-6 N-API calls) ---
const adder5 = addon.createAdder(5); // old-path callback

const addNew = bench('add(1, 2) [cached]', () => addon.add(1, 2));
const addOld = bench('createAdder(5)(3) [dlsym]', () => adder5(3));
compare('Number addition (~4-6 N-API calls)', addNew, addOld);

// --- Test 3: Int32 add vs adder (~4-6 N-API calls) ---
const addIntsNew = bench('addInts(1, 2) [cached]', () => addon.addInts(1, 2));
compare('Int32 addition (~4-6 N-API calls)', addIntsNew, addOld);

// --- Test 4: No-op baseline (getNull = minimal work) ---
const getNullNew = bench('getNull() [cached]', () => addon.getNull());
console.log(`  Baseline (getNull, ~1 N-API call): ${getNullNew.perCallNs.toFixed(0)} ns/call\n`);

// --- Summary ---
console.log('Note: "OwnedDLHandle" path does dlopen(NULL)+dlsym per N-API call.');
console.log('      "Cached bindings" does 1 dlsym bootstrap, then cached pointers.');
console.log('      On macOS, dlopen(NULL) may be near-zero cost (cached by dyld).');
