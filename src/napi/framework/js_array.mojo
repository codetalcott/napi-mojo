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

    fn __init__(out self, value: NapiValue):
        self.value = value

    ## create_with_length — construct a new JavaScript array with the given length
    ##
    ## Calls napi_create_array_with_length and checks the status.
    ## Sets array.length to `len` but does not initialize elements (they are
    ## undefined until set).
    @staticmethod
    fn create_with_length(env: NapiEnv, len: UInt) raises -> JsArray:
        var result: NapiValue = NapiValue()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
        var status = raw_create_array_with_length(env, len, result_ptr)
        check_status(status)
        return JsArray(result)

    ## set — set the element at `index` to `val`
    ##
    ## Calls napi_set_element and checks the status.
    fn set(self, env: NapiEnv, index: UInt32, val: NapiValue) raises:
        var status = raw_set_element(env, self.value, index, val)
        check_status(status)

    ## get — return the element at `index`
    ##
    ## Calls napi_get_element and checks the status.
    fn get(self, env: NapiEnv, index: UInt32) raises -> NapiValue:
        var result: NapiValue = NapiValue()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
        var status = raw_get_element(env, self.value, index, result_ptr)
        check_status(status)
        return result

    ## length — return the array's length property as a UInt32
    ##
    ## Calls napi_get_array_length and checks the status.
    fn length(self, env: NapiEnv) raises -> UInt32:
        var len: UInt32 = 0
        var len_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=len).bitcast[NoneType]()
        var status = raw_get_array_length(env, self.value, len_ptr)
        check_status(status)
        return len

    ## has — check if an element exists at the given index
    ##
    ## Calls napi_has_element. Returns false for sparse array holes.
    fn has(self, env: NapiEnv, index: UInt32) raises -> Bool:
        var result: Bool = False
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
        var status = raw_has_element(env, self.value, index, result_ptr)
        check_status(status)
        return result

    ## delete_element — delete the element at the given index
    ##
    ## Makes the array sparse (length unchanged, element becomes undefined).
    fn delete_element(self, env: NapiEnv, index: UInt32) raises -> Bool:
        var deleted: Bool = False
        var deleted_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=deleted).bitcast[NoneType]()
        var status = raw_delete_element(env, self.value, index, deleted_ptr)
        check_status(status)
        return deleted
