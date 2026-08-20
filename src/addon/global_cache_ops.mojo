## src/addon/global_cache_ops.mojo — makes a silent perf regression testable
##
## napi/global_cache.mojo serves the per-callback bootstrap symbol from a
## data-segment slot instead of a dlsym. That optimisation degrades SILENTLY:
## if a toolchain change ever stops honouring the `@no_inline` it depends on,
## every call simply falls back to resolving the symbol again — correct, and
## ~346 ns/call slower, with nothing failing.
##
## This is the same hazard shape as parallelize_safe()'s sequential fallback,
## and it gets the same treatment: export the state, assert it in a test.

from napi.types import NapiEnv, NapiValue
from napi.bindings import Bindings
from napi.global_cache import global_cache_is_active
from napi.framework.args import CbArgs
from napi.framework.js_boolean import JsBoolean
from napi.framework.register import fn_ptr, ModuleBuilder


def global_cache_active_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        # Reaching here already required the bootstrap, so a healthy build has
        # populated the slot by now.
        return JsBoolean.create(b, env, global_cache_is_active()).value
    except:
        return NapiValue(unsafe_from_address=Int(0))


def register_global_cache_ops(mut m: ModuleBuilder) raises:
    var global_cache_active_ref = global_cache_active_fn
    m.method("globalCacheActive", fn_ptr(global_cache_active_ref))
    _ = global_cache_active_ref
