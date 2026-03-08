// Benchmark: measure dlsym overhead per N-API call
// Run with: node benchmarks/dlsym_overhead.js
//
// Each raw_* function in raw.mojo calls OwnedDLHandle() + dlsym per invocation.
// This benchmark measures whether that overhead is significant.

const addon = require('../build/index.node');

const N = 1_000_000;

// Warm up
for (let i = 0; i < 1000; i++) addon.add(1, 2);

// Benchmark: simple two-arg function (2 dlsym calls: get_cb_info + create_double + ...)
const start = performance.now();
for (let i = 0; i < N; i++) {
  addon.add(1, 2);
}
const elapsed = performance.now() - start;

console.log(`add(1, 2): ${N.toLocaleString()} calls in ${elapsed.toFixed(1)}ms = ${(N / elapsed * 1000).toFixed(0)} calls/sec`);

// Benchmark: zero-arg function (fewer dlsym calls)
const start2 = performance.now();
for (let i = 0; i < N; i++) {
  addon.hello();
}
const elapsed2 = performance.now() - start2;

console.log(`hello():   ${N.toLocaleString()} calls in ${elapsed2.toFixed(1)}ms = ${(N / elapsed2 * 1000).toFixed(0)} calls/sec`);
