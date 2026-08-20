## src/napi/framework/js_array.mojo — ergonomic wrapper for JavaScript array values
##
## JsArray hides the raw pointer operations needed to create and manipulate JS arrays:
##
##   # Create an array with a known length:
##   var arr = JsArray.create_with_length(env, 3)
##   arr.set(env, 0, JsNumber.create(env, 1.0).value)
##   arr.set(env, 1, JsNumber.create(env, 2.0).value)
##   arr.set(env, 2, JsNumber.create(env, 3.0).value)
##   return arr.value
##
##   # Read an element:
##   var elem = arr.get(env, 0)
##   var n = JsNumber.from_napi_value(env, elem)
##
##   # Get the length:
##   var len = arr.length(env)

from napi.types import NapiEnv, NapiValue
from napi.bindings import Bindings
from napi.raw import (
    raw_create_array_with_length,
    raw_set_element,
    raw_get_element,
    raw_get_array_length,
    raw_has_element,
    raw_delete_element,
)
from napi.error import check_status


## JsArray — typed wrapper for a JavaScript array napi_value
struct JsArray:
    ## The underlying napi_value handle. Valid within the current handle scope.
    var value: NapiValue

    def __init__(out self, value: NapiValue):
        self.value = value

    # --- Bindings-aware overloads ---

    @staticmethod
    def create_with_length(
        b: Bindings, env: NapiEnv, len: UInt
    ) raises -> JsArray:
        var result: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=result
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var status = raw_create_array_with_length(b, env, len, result_ptr)
        check_status(status)
        return JsArray(result)

    def set(
        self, b: Bindings, env: NapiEnv, index: UInt32, val: NapiValue
    ) raises:
        var status = raw_set_element(b, env, self.value, index, val)
        check_status(status)

    def get(self, b: Bindings, env: NapiEnv, index: UInt32) raises -> NapiValue:
        var result: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=result
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var status = raw_get_element(b, env, self.value, index, result_ptr)
        check_status(status)
        return result

    def length(self, b: Bindings, env: NapiEnv) raises -> UInt32:
        var len: UInt32 = 0
        var len_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=len
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var status = raw_get_array_length(b, env, self.value, len_ptr)
        check_status(status)
        return len

    def has(self, b: Bindings, env: NapiEnv, index: UInt32) raises -> Bool:
        var result: Bool = False
        var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=result
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var status = raw_has_element(b, env, self.value, index, result_ptr)
        check_status(status)
        return result

    def delete_element(
        self, b: Bindings, env: NapiEnv, index: UInt32
    ) raises -> Bool:
        var deleted: Bool = False
        var deleted_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=deleted
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var status = raw_delete_element(b, env, self.value, index, deleted_ptr)
        check_status(status)
        return deleted
