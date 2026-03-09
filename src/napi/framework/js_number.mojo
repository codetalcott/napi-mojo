## src/napi/framework/js_number.mojo — ergonomic wrapper for JavaScript number values
##
## JsNumber hides the raw pointer operations needed to create and read JS numbers:
##
##   # Create a JS number from a Mojo Float64:
##   var n = JsNumber.create(env, 42.0)
##   return n.value
##
##   # Read a NapiValue as a Mojo Float64:
##   var x = JsNumber.from_napi_value(env, napi_val)
##
## Number values in N-API are always doubles (IEEE 754 Float64), matching
## JavaScript's single numeric type.

from napi.types import NapiEnv, NapiValue
from napi.raw import raw_create_double, raw_get_value_double, raw_create_int64, raw_get_value_int64
from napi.error import check_status
from napi.bindings import Bindings

## JsNumber — typed wrapper for a JavaScript number napi_value
struct JsNumber:
    ## The underlying napi_value handle. Valid within the current handle scope.
    var value: NapiValue

    fn __init__(out self, value: NapiValue):
        self.value = value

    ## create — construct a JsNumber from a Mojo Float64
    ##
    ## Calls napi_create_double and checks the status.
    ##
    ## bootstrap-safe: the no-bindings overload is retained for async complete
    ## and TSFN callbacks that lack an `info` parameter and cannot retrieve
    ## cached bindings. Use create(b, env, n) in all hot-path callbacks.
    @staticmethod
    fn create(env: NapiEnv, n: Float64) raises -> JsNumber:
        var result: NapiValue = NapiValue()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
        var status = raw_create_double(env, n, result_ptr)
        check_status(status)
        return JsNumber(result)

    @staticmethod
    fn create(b: Bindings, env: NapiEnv, n: Float64) raises -> JsNumber:
        var result: NapiValue = NapiValue()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
        var status = raw_create_double(b, env, n, result_ptr)
        check_status(status)
        return JsNumber(result)

    ## from_napi_value — read a NapiValue as a Mojo Float64
    ##
    ## Calls napi_get_value_double and checks the status.
    ## The NapiValue must hold a JS number; returns a NapiError otherwise.
    @staticmethod
    fn from_napi_value(env: NapiEnv, val: NapiValue) raises -> Float64:
        var n: Float64 = 0.0
        var n_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=n).bitcast[NoneType]()
        var status = raw_get_value_double(env, val, n_ptr)
        check_status(status)
        return n

    @staticmethod
    fn from_napi_value(b: Bindings, env: NapiEnv, val: NapiValue) raises -> Float64:
        var n: Float64 = 0.0
        var n_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=n).bitcast[NoneType]()
        var status = raw_get_value_double(b, env, val, n_ptr)
        check_status(status)
        return n

    ## create_int — construct a JS number from a Mojo Int via napi_create_int64
    @staticmethod
    fn create_int(env: NapiEnv, n: Int) raises -> JsNumber:
        var result = NapiValue()
        check_status(raw_create_int64(env, Int64(n), UnsafePointer(to=result).bitcast[NoneType]()))
        return JsNumber(result)

    @staticmethod
    fn create_int(b: Bindings, env: NapiEnv, n: Int) raises -> JsNumber:
        var result = NapiValue()
        check_status(raw_create_int64(b, env, Int64(n), UnsafePointer(to=result).bitcast[NoneType]()))
        return JsNumber(result)

    ## to_int — read a NapiValue as a Mojo Int via napi_get_value_int64
    @staticmethod
    fn to_int(env: NapiEnv, val: NapiValue) raises -> Int:
        var n: Int64 = 0
        check_status(raw_get_value_int64(env, val, UnsafePointer(to=n).bitcast[NoneType]()))
        return Int(n)

    @staticmethod
    fn to_int(b: Bindings, env: NapiEnv, val: NapiValue) raises -> Int:
        var n: Int64 = 0
        check_status(raw_get_value_int64(b, env, val, UnsafePointer(to=n).bitcast[NoneType]()))
        return Int(n)
