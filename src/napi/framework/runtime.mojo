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
from napi.raw import _sym


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
    # dev2026072306 renamed this entry point: the old
    # `KGEN_CompilerRT_AsyncRT_GetOrCreateRuntime` is gone, replaced by
    # `..._GetOrCreateCPUDevice`. Do NOT be misled by the C++ symbol it
    # forwards to —
    #   M::AsyncRT::getOrCreateCPUDevice(CPUDeviceSource, const CPUDeviceOptions&, bool)
    # takes three arguments, which is why this was first read as an ABI change
    # too risky to guess at. The exported C WRAPPER is a different function:
    # it ignores its incoming registers, stack-constructs a default
    # CPUDeviceOptions, and calls the C++ function with (source=1, &options,
    # false). At the C ABI it is nullary — a drop-in replacement for the old
    # symbol, which is why the signature below is unchanged. Verified two ways:
    # by disassembling the wrapper, and at runtime by spike/runtime_probe.mojo
    # (non-null device, same pointer on a second call, ParallelismLevel 4,
    # parallelize() producing correct results inside Node).
    #
    # To re-check the export list after a nightly bump, note that `nm -gU` on
    # this library shows NOTHING useful — its exports live in the LC_DYLD
    # export trie, so nm reports only undefined imports. Use
    # `dyld_info -exports` (macOS) or `nm -D` (Linux).
    var create_rt = _sym[def() thin abi("C") -> OpaquePointer[MutAnyOrigin]](
        lib, "KGEN_CompilerRT_AsyncRT_GetOrCreateCPUDevice"
    )
    _ = create_rt()
    # `lib` owns a NAMED library, unlike every other FFI site in this project
    # (which use OwnedDLHandle() == dlopen(NULL) on the never-unmapped host
    # process image). A resolved symbol pointer does NOT borrow the handle, so
    # ASAP destruction would otherwise let `lib`'s __del__ run dlclose() at its
    # last tracked use — the _sym call — and unmap the library out from under
    # create_rt(). Keep it alive across the call explicitly.
    _ = lib^


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
