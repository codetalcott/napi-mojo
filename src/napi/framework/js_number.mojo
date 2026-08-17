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
from napi.raw import (
    raw_create_double,
    raw_get_value_double,
    raw_create_int64,
    raw_get_value_int64,
)
from napi.error import check_status
from napi.bindings import Bindings


## JsNumber — typed wrapper for a JavaScript number napi_value
struct JsNumber:
    ## The underlying napi_value handle. Valid within the current handle scope.
    @__allow_legacy_any_origin_fields
    var value: NapiValue

    def __init__(out self, value: NapiValue):
        self.value = value

    @staticmethod
    def create(b: Bindings, env: NapiEnv, n: Float64) raises -> JsNumber:
        var result: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=result
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var status = raw_create_double(b, env, n, result_ptr)
        check_status(status)
        return JsNumber(result)

    @staticmethod
    def from_napi_value(
        b: Bindings, env: NapiEnv, val: NapiValue
    ) raises -> Float64:
        var n: Float64 = 0.0
        var n_ptr: OpaquePointer[MutAnyOrigin] = Pointer(to=n).unsafe_bitcast[
            NoneType
        ]().as_unsafe_any_origin()
        var status = raw_get_value_double(b, env, val, n_ptr)
        check_status(status)
        return n

    @staticmethod
    def create_int(b: Bindings, env: NapiEnv, n: Int) raises -> JsNumber:
        var result = NapiValue(unsafe_from_address=Int(0))
        check_status(
            raw_create_int64(
                b, env, Int64(n), Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
            )
        )
        return JsNumber(result)

    @staticmethod
    def to_int(b: Bindings, env: NapiEnv, val: NapiValue) raises -> Int:
        var n: Int64 = 0
        check_status(
            raw_get_value_int64(
                b,
                env,
                val,
                Pointer(to=n).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        return Int(n)
