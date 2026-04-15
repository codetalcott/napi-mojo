// GPU matmul + top-k retrieval primitives (v0.4.0+).
//
// Gated on the presence of build/gpu.node — hosts without a GPU toolchain
// won't have it, and the whole suite skips cleanly so CI on CPU-only
// runners stays green.

const path = require('path');

let gpu;
try {
  gpu = require(path.join(__dirname, '..', 'build', 'gpu.node'));
} catch {
  gpu = null;
}

const describeIfGpu = gpu ? describe : describe.skip;

// Reference implementations used across tests.
function jsMatmul(a, b, M, K, N) {
  const c = new Float32Array(M * N);
  for (let i = 0; i < M; i++) {
    for (let j = 0; j < N; j++) {
      let sum = 0;
      for (let p = 0; p < K; p++) sum += a[i * K + p] * b[p * N + j];
      c[i * N + j] = sum;
    }
  }
  return c;
}

function jsTopK(scores, n, k) {
  const idx = Array.from({ length: n }, (_, i) => i);
  idx.sort((a, b) => scores[b] - scores[a]);
  return {
    idx: idx.slice(0, k),
    scores: idx.slice(0, k).map((i) => scores[i]),
  };
}

describeIfGpu('GPU matmul — handle lifecycle', () => {
  test('loadMatrixGpu returns an external handle', () => {
    const a = new Float32Array(16);
    const h = gpu.loadMatrixGpu(a, 4, 4);
    expect(typeof h).toBe('object');
    gpu.releaseMatrixGpu(h);
  });

  test('matmulHandle on a released handle throws', () => {
    const a = new Float32Array([1, 0, 0, 1]);
    const b = new Float32Array([1, 2, 3, 4]);
    const dst = new Float32Array(4);
    const hA = gpu.loadMatrixGpu(a, 2, 2);
    const hB = gpu.loadMatrixGpu(b, 2, 2);
    gpu.releaseMatrixGpu(hA);
    expect(() => gpu.matmulHandle(hA, hB, dst)).toThrow();
    gpu.releaseMatrixGpu(hB);
  });

  test('dst buffer too small throws', () => {
    const a = new Float32Array(4);
    const b = new Float32Array(4);
    const dst = new Float32Array(1);  // needs 4
    const hA = gpu.loadMatrixGpu(a, 2, 2);
    const hB = gpu.loadMatrixGpu(b, 2, 2);
    expect(() => gpu.matmulHandle(hA, hB, dst)).toThrow();
    gpu.releaseMatrixGpu(hA);
    gpu.releaseMatrixGpu(hB);
  });

  test('dimension mismatch throws', () => {
    const a = new Float32Array(6);  // 2x3
    const b = new Float32Array(8);  // 4x2 — A.cols=3 != B.rows=4
    const dst = new Float32Array(4);
    const hA = gpu.loadMatrixGpu(a, 2, 3);
    const hB = gpu.loadMatrixGpu(b, 4, 2);
    expect(() => gpu.matmulHandle(hA, hB, dst)).toThrow();
    gpu.releaseMatrixGpu(hA);
    gpu.releaseMatrixGpu(hB);
  });
});

describeIfGpu('GPU matmul — correctness', () => {
  test('2x2 identity × 2x2 == 2x2 (small hand-checkable case)', () => {
    const a = new Float32Array([1, 0, 0, 1]);
    const b = new Float32Array([3, 7, 5, 11]);
    const dst = new Float32Array(4);
    const hA = gpu.loadMatrixGpu(a, 2, 2);
    const hB = gpu.loadMatrixGpu(b, 2, 2);
    gpu.matmulHandle(hA, hB, dst);
    expect(Array.from(dst)).toEqual([3, 7, 5, 11]);
    gpu.releaseMatrixGpu(hA);
    gpu.releaseMatrixGpu(hB);
  });

  test('[4, 64] x [64, 1000] matches JS reference within rtol=1e-4', () => {
    const M = 4, K = 64, N = 1000;
    const a = new Float32Array(M * K);
    const b = new Float32Array(K * N);
    for (let i = 0; i < a.length; i++) a[i] = Math.random() * 2 - 1;
    for (let i = 0; i < b.length; i++) b[i] = Math.random() * 2 - 1;

    const expected = jsMatmul(a, b, M, K, N);
    const dst = new Float32Array(M * N);
    const hA = gpu.loadMatrixGpu(a, M, K);
    const hB = gpu.loadMatrixGpu(b, K, N);
    gpu.matmulHandle(hA, hB, dst);
    gpu.releaseMatrixGpu(hA);
    gpu.releaseMatrixGpu(hB);

    let mismatches = 0;
    for (let i = 0; i < dst.length; i++) {
      const tol = Math.max(1e-4 * Math.max(Math.abs(dst[i]), Math.abs(expected[i])), 1e-3);
      if (Math.abs(dst[i] - expected[i]) > tol) mismatches++;
    }
    expect(mismatches).toBe(0);
  });
});

describeIfGpu('GPU search — top-k correctness', () => {
  test('searchHandle top-10 matches brute-force sort on [1, 32] × [32, 500]', () => {
    const d = 32, N = 500, k = 10;
    const q = new Float32Array(d);
    const corpus = new Float32Array(d * N);
    for (let i = 0; i < q.length; i++) q[i] = Math.random() * 2 - 1;
    for (let i = 0; i < corpus.length; i++) corpus[i] = Math.random() * 2 - 1;

    // Compute exact top-k on the host for ground truth.
    const scores = jsMatmul(q, corpus, 1, d, N);
    const expected = jsTopK(scores, N, k);

    const idx = new Uint32Array(k);
    const sc = new Float32Array(k);
    const hA = gpu.loadMatrixGpu(q, 1, d);
    const hB = gpu.loadMatrixGpu(corpus, d, N);
    gpu.searchHandle(hA, hB, idx, sc);
    gpu.releaseMatrixGpu(hA);
    gpu.releaseMatrixGpu(hB);

    // Scores descending.
    for (let i = 1; i < k; i++) expect(sc[i]).toBeLessThanOrEqual(sc[i - 1]);
    // Indices match ground truth.
    expect(Array.from(idx)).toEqual(expected.idx);
    // Scores within float tolerance of brute-force dot products.
    for (let i = 0; i < k; i++) {
      expect(Math.abs(sc[i] - expected.scores[i])).toBeLessThan(1e-3);
    }
  });

  test('searchHandle with batch B=4 returns per-row top-k', () => {
    const B = 4, d = 16, N = 200, k = 5;
    const queries = new Float32Array(B * d);
    const corpus = new Float32Array(d * N);
    for (let i = 0; i < queries.length; i++) queries[i] = Math.random() * 2 - 1;
    for (let i = 0; i < corpus.length; i++) corpus[i] = Math.random() * 2 - 1;

    const idx = new Uint32Array(B * k);
    const sc = new Float32Array(B * k);
    const hA = gpu.loadMatrixGpu(queries, B, d);
    const hB = gpu.loadMatrixGpu(corpus, d, N);
    gpu.searchHandle(hA, hB, idx, sc);
    gpu.releaseMatrixGpu(hA);
    gpu.releaseMatrixGpu(hB);

    // Cross-check each row.
    for (let r = 0; r < B; r++) {
      const rowQ = queries.subarray(r * d, (r + 1) * d);
      const rowScores = jsMatmul(rowQ, corpus, 1, d, N);
      const exp = jsTopK(rowScores, N, k);
      expect(Array.from(idx.subarray(r * k, (r + 1) * k))).toEqual(exp.idx);
    }
  });
});
