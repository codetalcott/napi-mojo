## src/napi/framework/js_undefined.mojo — ergonomic wrapper for the JavaScript undefined value
##
## JsUndefined wraps napi_get_undefined, which returns the pre-existing undefined singleton:
##
##   var undef_val = JsUndefined.create(env)
##   return undef_val.value
##
## N-API note: JavaScript undefined is a singleton, so napi_get_undefined returns
## the same napi_value every time within a given napi_env.

from napi.types import NapiEnv, NapiValue
from napi.raw import raw_get_undefined
from napi.error import check_status
from napi.bindings import Bindings

## JsUndefined — typed wrapper for the JavaScript undefined napi_value
struct JsUndefined:
    ## The underlying napi_value handle (the undefined singleton).
    var value: NapiValue

    def __init__(out self, value: NapiValue):
        self.value = value

    ## create — return the JavaScript undefined singleton
    ##
    ## Calls napi_get_undefined and checks the status.

    @staticmethod
    def create(b: Bindings, env: NapiEnv) raises -> JsUndefined:
        var result: NapiValue = NapiValue()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
        var status = raw_get_undefined(b, env, result_ptr)
        check_status(status)
        return JsUndefined(result)
