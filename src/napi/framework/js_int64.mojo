## src/napi/framework/js_int64.mojo — ergonomic wrapper for Int64-backed JS numbers
##
## JsInt64 wraps napi_create_int64 and napi_get_value_int64:
##
##   var n = JsInt64.create(env, Int64(42))
##   return n.value
##
##   var i = JsInt64.from_napi_value(env, napi_val)  # returns Int64

from napi.types import NapiEnv, NapiValue
from napi.raw import raw_create_int64, raw_get_value_int64
from napi.error import check_status

struct JsInt64:
    var value: NapiValue

    fn __init__(out self, value: NapiValue):
        self.value = value

    @staticmethod
    fn create(env: NapiEnv, n: Int64) raises -> JsInt64:
        var result = NapiValue()
        check_status(raw_create_int64(env, n, UnsafePointer(to=result).bitcast[NoneType]()))
        return JsInt64(result)

    @staticmethod
    fn from_napi_value(env: NapiEnv, val: NapiValue) raises -> Int64:
        var n: Int64 = 0
        check_status(raw_get_value_int64(env, val, UnsafePointer(to=n).bitcast[NoneType]()))
        return n
