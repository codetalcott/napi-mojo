## src/napi/framework/runtime.mojo — Mojo async runtime initialization
##
## When a Mojo shared library is loaded via dlopen (Node.js .node addon),
## the async runtime is NOT initialized automatically (no compiler-generated
## main()). Call init_async_runtime() in register_module before using
## parallelize() or other async primitives.

from ffi import OwnedDLHandle


fn init_async_runtime() raises:
    """Initialize the Mojo async runtime for shared library addons.

    Must be called before parallelize() or other async primitives.
    Safe to call multiple times — the runtime handles re-init internally.
    """
    var lib = OwnedDLHandle()
    var create_rt = lib.get_function[
        fn () -> OpaquePointer[MutAnyOrigin]
    ]("KGEN_CompilerRT_AsyncRT_CreateRuntime")
    _ = create_rt()
