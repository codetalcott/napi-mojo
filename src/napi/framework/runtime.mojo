## src/napi/framework/runtime.mojo — Mojo async runtime initialization
##
## When a Mojo shared library is loaded via dlopen (Node.js .node addon),
## the async runtime is NOT initialized automatically (no compiler-generated
## main()). Call init_async_runtime() in register_module before using
## parallelize() or other async primitives.
##
## SIMD parallelism crossover point:
##   Each parallelize() call carries ~200 ns of thread-dispatch overhead.
##   For Float64 operations this breaks even at roughly 64 elements —
##   below that threshold a simple scalar loop is faster.
##   Rule of thumb: use parallelize_safe() for n >= 64 Float64 elements,
##   or n >= 128 Float32/Int32 elements; fall back to scalar for smaller arrays.

from std.runtime import initialize_runtime
from max.algorithm import parallelize


def init_async_runtime() raises:
    """Initialize the Mojo async runtime for shared library addons.

    Must be called before parallelize() or other async primitives.
    Idempotent — safe to call multiple times.

    As of Mojo 1.0.0 this delegates to the official
    `std.runtime.initialize_runtime()`, which exists for exactly this
    situation (shared-lib Mojo called from a non-Mojo host, so no Mojo
    main() ever ran). It replaces the hand-rolled resolution of the
    private `KGEN_CompilerRT_AsyncRT_GetOrCreateCPUDevice` symbol from
    libKGENCompilerRTShared, which silently broke every time the KGEN
    entry point was renamed (see git history and CLAUDE.md for that saga).
    `raises` is kept in the signature for API stability with existing
    callers even though the official API does not raise.
    """
    initialize_runtime()


def parallelize_safe[func: def(Int) capturing -> None](n: Int):
    """Run func(i) for i in 0..n-1 in parallel, with runtime auto-init.

    Equivalent to parallelize[func](n) but safe to call from a .node addon
    without a prior explicit init_async_runtime() call.

    If the async runtime cannot be initialized, this runs the work
    SEQUENTIALLY rather than calling parallelize(). That is not a cosmetic
    choice: parallelize() on an uninitialized runtime dereferences it and
    SIGSEGVs the host Node process. The earlier docstring claimed parallelize()
    fell back on its own — it does not, and examples/vectors-addon.mojo crashed
    at exactly its PARALLEL_THRESHOLD because of it.

    Sequential fallback is semantically identical, just without thread
    dispatch: func(i) is invoked for every i either way.

    Crossover point: ~200 ns thread-dispatch overhead means this is only
    faster than scalar for n >= ~64 Float64 elements. For small arrays
    use a plain for loop instead.
    """
    try:
        init_async_runtime()
    except:
        for i in range(n):
            func(i)
        return
    parallelize[func](n)
