## src/napi/framework/js_null.mojo — ergonomic wrapper for the JavaScript null value
##
## JsNull wraps napi_get_null, which returns the pre-existing null singleton:
##
##   var null_val = JsNull.create(env)
##   return null_val.value
##
## N-API note: JavaScript null is a singleton, so napi_get_null returns the
## same napi_value every time within a given napi_env.

from napi.types import NapiEnv, NapiValue
from napi.raw import raw_get_null
from napi.error import check_status
from napi.bindings import Bindings


## JsNull — typed wrapper for the JavaScript null napi_value
struct JsNull:
    ## The underlying napi_value handle (the null singleton).
    var value: NapiValue

    def __init__(out self, value: NapiValue):
        self.value = value

    ## create — return the JavaScript null singleton
    ##
    ## Calls napi_get_null and checks the status.

    @staticmethod
    def create(b: Bindings, env: NapiEnv) raises -> JsNull:
        var result: NapiValue = NapiValue()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
            to=result
        ).bitcast[NoneType]()
        var status = raw_get_null(b, env, result_ptr)
        check_status(status)
        return JsNull(result)
