// examples/gpu-matmul.js — smoke test for the v0.4.0 GPU primitives
//
// Exercises loadMatrixGpu / matmulHandle / searchHandle / releaseMatrixGpu
// against small hand-checkable shapes and one random [4, 64] × [64, 1000]
// case cross-checked against a JS reference. Meant to run on any host that
// built build/gpu.node (Apple Silicon with Metal, Linux x86_64 with CUDA).
//
// Run: node examples/gpu-matmul.js

const napi = require('..');

if (typeof napi.loadMatrixGpu !== 'function') {
  console.error('GPU addon not loaded — rebuild with a GPU toolchain:');
  console.error('  pixi run bash build.sh');
  process.exit(1);
}

function jsMatmul(a, b, M, K, N) {
  const c = new Float32Array(M * N);
  for (let i = 0; i < M; i++) {
    for (let j = 0; j < N; j++) {
      let s = 0;
      for (let p = 0; p < K; p++) s += a[i * K + p] * b[p * N + j];
      c[i * N + j] = s;
    }
  }
  return c;
}

// --- Case 1: 2x2 identity × 2x2 (hand-checkable) ---------------------------
{
  const a = new Float32Array([1, 0, 0, 1]);
  const b = new Float32Array([3, 7, 5, 11]);
  const dst = new Float32Array(4);
  const hA = napi.loadMatrixGpu(a, 2, 2);
  const hB = napi.loadMatrixGpu(b, 2, 2);
  napi.matmulHandle(hA, hB, dst);
  napi.releaseMatrixGpu(hA);
  napi.releaseMatrixGpu(hB);
  console.log('identity matmul:', Array.from(dst), '(expected [3, 7, 5, 11])');
}

// --- Case 2: [4, 64] × [64, 1000] cross-checked against JS ----------------
{
  const M = 4, K = 64, N = 1000;
  const a = new Float32Array(M * K);
  const b = new Float32Array(K * N);
  for (let i = 0; i < a.length; i++) a[i] = Math.random() * 2 - 1;
  for (let i = 0; i < b.length; i++) b[i] = Math.random() * 2 - 1;

  const dst = new Float32Array(M * N);
  const hA = napi.loadMatrixGpu(a, M, K);
  const hB = napi.loadMatrixGpu(b, K, N);
  const t0 = performance.now();
  napi.matmulHandle(hA, hB, dst);
  const ms = performance.now() - t0;
  napi.releaseMatrixGpu(hA);
  napi.releaseMatrixGpu(hB);

  const expected = jsMatmul(a, b, M, K, N);
  let maxErr = 0;
  for (let i = 0; i < dst.length; i++) {
    maxErr = Math.max(maxErr, Math.abs(dst[i] - expected[i]));
  }
  console.log(`[4, 64] × [64, 1000]: ${ms.toFixed(2)}ms, maxErr=${maxErr.toExponential(2)}`);
}

// --- Case 3: searchHandle top-10 over [1, 32] × [32, 500] ------------------
{
  const d = 32, N = 500, k = 10;
  const q = new Float32Array(d);
  const corpus = new Float32Array(d * N);
  for (let i = 0; i < q.length; i++) q[i] = Math.random() * 2 - 1;
  for (let i = 0; i < corpus.length; i++) corpus[i] = Math.random() * 2 - 1;

  const idx = new Uint32Array(k);
  const scores = new Float32Array(k);
  const hA = napi.loadMatrixGpu(q, 1, d);
  const hB = napi.loadMatrixGpu(corpus, d, N);
  const t0 = performance.now();
  napi.searchHandle(hA, hB, idx, scores);
  const ms = performance.now() - t0;
  napi.releaseMatrixGpu(hA);
  napi.releaseMatrixGpu(hB);

  console.log(`searchHandle top-${k}: ${ms.toFixed(2)}ms`);
  console.log('  top indices:', Array.from(idx));
  console.log('  top scores: ', Array.from(scores).map((s) => s.toFixed(3)));
}
