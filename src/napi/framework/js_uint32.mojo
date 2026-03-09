## src/napi/framework/js_uint32.mojo — ergonomic wrapper for UInt32-backed JS numbers
##
## JsUInt32 wraps napi_create_uint32 and napi_get_value_uint32:
##
##   var n = JsUInt32.create(env, UInt32(42))
##   return n.value
##
##   var i = JsUInt32.from_napi_value(env, napi_val)  # returns UInt32

from napi.types import NapiEnv, NapiValue
from napi.raw import raw_create_uint32, raw_get_value_uint32
from napi.error import check_status
from napi.bindings import Bindings

struct JsUInt32:
    var value: NapiValue

    fn __init__(out self, value: NapiValue):
        self.value = value

    @staticmethod
    fn create(env: NapiEnv, n: UInt32) raises -> JsUInt32:
        var result = NapiValue()
        check_status(raw_create_uint32(env, n, UnsafePointer(to=result).bitcast[NoneType]()))
        return JsUInt32(result)

    @staticmethod
    fn create(b: Bindings, env: NapiEnv, n: UInt32) raises -> JsUInt32:
        var result = NapiValue()
        check_status(raw_create_uint32(b, env, n, UnsafePointer(to=result).bitcast[NoneType]()))
        return JsUInt32(result)

    @staticmethod
    fn from_napi_value(env: NapiEnv, val: NapiValue) raises -> UInt32:
        var n: UInt32 = 0
        check_status(raw_get_value_uint32(env, val, UnsafePointer(to=n).bitcast[NoneType]()))
        return n

    @staticmethod
    fn from_napi_value(b: Bindings, env: NapiEnv, val: NapiValue) raises -> UInt32:
        var n: UInt32 = 0
        check_status(raw_get_value_uint32(b, env, val, UnsafePointer(to=n).bitcast[NoneType]()))
        return n
