'use strict';
// @napi-mojo/gpu — JS shim that loads the native addon and re-exports its
// surface plus a small JS-side ergonomic wrapper.

const path = require('path');

let native;
try {
  native = require(path.join(__dirname, 'build', 'gpu.node'));
} catch (err) {
  // Fail loudly here — this package's whole reason to exist is the GPU
  // addon. Callers who want optional GPU should `try { require } catch`
  // around the package import itself.
  throw new Error(
    `@napi-mojo/gpu: failed to load build/gpu.node — ` +
      `is the GPU build available for ${process.platform}-${process.arch}? ` +
      `Original error: ${err.message}`,
  );
}

// Native surface. _liveHandlesCount returns a Number; we wrap it into
// the documented `liveHandles(): { matrices: number }` shape on the JS
// side so we can grow that object without ABI churn.
const {
  loadMatrixGpu,
  freeMatrix,
  freeAll,
  _liveHandlesCount,
} = native;

function liveHandles() {
  return { matrices: _liveHandlesCount() };
}

// ─── Class wrapper ──────────────────────────────────────────────────────────
// Holds a handle + dimensions; provides `.free()` and a FinalizationRegistry
// safety net. Not a substitute for explicit free — see index.d.ts.

const finalizationRegistry = new FinalizationRegistry((handle) => {
  // Best-effort: warn so leaks surface in development, then free.
  // FinalizationRegistry callbacks are not guaranteed to fire — this is a
  // backstop, not a lifecycle.
  if (process.env.NAPI_MOJO_GPU_FINALIZER_QUIET !== '1') {
    process.emitWarning(
      `@napi-mojo/gpu: Matrix(handle=${handle}) was GC'd without explicit free()`,
      'NapiMojoGpuLeak',
    );
  }
  freeMatrix(handle);
});

class Matrix {
  /**
   * @param {bigint} handle
   * @param {number} rows
   * @param {number} cols
   */
  constructor(handle, rows, cols) {
    this.handle = handle;
    this.rows = rows;
    this.cols = cols;
    this.disposed = false;
    finalizationRegistry.register(this, handle, this);
  }

  static async load(data, rows, cols) {
    const handle = await loadMatrixGpu(data, rows, cols);
    return new Matrix(handle, rows, cols);
  }

  free() {
    if (this.disposed) return;
    this.disposed = true;
    finalizationRegistry.unregister(this);
    freeMatrix(this.handle);
  }
}

module.exports = {
  loadMatrixGpu,
  freeMatrix,
  freeAll,
  liveHandles,
  Matrix,
};
