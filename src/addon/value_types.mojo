## src/addon/value_types.mojo — BigInt, Date, Symbol, and word-level BigInt ops

from std.memory import alloc
from napi.types import NapiEnv, NapiValue, NAPI_TYPE_BIGINT
from napi.bindings import Bindings
from napi.error import throw_js_error, throw_js_error_dynamic, check_status
from napi.raw import raw_symbol_for, raw_get_value_bigint_words
from napi.framework.js_number import JsNumber
from napi.framework.js_bigint import JsBigInt
from napi.framework.js_date import JsDate
from napi.framework.js_symbol import JsSymbol
from napi.framework.js_string import JsString
from napi.framework.js_array import JsArray
from napi.framework.js_object import JsObject
from napi.framework.args import CbArgs
from napi.framework.js_value import js_typeof, js_type_name
from napi.framework.register import fn_ptr, ModuleBuilder


def add_bigints_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var ta = js_typeof(b, env, args[0])
        var tb = js_typeof(b, env, args[1])
        if ta != NAPI_TYPE_BIGINT or tb != NAPI_TYPE_BIGINT:
            throw_js_error_dynamic(
                b,
                env,
                "addBigInts: expected bigint, got "
                + js_type_name(ta)
                + " and "
                + js_type_name(tb),
            )
            return NapiValue()
        var a = JsBigInt.to_int64(b, env, args[0])
        var b2 = JsBigInt.to_int64(b, env, args[1])
        return JsBigInt.from_int64(b, env, a + b2).value
    except:
        throw_js_error(env, "addBigInts requires two bigint arguments")
        return NapiValue()


def create_date_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var ts = JsNumber.from_napi_value(b, env, arg0)
        return JsDate.create(b, env, ts).value
    except:
        throw_js_error(env, "createDate requires one number argument")
        return NapiValue()


def get_date_value_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var d = JsDate(arg0)
        var ts = d.timestamp_ms(b, env)
        return JsNumber.create(b, env, ts).value
    except:
        throw_js_error(env, "getDateValue requires one Date argument")
        return NapiValue()


def create_symbol_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        return JsSymbol.create(b, env, arg0).value
    except:
        throw_js_error(env, "createSymbol requires one string argument")
        return NapiValue()


def symbol_for_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var key = JsString.from_napi_value(b, env, arg0)
        var key_ptr: OpaquePointer[ImmutAnyOrigin] = key.unsafe_ptr().bitcast[
            NoneType
        ]()
        var key_len = UInt(len(key))
        var result = NapiValue()
        check_status(
            raw_symbol_for(
                b,
                env,
                key_ptr,
                key_len,
                UnsafePointer(to=result).bitcast[NoneType](),
            )
        )
        _ = key^  # prevent ASAP destruction before raw_symbol_for reads key_ptr
        return result
    except:
        throw_js_error(env, "symbolFor requires one string argument")
        return NapiValue()


def bigint_from_words_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var sign_bit = Int32(JsNumber.from_napi_value(b, env, args[0]))
        var arr_val = args[1]
        var arr = JsArray(arr_val)
        var arr_len = arr.length(b, env)
        var words_ptr = alloc[UInt64](Int(arr_len))
        for i in range(Int(arr_len)):
            var elem = arr.get(b, env, UInt32(i))
            var num = JsNumber.from_napi_value(b, env, elem)
            words_ptr[i] = UInt64(num)
        var result = JsBigInt.from_words(
            b, env, sign_bit, words_ptr.bitcast[NoneType](), UInt(arr_len)
        )
        words_ptr.free()
        return result.value
    except:
        throw_js_error(env, "bigIntFromWords failed")
        return NapiValue()


def bigint_to_words_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var sign: Int32 = 0
        var count: UInt = 16
        var words_ptr = alloc[UInt64](16)
        check_status(
            raw_get_value_bigint_words(
                b,
                env,
                arg0,
                UnsafePointer(to=sign).bitcast[NoneType](),
                UnsafePointer(to=count).bitcast[NoneType](),
                words_ptr.bitcast[NoneType](),
            )
        )
        var obj = JsObject.create(b, env)
        obj.set_property(
            b, env, "sign", JsNumber.create_int(b, env, Int(sign)).value
        )
        var arr = JsArray.create_with_length(b, env, count)
        for i in range(Int(count)):
            var word_val = JsNumber.create(b, env, Float64(words_ptr[i]))
            arr.set(b, env, UInt32(i), word_val.value)
        obj.set_property(b, env, "words", arr.value)
        words_ptr.free()
        return obj.value
    except:
        throw_js_error(env, "bigIntToWords failed")
        return NapiValue()


def register_value_types(mut m: ModuleBuilder) raises:
    var add_bigints_ref = add_bigints_fn
    var create_date_ref = create_date_fn
    var get_date_value_ref = get_date_value_fn
    var create_symbol_ref = create_symbol_fn
    var symbol_for_ref = symbol_for_fn
    var bigint_from_words_ref = bigint_from_words_fn
    var bigint_to_words_ref = bigint_to_words_fn
    m.method("addBigInts", fn_ptr(add_bigints_ref))
    m.method("createDate", fn_ptr(create_date_ref))
    m.method("getDateValue", fn_ptr(get_date_value_ref))
    m.method("createSymbol", fn_ptr(create_symbol_ref))
    m.method("symbolFor", fn_ptr(symbol_for_ref))
    m.method("bigIntFromWords", fn_ptr(bigint_from_words_ref))
    m.method("bigIntToWords", fn_ptr(bigint_to_words_ref))
