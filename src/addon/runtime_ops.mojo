## src/addon/runtime_ops.mojo — Mojo async runtime diagnostics
##
## Exists to make parallelize_safe's TWO silent failure modes visible. Both are
## silent in the same way: results or performance degrade and every other
## signal in the project stays green.
##
##   1. INIT FAILS -> sequential. parallelize_safe() quietly runs its work in a
##      plain loop: results stay correct, the build stays green, the suite
##      stays green, and every parallel speedup becomes 1x. dev2026072306 did
##      exactly that (by renaming the private KGEN symbol the init used to
##      resolve by hand) and it went undetected until someone read the source.
##      `asyncRuntimeInitOk()` exports the init result so the suite can assert
##      it. Since Mojo 1.0.0 the init delegates to the official, idempotent
##      `std.runtime.initialize_runtime()`, so a rename is no longer the likely
##      cause — but "init failed" is still unobservable without this export.
##
##   2. THE WORK RUNS BUT THE CAPTURES ARE WRONG -> garbage results. Mojo 1.1.0
##      made this concrete: a legacy closure parameter spelled bare `capturing`
##      reads a DEAD STACK SLOT with no warning and no error, and MAX 26.6
##      moved parallelize() to a unified closure argument, forcing
##      parallelize_safe to wrap `func` in a closure of its own. A wrapper that
##      captured wrongly would compile and compute garbage in silence.
##      `parallelSquares()` exports real captured work so the suite can assert
##      the VALUES, not just that init returned true.
##
## Nothing instantiates parallelize_safe in the addon graph otherwise, and Mojo
## elaborates a parametric body only when it is instantiated — so before
## parallelSquares existed, parallelize_safe could fail to compile with
## `build.sh` and the whole Jest suite green. That is not hypothetical: it is
## what the 1.1.0 bump hit, and only tests/compile/framework_coverage.mojo
## caught it. This export puts it in the addon build too.
##
## This file is also what makes src/lib.mojo type-check runtime.mojo at all —
## before it, only examples/ imported it, which is how runtime.mojo accumulated
## a latent dlclose bug and a dead symbol lookup.

from napi.types import NapiEnv, NapiValue
from napi.error import throw_js_error, throw_js_range_error
from napi.framework.js_boolean import JsBoolean
from napi.framework.js_number import JsNumber
from napi.framework.js_mojo_array import MojoFloat64Array
from napi.framework.runtime import init_async_runtime, parallelize_safe
from napi.framework.args import CbArgs
from napi.framework.register import fn_ptr, ModuleBuilder

## Written into every slot before the parallel work runs, so an index the work
## never touched is distinguishable in the failure message from one it computed
## wrongly. No legitimate result can collide with it: parallelSquares returns
## i*i*scale, and the test's scales cannot produce a negative value.
comptime UNWRITTEN_SENTINEL: Float64 = -123456789.5

## A diagnostic export should not be a way to ask the addon for a 100 GB
## allocation. 1 << 22 elements is 32 MB, far above any threshold worth
## exercising and far below anything alarming.
comptime MAX_PARALLEL_N: Int = 1 << 22


def async_runtime_init_ok_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    """asyncRuntimeInitOk() -> boolean.

    True when the Mojo async runtime initialized, i.e. parallelize_safe() will
    actually dispatch to threads. False means it silently falls back to a
    sequential loop.
    """
    var ok = True
    try:
        init_async_runtime()
    except:
        ok = False
    try:
        var b = CbArgs.get_bindings(env, info)
        return JsBoolean.create(b, env, ok).value
    except:
        return NapiValue(unsafe_from_address=Int(0))


def parallel_squares_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    """parallelSquares(n, scale) -> Float64Array where [i] = i * i * scale.

    Real work dispatched through `parallelize_safe`, shaped so that a wrong
    answer is the ONLY possible outcome of a broken capture. Every element
    depends on both captured values — the output pointer and the `scale`
    scalar — so a closure reading a dead or stale slot cannot produce a
    correct array, and the buffer is pre-filled with a sentinel so an index
    the work never visited is distinguishable from one computed wrongly.

    Deliberately not a parallelism assertion: the sequential fallback computes
    the same values by design, and `asyncRuntimeInitOk()` is what observes
    which path ran. Timing-based checks would be flaky and are not worth it.
    """
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var n = JsNumber.to_int(b, env, args[0])
        var scale = JsNumber.from_napi_value(b, env, args[1])

        if n < 1 or n > MAX_PARALLEL_N:
            throw_js_range_error(
                env, "parallelSquares: n must be between 1 and 4194304"
            )
            return NapiValue(unsafe_from_address=Int(0))

        var out = MojoFloat64Array(n)
        # Capture through plain locals, not `out.ptr` inline: the closure body
        # must not reach through a struct that Mojo may move.
        var slots = out.ptr
        var factor = scale

        for i in range(n):
            slots[unsafe_offset=i] = UNWRITTEN_SENTINEL

        def worker(i: Int) capturing:
            var x = Float64(i)
            slots[unsafe_offset=i] = x * x * factor

        parallelize_safe[worker](n)
        return out.to_js(b, env)
    except:
        # Unconditional: napi_throw_error is a documented no-op while an
        # exception is already pending, so a JS-side failure keeps its own
        # identity and a Mojo-side one still surfaces.
        throw_js_error(env, "parallelSquares requires (n: number, scale: number)")
        return NapiValue(unsafe_from_address=Int(0))


def register_runtime_ops(mut m: ModuleBuilder) raises:
    var async_runtime_init_ok_ref = async_runtime_init_ok_fn
    m.method("asyncRuntimeInitOk", fn_ptr(async_runtime_init_ok_ref))
    var parallel_squares_ref = parallel_squares_fn
    m.method("parallelSquares", fn_ptr(parallel_squares_ref))
