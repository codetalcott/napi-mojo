## src/napi/framework/js_bigint.mojo — BigInt wrapper
##
## JsBigInt wraps creation and reading of JavaScript BigInt values.
##
## Usage:
##   var bi = JsBigInt.from_int64(env, 42)
##   var n = JsBigInt.to_int64(env, some_bigint_value)

from napi.types import NapiEnv, NapiValue
from napi.raw import (
    raw_create_bigint_int64, raw_create_bigint_uint64,
    raw_get_value_bigint_int64, raw_get_value_bigint_uint64,
)
from napi.error import check_status

struct JsBigInt:
    var value: NapiValue

    fn __init__(out self, value: NapiValue):
        self.value = value

    @staticmethod
    fn from_int64(env: NapiEnv, n: Int64) raises -> JsBigInt:
        var result = NapiValue()
        check_status(raw_create_bigint_int64(env, n,
            UnsafePointer(to=result).bitcast[NoneType]()))
        return JsBigInt(result)

    @staticmethod
    fn from_uint64(env: NapiEnv, n: UInt64) raises -> JsBigInt:
        var result = NapiValue()
        check_status(raw_create_bigint_uint64(env, n,
            UnsafePointer(to=result).bitcast[NoneType]()))
        return JsBigInt(result)

    @staticmethod
    fn to_int64(env: NapiEnv, val: NapiValue) raises -> Int64:
        var result: Int64 = 0
        var lossless: Bool = False
        check_status(raw_get_value_bigint_int64(env, val,
            UnsafePointer(to=result).bitcast[NoneType](),
            UnsafePointer(to=lossless).bitcast[NoneType]()))
        if not lossless:
            raise Error("BigInt value exceeds Int64 range")
        return result

    @staticmethod
    fn to_uint64(env: NapiEnv, val: NapiValue) raises -> UInt64:
        var result: UInt64 = 0
        var lossless: Bool = False
        check_status(raw_get_value_bigint_uint64(env, val,
            UnsafePointer(to=result).bitcast[NoneType](),
            UnsafePointer(to=lossless).bitcast[NoneType]()))
        if not lossless:
            raise Error("BigInt value exceeds UInt64 range")
        return result
