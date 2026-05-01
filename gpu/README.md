# @napi-mojo/gpu

GPU primitives for napi-mojo, backed by Mojo + MAX. Handle-based,
explicit free, async upload.

> **Status: prototype.** Surface API is `loadMatrixGpu` / `freeMatrix` /
> `freeAll` / `liveHandles` plus a `Matrix` class wrapper. matmul,
> top-k retrieval, and async-on-worker-thread upload are next.

## Why a separate package

napi-mojo's CPU addon links nothing GPU-related, so hosts without a
GPU runtime install just the CPU package. This package builds an
independent `gpu.node` that depends on the MAX GPU runtime and is
loaded by the dependent application only when GPU is actually needed.

## Why handle-based + explicit free

GPU memory is small and precious. Relying on V8's GC to free a
device buffer is a recipe for OOM in long-lived processes — finalizers
run "eventually," not "promptly." More pressingly, the underlying
napi-mojo addon currently can't reliably register N-API finalizers
(Mojo 1.0.0b1 doesn't expose a way to take a `def`'s code address as
a thin C-ABI callback pointer); the fix is upstream. So this package
sidesteps the entire GC-finalizer code path by keeping resources in
a process-lifetime registry and surfacing handles to JS as opaque
`bigint`s. `freeMatrix(h)` is synchronous, idempotent, and the only
correct way to release a handle.

The `Matrix` class wraps a handle and registers it with a
`FinalizationRegistry` as a *safety net* (warns + frees on GC). MDN
explicitly documents that `FinalizationRegistry` callbacks are not
guaranteed to fire — treat the warning as a development aid, not a
lifecycle promise.

## Build

```bash
bash build.sh
```

Auto-detects target accelerator by platform (Metal on macOS arm64,
sm_90 on Linux x86_64). Override with `NAPI_MOJO_GPU_ACCEL`:

```bash
NAPI_MOJO_GPU_ACCEL="--target-accelerator sm_80" bash build.sh   # A100
NAPI_MOJO_GPU_ACCEL="" bash build.sh                              # skip GPU codegen
```

If the accel build fails (no toolchain, wrong driver, etc.), the
addon still loads — the `gpu_available` flag is False inside, and
every op rejects/throws with a clear `"no GPU available"` error.

## Quick example

```ts
import { loadMatrixGpu, freeMatrix } from '@napi-mojo/gpu';

const data = new Float32Array(4);
data.set([1, 2, 3, 4]);
const h = await loadMatrixGpu(data, 2, 2);
try {
  // pass `h` to other GPU ops (matmul, search, ...)
} finally {
  freeMatrix(h);
}
```

Or with the class wrapper (Stage-4 `using` syntax lands cleanly on top):

```ts
import { Matrix } from '@napi-mojo/gpu';

const m = await Matrix.load(data, 2, 2);
try {
  // ... use m.handle ...
} finally {
  m.free();
}
```

## TODO

- Move H2D copy to a libuv worker thread (currently runs synchronously
  on the JS main thread; the Promise resolves immediately).
- `matmulHandle(a, b)` returning a new `MatrixHandle`.
- `buildIndex(m)` + `searchHandle(idx, query, k)` for RAG retrieval.
- Test with explicit `NAPI_MOJO_GPU_ACCEL=""` to confirm graceful
  no-GPU degradation.
- Mutex on the registry once cross-thread access lands.
