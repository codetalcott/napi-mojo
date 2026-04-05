## src/addon/collections.mojo — object and array operation callbacks
##
## Covers: sumArray, getProperty, callFunction, mapArray,
##         getKeys, hasOwn, deleteProperty, strictEquals, isInstanceOf,
##         freezeObject, sealObject, arrayHasElement, arrayDeleteElement,
##         getPrototype, setPropertyByKey, hasPropertyByKey

from std.memory import alloc
from napi.types import (
    NapiEnv,
    NapiValue,
    NAPI_TYPE_OBJECT,
    NAPI_TYPE_FUNCTION,
    NAPI_TYPE_STRING,
)
from napi.bindings import Bindings
from napi.error import throw_js_error, throw_js_error_dynamic
from napi.framework.js_object import JsObject
from napi.framework.js_array import JsArray
from napi.framework.js_function import JsFunction
from napi.framework.js_number import JsNumber
from napi.framework.js_boolean import JsBoolean
from napi.framework.js_uint32 import JsUInt32
from napi.framework.handle_scope import HandleScope
from napi.framework.args import CbArgs
from napi.framework.js_value import (
    js_typeof,
    js_type_name,
    js_is_array,
    js_strict_equals,
)
from napi.framework.register import fn_ptr, ModuleBuilder


def sum_array_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        if not js_is_array(b, env, arg0):
            var t = js_typeof(b, env, arg0)
            throw_js_error_dynamic(
                b, env, "sumArray: expected array, got " + js_type_name(t)
            )
            return NapiValue()
        var arr = JsArray(arg0)
        var len = arr.length(b, env)
        var total: Float64 = 0.0
        for i in range(Int(len)):
            var elem = arr.get(b, env, UInt32(i))
            total += JsNumber.from_napi_value(b, env, elem)
        return JsNumber.create(b, env, total).value
    except:
        throw_js_error(env, "sumArray requires one array argument")
        return NapiValue()


def get_property_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var t0 = js_typeof(b, env, args[0])
        if t0 != NAPI_TYPE_OBJECT:
            throw_js_error_dynamic(
                b, env, "getProperty: expected object, got " + js_type_name(t0)
            )
            return NapiValue()
        var t1 = js_typeof(b, env, args[1])
        if t1 != NAPI_TYPE_STRING:
            throw_js_error_dynamic(
                b,
                env,
                "getProperty: key must be a string, got " + js_type_name(t1),
            )
            return NapiValue()
        var obj = JsObject(args[0])
        return obj.get(b, env, args[1])
    except:
        throw_js_error(env, "getProperty requires (object, string)")
        return NapiValue()


def call_function_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var t = js_typeof(b, env, args[0])
        if t != NAPI_TYPE_FUNCTION:
            throw_js_error_dynamic(
                b,
                env,
                "callFunction: expected function, got " + js_type_name(t),
            )
            return NapiValue()
        var func = JsFunction(args[0])
        return func.call1(b, env, args[1])
    except:
        throw_js_error(env, "callFunction requires (function, arg)")
        return NapiValue()


def map_array_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        if not js_is_array(b, env, args[0]):
            var t = js_typeof(b, env, args[0])
            throw_js_error_dynamic(
                b, env, "mapArray: expected array, got " + js_type_name(t)
            )
            return NapiValue()
        var t1 = js_typeof(b, env, args[1])
        if t1 != NAPI_TYPE_FUNCTION:
            throw_js_error_dynamic(
                b, env, "mapArray: expected function, got " + js_type_name(t1)
            )
            return NapiValue()
        var arr = JsArray(args[0])
        var func = JsFunction(args[1])
        var len = arr.length(b, env)
        var result = JsArray.create_with_length(b, env, UInt(len))
        for i in range(Int(len)):
            var hs = HandleScope.open(b, env)
            var ok = True
            try:
                var elem = arr.get(b, env, UInt32(i))
                var mapped = func.call1(b, env, elem)
                result.set(b, env, UInt32(i), mapped)
            except:
                ok = False
            hs.close(b, env)
            if not ok:
                raise Error("mapArray: callback failed at index " + String(i))
        return result.value
    except:
        throw_js_error(env, "mapArray requires (array, function)")
        return NapiValue()


def get_keys_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var t0 = js_typeof(b, env, arg0)
        if t0 != NAPI_TYPE_OBJECT:
            throw_js_error_dynamic(
                b, env, "getKeys: expected object, got " + js_type_name(t0)
            )
            return NapiValue()
        var obj = JsObject(arg0)
        return obj.keys(b, env)
    except:
        throw_js_error(env, "getKeys requires one object argument")
        return NapiValue()


def has_own_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var t0 = js_typeof(b, env, args[0])
        if t0 != NAPI_TYPE_OBJECT:
            throw_js_error_dynamic(
                b, env, "hasOwn: expected object, got " + js_type_name(t0)
            )
            return NapiValue()
        var obj = JsObject(args[0])
        var result = obj.has_own(b, env, args[1])
        return JsBoolean.create(b, env, result).value
    except:
        throw_js_error(env, "hasOwn requires (object, key)")
        return NapiValue()


def delete_property_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var t0 = js_typeof(b, env, args[0])
        if t0 != NAPI_TYPE_OBJECT:
            throw_js_error_dynamic(
                b,
                env,
                "deleteProperty: expected object, got " + js_type_name(t0),
            )
            return NapiValue()
        var obj = JsObject(args[0])
        _ = obj.delete_prop(b, env, args[1])
        return obj.value
    except:
        throw_js_error(env, "deleteProperty requires (object, key)")
        return NapiValue()


