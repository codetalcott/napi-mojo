## src/napi/framework/js_boolean.mojo — ergonomic wrapper for JavaScript boolean values
##
## JsBoolean hides the raw pointer operations needed to create and read JS booleans:
##
##   # Create a JS boolean from a Mojo Bool:
##   var b = JsBoolean.create(env, True)
##   return b.value
##
##   # Read a NapiValue as a Mojo Bool:
##   var flag = JsBoolean.from_napi_value(env, napi_val)
##
## N-API note: JavaScript has true/false singletons, so napi_get_boolean returns
## the pre-existing singleton rather than allocating a new value.

from napi.types import NapiEnv, NapiValue
from napi.raw import raw_get_boolean, raw_get_value_bool
from napi.error import check_status
from napi.bindings import Bindings


## JsBoolean — typed wrapper for a JavaScript boolean napi_value
struct JsBoolean:
    ## The underlying napi_value handle. Valid within the current handle scope.
    var value: NapiValue

    def __init__(out self, value: NapiValue):
        self.value = value

    ## create — construct a JsBoolean from a Mojo Bool
    ##
    ## Calls napi_get_boolean (returns the JS true/false singleton) and checks
    ## the status.

    @staticmethod
    def create(b: Bindings, env: NapiEnv, bval: Bool) raises -> JsBoolean:
        var result: NapiValue = NapiValue(unsafe_from_address=0)
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
            to=result
        ).bitcast[NoneType]()
        var status = raw_get_boolean(b, env, bval, result_ptr)
        check_status(status)
        return JsBoolean(result)

    ## from_napi_value — read a NapiValue as a Mojo Bool
    ##
    ## Calls napi_get_value_bool and checks the status.
    ## The NapiValue must hold a JS boolean; returns a NapiError otherwise.

    @staticmethod
    def from_napi_value(
        b: Bindings, env: NapiEnv, val: NapiValue
    ) raises -> Bool:
        var bval: Bool = False
        var b_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=bval).bitcast[
            NoneType
        ]()
        var status = raw_get_value_bool(b, env, val, b_ptr)
        check_status(status)
        return bval
