## src/addon/convert_ops.mojo — collection and object helper callbacks (E6, Steps 1+2)
##
## Demonstrates concrete and parametric array helpers plus object helpers.

from napi.types import NapiEnv, NapiValue
from napi.bindings import Bindings
from napi.error import throw_js_error, throw_js_type_error
from napi.framework.js_number import JsNumber
from napi.framework.js_string import JsString
from napi.framework.js_array import JsArray
from napi.framework.js_boolean import JsBoolean
from napi.framework.js_object import JsObject
from napi.framework.args import CbArgs
from napi.framework.register import fn_ptr, ModuleBuilder
from napi.framework.convert import (
    to_js_array_f64, from_js_array_f64, to_js_array_str, from_js_array_str,
    to_js_array, from_js_array, JsF64, JsStr, JsBool,
)

## sumJsArray — accepts a JS number array, returns sum of all elements
fn sum_js_array_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var items = from_js_array_f64(b, env, arg0)
        var total: Float64 = 0.0
        for i in range(len(items)):
            total += items[i]
        return JsNumber.create(b, env, total).value
    except:
        throw_js_type_error(env, "sumJsArray: expected array of numbers")
        return NapiValue()

## doubleArray — accepts a JS number array, returns new array with each element doubled
fn double_array_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var items = from_js_array_f64(b, env, arg0)
        var doubled = List[Float64]()
        for i in range(len(items)):
            doubled.append(items[i] * 2.0)
        return to_js_array_f64(b, env, doubled)
    except:
        throw_js_type_error(env, "doubleArray: expected array of numbers")
        return NapiValue()

## joinStrings — accepts a JS string array and separator, returns joined string
fn join_strings_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var arr_val = args[0]
        var sep_val = args[1]
        var items = from_js_array_str(b, env, arr_val)
        var sep = JsString.from_napi_value(b, env, sep_val)
        var result = String("")
        for i in range(len(items)):
            if i > 0:
                result += sep
            result += items[i]
        return JsString.create(b, env, result).value
    except:
        throw_js_type_error(env, "joinStrings: expected (string[], string)")
        return NapiValue()

## reverseStrings — accepts a JS string array, returns new array reversed
fn reverse_strings_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var items = from_js_array_str(b, env, arg0)
        var reversed = List[String]()
        var n = len(items)
        for i in range(n):
            reversed.append(items[n - 1 - i])
        return to_js_array_str(b, env, reversed)
    except:
        throw_js_type_error(env, "reverseStrings: expected array of strings")
        return NapiValue()

## genericDoubleArray — doubles each element using parametric to_js_array[JsF64]/from_js_array[JsF64]
fn generic_double_array_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var ba = CbArgs.get_bindings_and_one(env, info)
        var items = from_js_array[JsF64](ba.b, env, ba.arg0)
        var doubled = List[JsF64]()
        for i in range(len(items)):
            doubled.append(JsF64(items[i].val * 2.0))
        return to_js_array(ba.b, env, doubled)
    except:
        throw_js_type_error(env, "genericDoubleArray: expected array of numbers")
        return NapiValue()

## genericReverseStrings — reverses a string array using parametric helpers
fn generic_reverse_strings_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var ba = CbArgs.get_bindings_and_one(env, info)
        var items = from_js_array[JsStr](ba.b, env, ba.arg0)
        var n = len(items)
        var rev = List[JsStr]()
        for i in range(n):
            rev.append(items[n - 1 - i].copy())
        return to_js_array(ba.b, env, rev)
    except:
        throw_js_type_error(env, "genericReverseStrings: expected array of strings")
        return NapiValue()

## objectFromArrays — builds a JS object from parallel key/value arrays
fn object_from_arrays_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var ba = CbArgs.get_bindings_and_two(env, info)
        var keys = from_js_array_str(ba.b, env, ba.arg0)
        var values = from_js_array_f64(ba.b, env, ba.arg1)
        if len(keys) != len(values):
            throw_js_type_error(ba.b, env, "objectFromArrays: keys and values must have equal length")
            return NapiValue()
        var obj = JsObject.create(ba.b, env)
        for i in range(len(keys)):
            var key_js = JsString.create(ba.b, env, keys[i]).value
            obj.set(ba.b, env, key_js, JsNumber.create(ba.b, env, values[i]).value)
        return obj.value
    except:
        throw_js_type_error(env, "objectFromArrays: expected (string[], number[])")
        return NapiValue()

## objectToArrays — extracts {keys, values} from a plain JS object
fn object_to_arrays_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var ba = CbArgs.get_bindings_and_one(env, info)
        var key_arr_val = JsObject(ba.arg0).keys(ba.b, env)
        var key_arr = JsArray(key_arr_val)
        var n = Int(key_arr.length(ba.b, env))
        var keys = List[String]()
        var values = List[Float64]()
        for i in range(n):
            var key_val = key_arr.get(ba.b, env, UInt32(i))
            var k = JsString.from_napi_value(ba.b, env, key_val)
            var v = JsNumber.from_napi_value(ba.b, env, JsObject(ba.arg0).get(ba.b, env, key_val))
            keys.append(k)
            values.append(v)
        var result = JsObject.create(ba.b, env)
        result.set_property(ba.b, env, "keys", to_js_array_str(ba.b, env, keys))
        result.set_property(ba.b, env, "values", to_js_array_f64(ba.b, env, values))
        return result.value
    except:
        throw_js_type_error(env, "objectToArrays: expected a plain object")
        return NapiValue()

fn register_convert(mut m: ModuleBuilder) raises:
    var sum_js_array_ref = sum_js_array_fn
    var double_array_ref = double_array_fn
    var join_strings_ref = join_strings_fn
    var reverse_strings_ref = reverse_strings_fn
    var generic_double_array_ref = generic_double_array_fn
    var generic_reverse_strings_ref = generic_reverse_strings_fn
    var object_from_arrays_ref = object_from_arrays_fn
    var object_to_arrays_ref = object_to_arrays_fn
    m.method("sumJsArray", fn_ptr(sum_js_array_ref))
    m.method("doubleArray", fn_ptr(double_array_ref))
    m.method("joinStrings", fn_ptr(join_strings_ref))
    m.method("reverseStrings", fn_ptr(reverse_strings_ref))
    m.method("genericDoubleArray", fn_ptr(generic_double_array_ref))
    m.method("genericReverseStrings", fn_ptr(generic_reverse_strings_ref))
    m.method("objectFromArrays", fn_ptr(object_from_arrays_ref))
    m.method("objectToArrays", fn_ptr(object_to_arrays_ref))
