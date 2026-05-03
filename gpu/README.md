# @napi-mojo/gpu

GPU primitives for Node.js, backed by Mojo + MAX. **Metal-first** —
designed to deliver useful GPU acceleration on Apple Silicon developer
machines without a CUDA toolchain anywhere in the dependency graph.

> **Status: scaffold.** Today: process-lifetime handle registry,
> async `loadMatrixGpu`, sync `freeMatrix`, leak-detection helper,
> ergonomic `Matrix` class wrapper. Coming: `matmulHandle`,
> `searchHandle` (RAG retrieval), worker-thread H2D upload. The
> production RAG path lives in [`@qkstat/rag`](../packages/rag) today
> and will migrate here.

## When to reach for this

GPU acceleration is a worthwhile dependency for a fairly narrow set of
shapes on Apple Silicon. Be honest with yourself about which side of
each line you're on:

| Workload | Verdict on M-series Metal |
| --- | --- |
| **Single-query exact RAG**, ≥50k corpus, d≥384 | ✅ **GPU wins** — sub-5 ms latencies, recall 1.0 |
| Single-query against ≤10k corpus | ❌ Use CPU (ORT/Accelerate or HNSW) |
| Batched matmul (B≥64) on M-series | ❌ Use CPU — Metal stays flat at ~67 GFLOP/s for FP32 (no tensor cores) |
| FP32-strict precision | ❌ CPU; tensor-core paths trade precision for throughput on H100/sm_80+ |

The "avoid CUDA" framing pushes you exactly into the first row, which
is the row this package targets. If your workload sits in any of the
other rows, you don't need a GPU — keep it simple.

## Measured (M-series, Mojo 1.0.0b1, today)

```text
Build synthetic corpus, 10k docs × 768 dim, upload to GPU:
  Generation        : 51 ms
  loadMatrixGpu     : 19 ms (one-time)
  GpuIndex.search   : 4.99 ms / query (avg over 50 iters, k=10)
                      score=1.0000 on self-similarity check (recall=1.0)

Larger corpus benchmark, [1, 768] × [768, 100k]:
  JS baseline       : 87.8 ms
  Mojo GPU cached   : 3.51 ms  (25× JS, exact, recall=1.0)
  vs HNSW ef=2000   : 15.66 ms (recall=0.60 on random unit vectors)
```

(Full table including batched shapes in
[`mojo-addon-examples/examples/matmul/README.md`](https://github.com/codetalcott/mojo-addon-examples/blob/main/examples/matmul/README.md)
— same hardware class, same workload, includes ORT CPU baselines.)

## Quick example

```ts
import { loadMatrixGpu, freeMatrix } from '@napi-mojo/gpu';

const data = new Float32Array(rows * cols);
// ... fill data ...
const h = await loadMatrixGpu(data, rows, cols);
try {
  // Pass `h` to other GPU ops (matmul, search) once they land here.
  // Today, use @qkstat/rag for the full pipeline.
} finally {
  freeMatrix(h);
}
```

Or use the class wrapper (`using` lands cleanly on top once the
explicit-resource-management proposal ships in your engine):

```ts
import { Matrix } from '@napi-mojo/gpu';

const m = await Matrix.load(data, rows, cols);
try {
  // ... use m.handle ...
} finally {
  m.free();
}
```

## Build

```bash
bash build.sh
```

Auto-detects target accelerator by platform (`metal:4` on macOS arm64,
`sm_90` on Linux x86_64). Override:

```bash
NAPI_MOJO_GPU_ACCEL="--target-accelerator sm_80" bash build.sh   # A100
NAPI_MOJO_GPU_ACCEL="" bash build.sh                              # skip GPU codegen
```

If the accel build fails (no toolchain, wrong driver, etc.) the addon
still loads — every op throws/rejects with a clear `"no GPU available"`
error. This means you can ship a single binary across hosts and let
the runtime degrade.

## Why handle-based + explicit free

Two reasons. The first is product-shaped: **GPU memory is small and
precious.** Relying on V8's GC to free a device buffer is a recipe for
OOM in long-lived processes — `FinalizationRegistry` callbacks run
"eventually," not "promptly," and MDN explicitly disclaims any
liveness guarantee.

The second is dependency-shaped: **napi-mojo can't currently register
reliable N-API finalizers on Linux.** Mojo 1.0.0b1 doesn't expose a
way to take a `def`'s code address as a thin C-ABI callback pointer
(the address-of-local-var pattern extracts a sentinel, not a function
address). So this package sidesteps the entire `napi_wrap` /
`napi_create_external` / `napi_set_instance_data` GC-finalizer code
path: every GPU resource lives in a process-lifetime registry keyed by
a monotonically-increasing UInt64; the JS handle is that id wrapped
as a `bigint`. `freeMatrix(h)` removes the entry and releases the
device buffer synchronously. No GC finalizers anywhere on the call
path, no platform-specific symbol-visibility quirks, no Linux flake.

The `Matrix` class wraps a handle and registers it with a
`FinalizationRegistry` as a *safety net* (warns + frees on GC). Treat
the warning as a development aid, not a lifecycle guarantee — call
`.free()`.

## Relationship to `@qkstat/rag`

`@qkstat/rag` is the **applied** layer today: end-to-end exact-retrieval
RAG with `loadMatrixGpu` / `matmulHandle` / `searchHandle` /
`releaseMatrixGpu` plus a `GpuIndex` class. It uses napi-mojo's
typed-external helpers, which means it inherits the
finalizer-pointer flake on the registration paths.

`@napi-mojo/gpu` is the **primitives** layer being scaffolded here
with the explicit-registry design. The plan is to grow it to feature
parity with `@qkstat/rag`'s GPU surface, then have `@qkstat/rag`
re-export from here. Until that lands, **for production single-query
RAG on Apple Silicon today, use `@qkstat/rag`.**

## Roadmap

- `matmulHandle(a, b): Promise<MatrixHandle>` — same registry, new op.
- `buildIndex(m)` + `searchHandle(idx, query, k)` — fused matmul + top-k.
- Move H2D copy to a libuv worker thread (the JS API is stable; this
  is purely a latency improvement under sustained load).
- Mutex on the registry once worker-thread reads land.
- Verified `NAPI_MOJO_GPU_ACCEL=""` no-GPU degradation path.
- Linux/CUDA self-hosted runner for CI parity beyond Metal.
