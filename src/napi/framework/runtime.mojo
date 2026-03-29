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

from std.ffi import OwnedDLHandle
from std.algorithm import parallelize


def init_async_runtime() raises:
    """Initialize the Mojo async runtime for shared library addons.

    Must be called before parallelize() or other async primitives.
    Safe to call multiple times — the runtime handles re-init internally.
    """
    # On Linux, Node.js loads .node addons with dlopen(RTLD_LOCAL), so
    # dlsym(RTLD_DEFAULT, ...) via OwnedDLHandle() can't find symbols from
    # the addon's linked libraries. Explicitly open libKGENCompilerRTShared
    # by name — the linker finds it via the RUNPATH/rpath that `mojo build`
    # embeds in the shared library. Try .dylib first (macOS), fall back to
    # .so (Linux).
    var lib: OwnedDLHandle
    try:
        lib = OwnedDLHandle("libKGENCompilerRTShared.dylib")
    except:
        lib = OwnedDLHandle("libKGENCompilerRTShared.so")
    var create_rt = lib.get_function[
        def () -> OpaquePointer[MutAnyOrigin]
    ]("KGEN_CompilerRT_AsyncRT_GetOrCreateRuntime")
    _ = create_rt()


def parallelize_safe[func: def (Int) capturing -> None](n: Int):
    """Run func(i) for i in 0..n-1 in parallel, with runtime auto-init.

    Equivalent to parallelize[func](n) but safe to call from a .node addon
    without a prior explicit init_async_runtime() call. The runtime init is
    attempted silently; if it fails the loop still runs (sequentially via
    parallelize fallback behavior).

    Crossover point: ~200 ns thread-dispatch overhead means this is only
    faster than scalar for n >= ~64 Float64 elements. For small arrays
    use a plain for loop instead.
    """
    try:
        init_async_runtime()
    except:
        pass
    parallelize[func](n)
