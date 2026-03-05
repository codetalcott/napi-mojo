// examples/vectors.js — SIMD vector similarity demo + benchmark
//
// Demonstrates Mojo's SIMD vectorize() vs pure JavaScript on
// dot product, cosine similarity, and Euclidean distance.
//
// Build:  pixi run mojo build --emit shared-lib -I src examples/vectors-addon.mojo -o build/vectors.dylib
//         mv build/vectors.dylib build/vectors.node
// Run:    node examples/vectors.js

const addon = require('../build/vectors.node');

// --- Pure JS baselines -------------------------------------------------------

function jsDotProduct(a, b) {
  let sum = 0;
  for (let i = 0; i < a.length; i++) sum += a[i] * b[i];
  return sum;
}

function jsCosineSimilarity(a, b) {
  let dot = 0, normA = 0, normB = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  const denom = Math.sqrt(normA) * Math.sqrt(normB);
  return denom > 0 ? dot / denom : 0;
}

function jsEuclideanDistance(a, b) {
  let sum = 0;
  for (let i = 0; i < a.length; i++) {
    const d = a[i] - b[i];
    sum += d * d;
  }
  return Math.sqrt(sum);
}

// --- Correctness checks ------------------------------------------------------

console.log('=== Correctness ===\n');

const a = new Float64Array([1, 2, 3]);
const b = new Float64Array([4, 5, 6]);

console.log('dotProduct([1,2,3], [4,5,6]):', addon.dotProduct(a, b), '(expected 32)');
console.log('cosineSimilarity:            ', addon.cosineSimilarity(a, b).toFixed(6), '(expected ~0.974632)');
console.log('euclideanDistance:            ', addon.euclideanDistance(a, b).toFixed(6), '(expected ~5.196152)');

// Identity checks
const x = new Float64Array([0.6, 0.8]);
console.log('\ncosineSimilarity(x, x):      ', addon.cosineSimilarity(x, x), '(expected 1)');
console.log('euclideanDistance(x, x):      ', addon.euclideanDistance(x, x), '(expected 0)');

// --- Benchmark at multiple dimensions ----------------------------------------

function bench(name, fn, iters) {
  // warmup
  for (let i = 0; i < 100; i++) fn();

  const start = performance.now();
  for (let i = 0; i < iters; i++) fn();
  const ms = performance.now() - start;
  const opsPerSec = Math.round(iters / (ms / 1000));
  console.log(`  ${name}: ${ms.toFixed(1)}ms (${opsPerSec.toLocaleString()} ops/sec)`);
  return ms;
}

for (const [DIM, ITERS] of [[768, 100_000], [10_000, 10_000], [100_000, 1_000]]) {
  console.log(`\n=== cosineSimilarity: ${DIM.toLocaleString()}-dimension vectors ===\n`);

  const va = new Float64Array(DIM);
  const vb = new Float64Array(DIM);
  for (let i = 0; i < DIM; i++) {
    va[i] = Math.random();
    vb[i] = Math.random();
  }

  const mojoMs = bench('Mojo SIMD', () => addon.cosineSimilarity(va, vb), ITERS);
  const jsMs = bench('Pure JS  ', () => jsCosineSimilarity(va, vb), ITERS);
  console.log(`  Speedup: ${(jsMs / mojoMs).toFixed(1)}x`);
}
