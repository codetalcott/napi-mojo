## src/napi/framework/js_string.mojo — ergonomic wrapper for JavaScript string values
##
## JsString hides the raw pointer operations needed to create a JS string via
## napi_create_string_utf8, giving addon authors a clean API:
##
##   var s = JsString.create(env, "Hello!")   # raises on N-API failure
##   return s.value                            # hand the NapiValue back to Node.js
##
## String lifetime: JsString.create() borrows the input Mojo String for the
## duration of the N-API call. The underlying napi_value is owned by the
## Node.js GC and valid until the current handle scope is collected.

from napi.types import NapiEnv, NapiValue
from napi.raw import raw_create_string_utf8
from napi.error import check_status

## JsString — typed wrapper for a JavaScript string napi_value
struct JsString:
    ## The underlying napi_value handle. Valid within the current handle scope.
    var value: NapiValue

    fn __init__(out self, value: NapiValue):
        self.value = value

    ## create — construct a JsString from a Mojo String
    ##
    ## Calls napi_create_string_utf8 and checks the status. The input string `s`
    ## must remain alive for the duration of this call (it is borrowed, not copied).
    @staticmethod
    fn create(env: NapiEnv, s: String) raises -> JsString:
        var result: NapiValue = NapiValue()
        var str_ptr: OpaquePointer[ImmutAnyOrigin] = s.unsafe_ptr().bitcast[NoneType]()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
        var status = raw_create_string_utf8(env, str_ptr, UInt(len(s)), result_ptr)
        check_status(status)
        return JsString(result)
