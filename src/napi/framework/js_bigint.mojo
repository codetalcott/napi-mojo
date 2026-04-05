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
from std.memory import alloc
from napi.error import check_status


struct JsBigInt:
    var value: NapiValue

    def __init__(out self, value: NapiValue):
        self.value = value

    @staticmethod
    def from_int64(env: NapiEnv, n: Int64) raises -> JsBigInt:
        var result = NapiValue()
        check_status(
            raw_create_bigint_int64(
                env, n, UnsafePointer(to=result).bitcast[NoneType]()
            )
        )
        return JsBigInt(result)

    @staticmethod
    def from_int64(b: Bindings, env: NapiEnv, n: Int64) raises -> JsBigInt:
        var result = NapiValue()
        check_status(
            raw_create_bigint_int64(
                b, env, n, UnsafePointer(to=result).bitcast[NoneType]()
            )
        )
        return JsBigInt(result)

    @staticmethod
    def from_uint64(env: NapiEnv, n: UInt64) raises -> JsBigInt:
        var result = NapiValue()
        check_status(
            raw_create_bigint_uint64(
                env, n, UnsafePointer(to=result).bitcast[NoneType]()
            )
        )
        return JsBigInt(result)

    @staticmethod
    def from_uint64(b: Bindings, env: NapiEnv, n: UInt64) raises -> JsBigInt:
        var result = NapiValue()
        check_status(
            raw_create_bigint_uint64(
                b, env, n, UnsafePointer(to=result).bitcast[NoneType]()
            )
        )
        return JsBigInt(result)

    @staticmethod
    def to_int64(env: NapiEnv, val: NapiValue) raises -> Int64:
        var result: Int64 = 0
        var lossless: Bool = False
        check_status(
            raw_get_value_bigint_int64(
                env,
                val,
                UnsafePointer(to=result).bitcast[NoneType](),
                UnsafePointer(to=lossless).bitcast[NoneType](),
            )
        )
        if not lossless:
            raise Error("BigInt value exceeds Int64 range")
        return result

    @staticmethod
    def to_int64(b: Bindings, env: NapiEnv, val: NapiValue) raises -> Int64:
        var result: Int64 = 0
        var lossless: Bool = False
        check_status(
            raw_get_value_bigint_int64(
                b,
                env,
                val,
                UnsafePointer(to=result).bitcast[NoneType](),
                UnsafePointer(to=lossless).bitcast[NoneType](),
            )
        )
        if not lossless:
            raise Error("BigInt value exceeds Int64 range")
        return result

    @staticmethod
    def to_uint64(env: NapiEnv, val: NapiValue) raises -> UInt64:
        var result: UInt64 = 0
        var lossless: Bool = False
        check_status(
            raw_get_value_bigint_uint64(
                env,
                val,
                UnsafePointer(to=result).bitcast[NoneType](),
                UnsafePointer(to=lossless).bitcast[NoneType](),
            )
        )
        if not lossless:
            raise Error("BigInt value exceeds UInt64 range")
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
                UnsafePointer(to=result).bitcast[NoneType](),
                UnsafePointer(to=lossless).bitcast[NoneType](),
            )
        )
        if not lossless:
            raise Error("BigInt value exceeds UInt64 range")
        return result

    ## from_words — create BigInt from sign bit and array of UInt64 words
    @staticmethod
    def from_words(
        env: NapiEnv,
        sign_bit: Int32,
        words_ptr: OpaquePointer[MutAnyOrigin],
        word_count: UInt,
    ) raises -> JsBigInt:
        var result = NapiValue()
        check_status(
            raw_create_bigint_words(
                env,
                sign_bit,
                word_count,
                words_ptr,
                UnsafePointer(to=result).bitcast[NoneType](),
            )
        )
        return JsBigInt(result)

    @staticmethod
    def from_words(
        b: Bindings,
        env: NapiEnv,
        sign_bit: Int32,
        words_ptr: OpaquePointer[MutAnyOrigin],
        word_count: UInt,
    ) raises -> JsBigInt:
        var result = NapiValue()
        check_status(
            raw_create_bigint_words(
                b,
                env,
                sign_bit,
                word_count,
                words_ptr,
                UnsafePointer(to=result).bitcast[NoneType](),
            )
        )
        return JsBigInt(result)

    ## word_count — query number of 64-bit words needed to represent a BigInt
    @staticmethod
    def word_count(env: NapiEnv, val: NapiValue) raises -> UInt:
        var sign: Int32 = 0
        var count: UInt = 0
        check_status(
            raw_get_value_bigint_words(
                env,
                val,
                UnsafePointer(to=sign).bitcast[NoneType](),
                UnsafePointer(to=count).bitcast[NoneType](),
                OpaquePointer[MutAnyOrigin](),
            )
        )
        return count

    @staticmethod
    def word_count(b: Bindings, env: NapiEnv, val: NapiValue) raises -> UInt:
        var sign: Int32 = 0
        var count: UInt = 0
        check_status(
            raw_get_value_bigint_words(
                b,
                env,
                val,
                UnsafePointer(to=sign).bitcast[NoneType](),
                UnsafePointer(to=count).bitcast[NoneType](),
                OpaquePointer[MutAnyOrigin](),
            )
        )
        return count

    ## to_words — extract sign and words from a BigInt into pre-allocated buffers
    @staticmethod
    def to_words(
        env: NapiEnv,
        val: NapiValue,
        sign_ptr: OpaquePointer[MutAnyOrigin],
        words_ptr: OpaquePointer[MutAnyOrigin],
        count_ptr: OpaquePointer[MutAnyOrigin],
    ) raises:
        check_status(
            raw_get_value_bigint_words(env, val, sign_ptr, count_ptr, words_ptr)
        )

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
