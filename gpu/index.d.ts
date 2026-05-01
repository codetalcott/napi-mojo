/**
 * @napi-mojo/gpu — GPU primitives backed by Mojo + MAX
 *
 * Handle-based design with explicit free. We deliberately avoid N-API
 * GC-managed handles (napi_wrap / napi_create_external / napi_set_instance_data)
 * because the underlying Mojo 1.0.0b1 broken-fn-pointer pattern makes
 * env-teardown finalizers unreliable on Linux. See ../docs/GPU-DESIGN.md.
 *
 * GPU memory is precious — explicit free is arguably better than relying
 * on V8 GC anyway. The `Matrix` class wrapper provides ergonomic
 * `using`-friendly cleanup; the function API is the substrate.
 */

// ─── Opaque handles ───────────────────────────────────────────────────────

/**
 * Opaque handle to a row-major Float32 matrix resident in GPU device memory.
 * Backed by a u64 index into a process-lifetime native registry. Don't do
 * arithmetic on it; pass it to GPU ops as-is.
 */
export type MatrixHandle = bigint & { readonly __brand: 'MatrixHandle' };

// ─── Native ops ───────────────────────────────────────────────────────────

/**
 * Upload a row-major Float32 matrix to GPU device memory.
 *
 * Async because the host-to-device copy can take 10s of ms for large
 * matrices and we don't want to block the JS event loop. The actual H2D
 * copy runs on a libuv worker thread; only the registry insertion happens
 * back on the main thread before the promise resolves.
 *
 * The handle owns the device buffer until you call `freeMatrix(h)`.
 *
 * @throws if `data.length !== rows * cols`
 * @throws if no GPU is available on this host
 */
export function loadMatrixGpu(
  data: Float32Array,
  rows: number,
  cols: number,
): Promise<MatrixHandle>;

/**
 * Free the GPU device buffer backing this handle and remove it from the
 * registry. Synchronous — the underlying device buffer free is fast and
 * synchronous, and a sync API is easier to reason about for cleanup paths
 * (`finally`, signal handlers, test teardown).
 *
 * Calling `freeMatrix` on the same handle twice is a no-op; freeing an
 * unknown handle is a no-op. Both cases return without throwing because
 * cleanup code shouldn't have to defensively check.
 */
export function freeMatrix(h: MatrixHandle): void;

/**
 * Free every live handle. Useful from `process.on('exit')` and from test
 * teardown; not normally needed in application code (just call `freeMatrix`
 * for each handle you allocate).
 */
export function freeAll(): void;

/**
 * Inspect what's still live. Mostly a leak-detection aid for tests:
 * `expect(liveHandles().matrices).toBe(0)` in `afterEach`.
 */
export function liveHandles(): { matrices: number };

// ─── Class wrapper ────────────────────────────────────────────────────────

/**
 * Ergonomic wrapper around `MatrixHandle`. Use it when you want:
 *   - method-style chaining (future: `a.matmul(b)`)
 *   - `using` syntax (Stage-4 explicit-resource-management proposal)
 *   - a FinalizationRegistry safety net for handles you forgot to free
 *
 * **The safety net is not a substitute for calling `.free()`.** GPU memory
 * is small and `FinalizationRegistry` callbacks are not guaranteed to run.
 * Treat it as a development warning, not a lifecycle guarantee.
 */
export class Matrix {
  /** Upload host data to GPU and return a wrapping `Matrix`. */
  static load(data: Float32Array, rows: number, cols: number): Promise<Matrix>;

  /** Underlying registry handle. Use to interop with the function API. */
  readonly handle: MatrixHandle;

  readonly rows: number;
  readonly cols: number;

  /** Free the device buffer. Idempotent. */
  free(): void;

  /** Whether `free()` has been called. */
  readonly disposed: boolean;
}
