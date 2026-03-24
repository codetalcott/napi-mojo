## src/addon/primitives.mojo — simple value callbacks
##
## Covers: hello, createObject, makeGreeting, greet, add, isPositive,
##         getNull, getUndefined, addInts, bitwiseOr, addIntsStrict,
##         throwTypeError, throwRangeError

from napi.types import NapiEnv, NapiValue, NAPI_TYPE_STRING, NAPI_TYPE_NUMBER
from napi.bindings import Bindings
from napi.error import throw_js_error, throw_js_error_dynamic, throw_js_type_error, throw_js_type_error_dynamic, throw_js_range_error
from napi.framework.js_object import JsObject
from napi.framework.js_string import JsString
from napi.framework.js_number import JsNumber
from napi.framework.js_boolean import JsBoolean
from napi.framework.js_null import JsNull
from napi.framework.js_undefined import JsUndefined
from napi.framework.js_int32 import JsInt32
from napi.framework.js_uint32 import JsUInt32
from napi.framework.args import CbArgs
from napi.framework.js_value import js_typeof, js_type_name
from napi.framework.register import fn_ptr, ModuleBuilder

def hello_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        return JsString.create_literal(b, env, "Hello from Mojo!").value
    except:
        return NapiValue()

def create_object_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        return JsObject.create(b, env).value
    except:
        return NapiValue()

def make_greeting_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var obj = JsObject.create(b, env)
        var msg = JsString.create_literal(b, env, "Hello!")
        obj.set_property(b, env, "message", msg.value)
        return obj.value
    except:
        return NapiValue()

def greet_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var t = js_typeof(b, env, arg0)
        if t != NAPI_TYPE_STRING:
            throw_js_error_dynamic(b, env, "greet: expected string, got " + js_type_name(t))
            return NapiValue()
        var name = JsString.from_napi_value(b, env, arg0)
        return JsString.create(b, env, "Hello, " + name + "!").value
    except:
        throw_js_error(env, "greet requires one string argument")
        return NapiValue()

def add_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var a = JsNumber.from_napi_value(b, env, args[0])
        var b2 = JsNumber.from_napi_value(b, env, args[1])
        return JsNumber.create(b, env, a + b2).value
    except:
        throw_js_error(env, "add requires two number arguments")
        return NapiValue()

def is_positive_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var n = JsNumber.from_napi_value(b, env, arg0)
        return JsBoolean.create(b, env, n > 0).value
    except:
        throw_js_error(env, "isPositive requires one number argument")
        return NapiValue()

def get_null_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        return JsNull.create(b, env).value
    except:
        return NapiValue()

def get_undefined_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        return JsUndefined.create(b, env).value
    except:
        return NapiValue()

def add_ints_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var ta = js_typeof(b, env, args[0])
        var tb = js_typeof(b, env, args[1])
        if ta != NAPI_TYPE_NUMBER or tb != NAPI_TYPE_NUMBER:
            throw_js_error(b, env, "addInts requires two number arguments")
            return NapiValue()
        var a = JsInt32.from_napi_value(b, env, args[0])
        var b2 = JsInt32.from_napi_value(b, env, args[1])
        return JsInt32.create(b, env, a + b2).value
    except:
        throw_js_error(env, "addInts requires two number arguments")
        return NapiValue()

def bitwise_or_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var ta = js_typeof(b, env, args[0])
        var tb = js_typeof(b, env, args[1])
        if ta != NAPI_TYPE_NUMBER or tb != NAPI_TYPE_NUMBER:
            throw_js_error(b, env, "bitwiseOr requires two number arguments")
            return NapiValue()
        var a = JsUInt32.from_napi_value(b, env, args[0])
        var b2 = JsUInt32.from_napi_value(b, env, args[1])
        return JsUInt32.create(b, env, a | b2).value
    except:
        throw_js_error(env, "bitwiseOr requires two number arguments")
        return NapiValue()

def throw_type_error_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        throw_js_type_error(b, env, "wrong type")
    except:
        throw_js_type_error(env, "wrong type")
    return NapiValue()

def throw_range_error_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        throw_js_range_error(b, env, "out of range")
    except:
        throw_js_range_error(env, "out of range")
    return NapiValue()

def add_ints_strict_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var ta = js_typeof(b, env, args[0])
        var tb = js_typeof(b, env, args[1])
        if ta != NAPI_TYPE_NUMBER or tb != NAPI_TYPE_NUMBER:
            throw_js_type_error_dynamic(b, env,
                "addIntsStrict: expected two numbers, got " + js_type_name(ta) + " and " + js_type_name(tb))
            return NapiValue()
        var a = JsInt32.from_napi_value(b, env, args[0])
        var b2 = JsInt32.from_napi_value(b, env, args[1])
        return JsInt32.create(b, env, a + b2).value
    except:
        throw_js_type_error(env, "addIntsStrict requires two number arguments")
        return NapiValue()

def register_primitives(mut m: ModuleBuilder) raises:
    var hello_ref = hello_fn
    var create_object_ref = create_object_fn
    var make_greeting_ref = make_greeting_fn
    var greet_ref = greet_fn
    var add_ref = add_fn
    var is_positive_ref = is_positive_fn
    var get_null_ref = get_null_fn
    var get_undefined_ref = get_undefined_fn
    var add_ints_ref = add_ints_fn
    var bitwise_or_ref = bitwise_or_fn
    var throw_type_error_ref = throw_type_error_fn
    var throw_range_error_ref = throw_range_error_fn
    var add_ints_strict_ref = add_ints_strict_fn
    m.method("hello", fn_ptr(hello_ref))
    m.method("createObject", fn_ptr(create_object_ref))
    m.method("makeGreeting", fn_ptr(make_greeting_ref))
    m.method("greet", fn_ptr(greet_ref))
    m.method("add", fn_ptr(add_ref))
    m.method("isPositive", fn_ptr(is_positive_ref))
    m.method("getNull", fn_ptr(get_null_ref))
    m.method("getUndefined", fn_ptr(get_undefined_ref))
    m.method("addInts", fn_ptr(add_ints_ref))
    m.method("bitwiseOr", fn_ptr(bitwise_or_ref))
    m.method("throwTypeError", fn_ptr(throw_type_error_ref))
    m.method("throwRangeError", fn_ptr(throw_range_error_ref))
    m.method("addIntsStrict", fn_ptr(add_ints_strict_ref))
