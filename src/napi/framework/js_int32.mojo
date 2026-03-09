## src/napi/framework/js_int32.mojo — ergonomic wrapper for Int32-backed JS numbers
##
## JsInt32 wraps napi_create_int32 and napi_get_value_int32:
##
##   var n = JsInt32.create(env, 42)
##   return n.value
##
##   var i = JsInt32.from_napi_value(env, napi_val)  # returns Int32

from napi.types import NapiEnv, NapiValue
from napi.raw import raw_create_int32, raw_get_value_int32
from napi.error import check_status
from napi.bindings import Bindings

struct JsInt32:
    var value: NapiValue

    fn __init__(out self, value: NapiValue):
        self.value = value

    @staticmethod
    fn create(env: NapiEnv, n: Int32) raises -> JsInt32:
        var result = NapiValue()
        check_status(raw_create_int32(env, n, UnsafePointer(to=result).bitcast[NoneType]()))
        return JsInt32(result)

    @staticmethod
    fn create(b: Bindings, env: NapiEnv, n: Int32) raises -> JsInt32:
        var result = NapiValue()
        check_status(raw_create_int32(b, env, n, UnsafePointer(to=result).bitcast[NoneType]()))
        return JsInt32(result)

    @staticmethod
    fn from_napi_value(env: NapiEnv, val: NapiValue) raises -> Int32:
        var n: Int32 = 0
        check_status(raw_get_value_int32(env, val, UnsafePointer(to=n).bitcast[NoneType]()))
        return n

    @staticmethod
    fn from_napi_value(b: Bindings, env: NapiEnv, val: NapiValue) raises -> Int32:
        var n: Int32 = 0
        check_status(raw_get_value_int32(b, env, val, UnsafePointer(to=n).bitcast[NoneType]()))
        return n
