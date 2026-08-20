#!/usr/bin/env node
/**
 * bench-harness.mjs — the timing core, shared by every benchmark in this repo.
 *
 * Extracted so that scripts/benchmark.mjs (napi-mojo's own per-call overhead,
 * gated by check-benchmark.mjs) and bench/napi-rs/compare.mjs (napi-mojo vs
 * napi-rs) run *literally the same code*, not the same code copied. A
 * cross-framework comparison is only worth publishing if the methodology is
 * provably identical on both sides, and a copied function drifts.
 *
 * Method: warm up, then time BATCHES batches of BATCH_SIZE calls each and
 * report per-batch ns/call percentiles. Batching amortises the hrtime call;
 * percentiles over batches make an outlier visible instead of averaged away.
 */

export const WARMUP = 1000;
export const BATCH_SIZE = 1000;
export const BATCHES = Number(process.env.NAPI_MOJO_BENCH_BATCHES ?? 1000);

/** Time `fn` and return {mean, median, p95, p99, stddev} in ns/call. */
export function measure(fn) {
  for (let i = 0; i < WARMUP; i++) fn();

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

  return {
    mean: Number(mean.toFixed(1)),
    median: Number(median.toFixed(1)),
    p95: Number(p95.toFixed(1)),
    p99: Number(p99.toFixed(1)),
    stddev: Number(Math.sqrt(variance).toFixed(1)),
  };
}
