## src/addon/runtime_ops.mojo — Mojo async runtime diagnostics
##
## Exists to make one specific failure visible. init_async_runtime() resolves a
## symbol out of libKGENCompilerRTShared; when a Mojo nightly renames that
## symbol the lookup throws, parallelize_safe() quietly runs its work
## SEQUENTIALLY, and nothing else in the project notices — results stay correct,
## the build stays green, the test suite stays green, and every parallel
## speedup silently becomes 1x. That is exactly what dev2026072306 did, and it
## went undetected until someone read the source.
##
## Exporting the init result gives the suite something to assert, so the next
## rename fails a test instead of degrading performance in silence. It also
## makes src/lib.mojo the first thing that type-checks runtime.mojo — before
## this, only examples/ imported it, which is how it accumulated a latent
## dlclose bug and a dead symbol lookup.

from napi.types import NapiEnv, NapiValue
from napi.framework.js_boolean import JsBoolean
from napi.framework.runtime import init_async_runtime
from napi.framework.register import fn_ptr, ModuleBuilder


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
        return JsBoolean.create(env, ok).value
    except:
        return NapiValue(unsafe_from_address=Int(0))


def register_runtime_ops(mut m: ModuleBuilder) raises:
    var async_runtime_init_ok_ref = async_runtime_init_ok_fn
    m.method("asyncRuntimeInitOk", fn_ptr(async_runtime_init_ok_ref))
