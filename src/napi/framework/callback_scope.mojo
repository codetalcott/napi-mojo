## src/napi/framework/callback_scope.mojo — callback scope for async_hooks integration
##
## CallbackScope wraps napi_callback_scope, which sets up an async context for
## synchronous N-API calls made from within a native async operation.
##
## Usage (mirrors HandleScope pattern):
##   var scope = CallbackScope.open(b, env, resource_obj, ctx)
##   # ... make synchronous N-API calls here ...
##   scope.close(b, env)
##
## IMPORTANT: Mojo has no RAII — close() must be called explicitly.
## Call close() even if an exception is raised, or the scope will leak.

from napi.types import NapiEnv, NapiValue, NapiAsyncContext, NapiCallbackScope
from napi.bindings import Bindings
from napi.raw import raw_open_callback_scope, raw_close_callback_scope
from napi.error import check_status

struct CallbackScope:
    var value: NapiCallbackScope

    def __init__(out self, value: NapiCallbackScope):
        self.value = value

    ## open — create a new callback scope
    ##
    ## resource_object: JS object for async_hooks tracking, or undefined
    ## context:         async context created by JsAsyncContext.create()
    @staticmethod
    def open(
        b: Bindings,
        env: NapiEnv,
        resource_object: NapiValue,
        context: NapiAsyncContext,
    ) raises -> CallbackScope:
        var result = NapiCallbackScope()
        check_status(raw_open_callback_scope(b, env, resource_object, context,
            UnsafePointer(to=result).bitcast[NoneType]()))
        return CallbackScope(result)

    ## close — close this callback scope
    ##
    ## Must be called exactly once after open(). After calling, self.value
    ## is invalid — do not use it again.
    def close(self, b: Bindings, env: NapiEnv) raises:
        check_status(raw_close_callback_scope(b, env, self.value))
