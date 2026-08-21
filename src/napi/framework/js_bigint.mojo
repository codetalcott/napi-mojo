## src/napi/framework/js_bigint.mojo — BigInt wrapper
##
## JsBigInt wraps creation and reading of JavaScript BigInt values.
##
## Usage:
##   var bi = JsBigInt.from_int64(env, 42)
##   var n = JsBigInt.to_int64(env, some_bigint_value)

from napi.types import NapiEnv, NapiValue
from napi.bindings import Bindings
from napi.raw import (
    raw_create_bigint_int64,
    raw_create_bigint_uint64,
    raw_get_value_bigint_int64,
    raw_get_value_bigint_uint64,
    raw_create_bigint_words,
    raw_get_value_bigint_words,
)
from std.memory.alloc import unsafe_alloc
from napi.error import check_status
from napi.keepalive import pin_across_ffi


struct JsBigInt:
    var value: NapiValue

    def __init__(out self, value: NapiValue):
        self.value = value

    @staticmethod
    def from_int64(b: Bindings, env: NapiEnv, n: Int64) raises -> JsBigInt:
        var result = NapiValue(unsafe_from_address=Int(0))
        check_status(
            raw_create_bigint_int64(
                b, env, n, Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
            )
        )
        return JsBigInt(result)

    @staticmethod
    def from_uint64(b: Bindings, env: NapiEnv, n: UInt64) raises -> JsBigInt:
        var result = NapiValue(unsafe_from_address=Int(0))
        check_status(
            raw_create_bigint_uint64(
                b, env, n, Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
            )
        )
        return JsBigInt(result)

    @staticmethod
    def to_int64(b: Bindings, env: NapiEnv, val: NapiValue) raises -> Int64:
        var result: Int64 = 0
        var lossless: Bool = False
        check_status(
            raw_get_value_bigint_int64(
                b,
                env,
                val,
                Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                Pointer(to=lossless).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        if not lossless:
            raise Error("BigInt value exceeds Int64 range")
        return result

    @staticmethod
    def to_uint64(b: Bindings, env: NapiEnv, val: NapiValue) raises -> UInt64:
        var result: UInt64 = 0
        var lossless: Bool = False
        check_status(
            raw_get_value_bigint_uint64(
                b,
                env,
                val,
                Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                Pointer(to=lossless).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        if not lossless:
            raise Error("BigInt value exceeds UInt64 range")
        return result

    @staticmethod
    def from_words(
        b: Bindings,
        env: NapiEnv,
        sign_bit: Int32,
        words_ptr: OpaquePointer[MutAnyOrigin],
        word_count: UInt,
    ) raises -> JsBigInt:
        var result = NapiValue(unsafe_from_address=Int(0))
        check_status(
            raw_create_bigint_words(
                b,
                env,
                sign_bit,
                word_count,
                words_ptr,
                Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        return JsBigInt(result)

    @staticmethod
    def word_count(b: Bindings, env: NapiEnv, val: NapiValue) raises -> UInt:
        var sign: Int32 = 0
        var count: UInt = 0
        check_status(
            raw_get_value_bigint_words(
                b,
                env,
                val,
                Pointer(to=sign).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                Pointer(to=count).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0)),
            )
        )
        # `sign` is an IGNORED output slot — this overload only reports the
        # word count. `count` is pinned by the return below; `sign` is not.
        pin_across_ffi(sign)
        return count

    @staticmethod
    def to_words(
        b: Bindings,
        env: NapiEnv,
        val: NapiValue,
        sign_ptr: OpaquePointer[MutAnyOrigin],
        words_ptr: OpaquePointer[MutAnyOrigin],
        count_ptr: OpaquePointer[MutAnyOrigin],
    ) raises:
        check_status(
            raw_get_value_bigint_words(
                b, env, val, sign_ptr, count_ptr, words_ptr
            )
        )
