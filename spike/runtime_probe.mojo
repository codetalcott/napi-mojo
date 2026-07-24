## runtime_probe.mojo — AsyncRT runtime-init spike
##
## PURPOSE: throwaway validation code, same role as ffi_probe.mojo. It answers,
## from inside a real Node.js process, whether the Mojo async runtime can be
## initialized from a dlopen'd .node addon — the precondition for parallelize().
## Re-run it whenever a Mojo nightly changes libKGENCompilerRTShared.
##
## BACKGROUND: dev2026072306 removed KGEN_CompilerRT_AsyncRT_GetOrCreateRuntime,
## the zero-arg entry point src/napi/framework/runtime.mojo used. The library now
## exports KGEN_CompilerRT_AsyncRT_GetOrCreateCPUDevice. Its C++ counterpart is
##   M::AsyncRT::getOrCreateCPUDevice(CPUDeviceSource, const CPUDeviceOptions&, bool)
## which takes three arguments — but that is the C++ symbol, NOT the exported C
## wrapper. Disassembly of the wrapper shows it ignores its incoming registers,
## stack-constructs a default CPUDeviceOptions, and calls the C++ function with
## (source=1, &options, false). At the C ABI it is NULLARY:
##   void* KGEN_CompilerRT_AsyncRT_GetOrCreateCPUDevice(void)
## i.e. a drop-in replacement for the removed symbol. This spike is what proves
## that claim at runtime rather than by reading disassembly.
##
## TOOLING NOTE: `nm -gU libKGENCompilerRTShared.dylib` reports NOTHING useful —
## the library's exports live in the LC_DYLD export trie, not the classic symbol
## table, so nm shows only its 231 undefined imports. Use `dyld_info -exports`
## (macOS) or `nm -D` (Linux) to list what is actually exported.
##
## QUESTIONS THIS ANSWERS:
##
##   1. Does KGEN_CompilerRT_AsyncRT_GetOrCreateCPUDevice resolve from a .node
##      addon, and is it callable as a nullary thin abi("C") function?
##   2. Does it return a non-null device, and is it idempotent (same pointer on
##      a second call)? runtime.mojo's docstring promises "safe to call multiple
##      times"; the compiler binary carries an assertion string about repeated
##      calls with differing options, so this must be checked, not assumed.
##   3. Does ParallelismLevel report more than one worker — i.e. is this a real
##      thread pool, not a degenerate single-worker runtime?
##   4. Does parallelize() actually run and produce correct results afterwards?
##      Without init it SIGSEGVs, so reaching this line at all is the signal.
##
## HOW TO RUN:
##   pixi run mojo build --emit shared-lib -I src spike/runtime_probe.mojo \
##     -o build/runtime_probe.dylib
##   cp build/runtime_probe.dylib build/runtime_probe.node
##   node -e "console.log(require('./build/runtime_probe.node').probe())"
##
## EXPECTED: { deviceOk: true, idempotent: true, parallelismLevel: >1,
##             parallelSum: 4950, expected: 4950 }

from std.ffi import OwnedDLHandle
from std.algorithm import parallelize
from std.memory import alloc
from napi.types import NapiEnv, NapiValue
from napi.raw import _sym
from napi.framework.js_object import JsObject
from napi.framework.js_number import JsNumber
from napi.framework.js_boolean import JsBoolean
from napi.framework.register import ModuleBuilder, fn_ptr

comptime N: Int = 100

## The exported C wrapper. Nullary despite the three-argument C++ symbol
## it forwards to — see the header comment.
comptime GetOrCreateCPUDeviceFn = def() thin abi("C") -> OpaquePointer[
    MutAnyOrigin
]
comptime ParallelismLevelFn = def() thin abi("C") -> Int


def _open_kgen() raises -> OwnedDLHandle:
    try:
        return OwnedDLHandle("libKGENCompilerRTShared.dylib")
    except:
        return OwnedDLHandle("libKGENCompilerRTShared.so")


def probe_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var lib = _open_kgen()

        # Q1/Q2: resolve, call twice, compare.
        var get_dev = _sym[GetOrCreateCPUDeviceFn](
            lib, "KGEN_CompilerRT_AsyncRT_GetOrCreateCPUDevice"
        )
        var dev1 = get_dev()
        var dev2 = get_dev()
        var device_ok = Int(dev1) != 0
        var idempotent = Int(dev1) == Int(dev2)

        # Q3: how many workers does the runtime think it has?
        var level: Int
        try:
            var plevel = _sym[ParallelismLevelFn](
                lib, "KGEN_CompilerRT_AsyncRT_ParallelismLevel"
            )
            level = plevel()
        except:
            level = -1

        # `lib` owns a NAMED library: a resolved symbol pointer does not borrow
        # the handle, so ASAP destruction would dlclose it at the last tracked
        # use (the _sym call) and unmap it out from under the calls above.
        _ = lib^

        # Q4: does parallelize() actually run now? Sum 0..N-1 across workers.
        var partials = alloc[Float64](N)
        for i in range(N):
            partials[i] = 0.0

        def worker(i: Int) capturing:
            partials[i] = Float64(i)

        parallelize[worker](N)

        var total: Float64 = 0.0
        for i in range(N):
            total += partials[i]
        partials.free()

        var expected = Float64(N * (N - 1) // 2)

        var out = JsObject.create(env)
        out.set_property(env, "deviceOk", JsBoolean.create(env, device_ok).value)
        out.set_property(
            env, "idempotent", JsBoolean.create(env, idempotent).value
        )
        out.set_property(
            env, "parallelismLevel", JsNumber.create_int(env, level).value
        )
        out.set_property(env, "parallelSum", JsNumber.create(env, total).value)
        out.set_property(
            env, "expected", JsNumber.create(env, expected).value
        )
        return out.value
    except:
        return NapiValue(unsafe_from_address=Int(0))


@export("napi_register_module_v1")
def register_module(env: NapiEnv, exports: NapiValue) abi("C") -> NapiValue:
    var probe_ref = probe_fn
    try:
        var m = ModuleBuilder(env, exports)
        m.method("probe", fn_ptr(probe_ref))
        m.flush()
    except:
        pass
    return exports
