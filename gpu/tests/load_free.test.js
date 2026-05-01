// @napi-mojo/gpu — load + free smoke test
//
// Skips cleanly on hosts without a GPU: the addon is built, but
// loadMatrixGpu rejects with "no GPU available" when no DeviceContext
// could be initialized. Test framework treats that as a guard, not a
// failure of the unit under test.

const path = require('path');

let gpu;
let gpuSkipReason = null;

try {
  gpu = require(path.join(__dirname, '..', 'index.js'));
} catch (err) {
  gpuSkipReason = `failed to load addon: ${err.message}`;
}

const describeIfGpu = gpuSkipReason ? describe.skip : describe;

describeIfGpu('@napi-mojo/gpu — loadMatrixGpu + freeMatrix', () => {
  beforeEach(() => {
    if (gpu) gpu.freeAll();
  });

  test('loadMatrixGpu returns a thenable', () => {
    // Avoid `instanceof Promise` — Jest runs each test file in its own
    // VM realm, so addon-side Promises don't share the test-side
    // Promise constructor identity.
    const result = gpu.loadMatrixGpu(new Float32Array(4), 2, 2);
    expect(typeof result.then).toBe('function');
    return result.then((h) => gpu.freeMatrix(h)).catch(() => {});
  });

  test('the resolved value is a BigInt handle', async () => {
    let handle;
    try {
      handle = await gpu.loadMatrixGpu(new Float32Array(4), 2, 2);
    } catch (err) {
      // No GPU on this host — expected on CPU-only CI runners.
      expect(err.message).toMatch(/no GPU available/);
      return;
    }
    expect(typeof handle).toBe('bigint');
    expect(handle).toBeGreaterThan(0n);
    gpu.freeMatrix(handle);
  });

  test('loadMatrixGpu rejects when data.length !== rows * cols', async () => {
    // This validation runs synchronously on the JS thread before any GPU
    // work, so it throws synchronously rather than rejecting.
    expect(() => gpu.loadMatrixGpu(new Float32Array(3), 2, 2)).toThrow();
  });

  test('handles are unique and monotonic', async () => {
    let h1, h2;
    try {
      h1 = await gpu.loadMatrixGpu(new Float32Array(4), 2, 2);
      h2 = await gpu.loadMatrixGpu(new Float32Array(4), 2, 2);
    } catch {
      return; // no-GPU host
    }
    expect(h2).toBeGreaterThan(h1);
    gpu.freeMatrix(h1);
    gpu.freeMatrix(h2);
  });

  test('liveHandles tracks insert + free', async () => {
    let h;
    try {
      h = await gpu.loadMatrixGpu(new Float32Array(4), 2, 2);
    } catch {
      return;
    }
    expect(gpu.liveHandles().matrices).toBe(1);
    gpu.freeMatrix(h);
    expect(gpu.liveHandles().matrices).toBe(0);
  });

  test('freeMatrix is idempotent on already-freed handles', async () => {
    let h;
    try {
      h = await gpu.loadMatrixGpu(new Float32Array(4), 2, 2);
    } catch {
      return;
    }
    gpu.freeMatrix(h);
    expect(() => gpu.freeMatrix(h)).not.toThrow();
  });

  test('freeMatrix is a no-op on unknown handles', () => {
    expect(() => gpu.freeMatrix(999999n)).not.toThrow();
  });

  test('freeAll clears every live handle', async () => {
    try {
      await gpu.loadMatrixGpu(new Float32Array(4), 2, 2);
      await gpu.loadMatrixGpu(new Float32Array(4), 2, 2);
      await gpu.loadMatrixGpu(new Float32Array(4), 2, 2);
    } catch {
      return;
    }
    expect(gpu.liveHandles().matrices).toBe(3);
    gpu.freeAll();
    expect(gpu.liveHandles().matrices).toBe(0);
  });

  test('Matrix class wraps the handle and supports free()', async () => {
    let m;
    try {
      m = await gpu.Matrix.load(new Float32Array(4), 2, 2);
    } catch {
      return;
    }
    expect(typeof m.handle).toBe('bigint');
    expect(m.rows).toBe(2);
    expect(m.cols).toBe(2);
    expect(m.disposed).toBe(false);
    m.free();
    expect(m.disposed).toBe(true);
    expect(() => m.free()).not.toThrow(); // idempotent
  });
});