def array_has_element_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        if not js_is_array(b, env, args[0]):
            throw_js_error(
                b, env, "arrayHasElement: first argument must be an array"
            )
            return NapiValue()
        var arr = JsArray(args[0])
        var index = JsUInt32.from_napi_value(b, env, args[1])
        var result = arr.has(b, env, index)
        return JsBoolean.create(b, env, result).value
    except:
        throw_js_error(env, "arrayHasElement requires (array, index)")
        return NapiValue()


def array_delete_element_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        if not js_is_array(b, env, args[0]):
            throw_js_error(
                b, env, "arrayDeleteElement: first argument must be an array"
            )
            return NapiValue()
        var arr = JsArray(args[0])
        var index = JsUInt32.from_napi_value(b, env, args[1])
        _ = arr.delete_element(b, env, index)
        return arr.value
    except:
        throw_js_error(env, "arrayDeleteElement requires (array, index)")
        return NapiValue()


def get_prototype_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var t0 = js_typeof(b, env, arg0)
        if t0 != NAPI_TYPE_OBJECT:
            throw_js_error_dynamic(
                b, env, "getPrototype: expected object, got " + js_type_name(t0)
            )
            return NapiValue()
        var obj = JsObject(arg0)
        return obj.prototype(b, env)
    except:
        throw_js_error(env, "getPrototype requires one object argument")
        return NapiValue()


def strict_equals_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var eq = js_strict_equals(b, env, args[0], args[1])
        return JsBoolean.create(b, env, eq).value
    except:
        throw_js_error(env, "strictEquals requires two arguments")
        return NapiValue()


def is_instance_of_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var t1 = js_typeof(b, env, args[1])
        if t1 != NAPI_TYPE_FUNCTION:
            throw_js_error_dynamic(
                b,
                env,
                "isInstanceOf: second arg must be a constructor, got "
                + js_type_name(t1),
            )
            return NapiValue()
        var obj = JsObject(args[0])
        var result = obj.instance_of(b, env, args[1])
        return JsBoolean.create(b, env, result).value
    except:
        throw_js_error(env, "isInstanceOf requires (value, constructor)")
        return NapiValue()


def freeze_object_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var t0 = js_typeof(b, env, arg0)
        if t0 != NAPI_TYPE_OBJECT:
            throw_js_error_dynamic(
                b, env, "freezeObject: expected object, got " + js_type_name(t0)
            )
            return NapiValue()
        var obj = JsObject(arg0)
        obj.freeze(b, env)
        return obj.value
    except:
        throw_js_error(env, "freezeObject requires one object argument")
        return NapiValue()


def seal_object_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var t0 = js_typeof(b, env, arg0)
        if t0 != NAPI_TYPE_OBJECT:
            throw_js_error_dynamic(
                b, env, "sealObject: expected object, got " + js_type_name(t0)
            )
            return NapiValue()
        var obj = JsObject(arg0)
        obj.seal(b, env)
        return obj.value
    except:
        throw_js_error(env, "sealObject requires one object argument")
        return NapiValue()


def set_property_by_key_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var argc = CbArgs.argc(b, env, info)
        var argv = alloc[NapiValue](Int(argc))
        CbArgs.get_argv(b, env, info, argc, argv)
        var obj = argv[0]
        var key = argv[1]
        var val = argv[2]
        JsObject(obj).set(b, env, key, val)
        argv.free()
        return obj
    except:
        throw_js_error(env, "setPropertyByKey failed")
        return NapiValue()


def has_property_by_key_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var result = JsObject(args[0]).has(b, env, args[1])
        return JsBoolean.create(b, env, result).value
    except:
        throw_js_error(env, "hasPropertyByKey failed")
        return NapiValue()


def register_collections(mut m: ModuleBuilder) raises:
    var sum_array_ref = sum_array_fn
    var get_property_ref = get_property_fn
    var call_function_ref = call_function_fn
    var map_array_ref = map_array_fn
    var get_keys_ref = get_keys_fn
    var has_own_ref = has_own_fn
    var delete_property_ref = delete_property_fn
    var array_has_element_ref = array_has_element_fn
    var array_delete_element_ref = array_delete_element_fn
    var get_prototype_ref = get_prototype_fn
    var strict_equals_ref = strict_equals_fn
    var is_instance_of_ref = is_instance_of_fn
    var freeze_object_ref = freeze_object_fn
    var seal_object_ref = seal_object_fn
    var set_property_by_key_ref = set_property_by_key_fn
    var has_property_by_key_ref = has_property_by_key_fn
    m.method("sumArray", fn_ptr(sum_array_ref))
    m.method("getProperty", fn_ptr(get_property_ref))
    m.method("callFunction", fn_ptr(call_function_ref))
    m.method("mapArray", fn_ptr(map_array_ref))
    m.method("getKeys", fn_ptr(get_keys_ref))
    m.method("hasOwn", fn_ptr(has_own_ref))
    m.method("deleteProperty", fn_ptr(delete_property_ref))
    m.method("arrayHasElement", fn_ptr(array_has_element_ref))
    m.method("arrayDeleteElement", fn_ptr(array_delete_element_ref))
    m.method("getPrototype", fn_ptr(get_prototype_ref))
    m.method("strictEquals", fn_ptr(strict_equals_ref))
    m.method("isInstanceOf", fn_ptr(is_instance_of_ref))
    m.method("freezeObject", fn_ptr(freeze_object_ref))
    m.method("sealObject", fn_ptr(seal_object_ref))
    m.method("setPropertyByKey", fn_ptr(set_property_by_key_ref))
    m.method("hasPropertyByKey", fn_ptr(has_property_by_key_ref))
