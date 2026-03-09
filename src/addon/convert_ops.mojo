## src/addon/convert_ops.mojo — collection helper callbacks (E6)
##
## Demonstrates to_js_array_f64/from_js_array_f64/to_js_array_str/from_js_array_str

from napi.types import NapiEnv, NapiValue
from napi.bindings import Bindings
from napi.error import throw_js_error, throw_js_type_error
from napi.framework.js_number import JsNumber
from napi.framework.js_string import JsString
from napi.framework.args import CbArgs
from napi.framework.register import fn_ptr, ModuleBuilder
from napi.framework.convert import to_js_array_f64, from_js_array_f64, to_js_array_str, from_js_array_str

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

fn register_convert(mut m: ModuleBuilder) raises:
    var sum_js_array_ref = sum_js_array_fn
    var double_array_ref = double_array_fn
    var join_strings_ref = join_strings_fn
    var reverse_strings_ref = reverse_strings_fn
    m.method("sumJsArray", fn_ptr(sum_js_array_ref))
    m.method("doubleArray", fn_ptr(double_array_ref))
    m.method("joinStrings", fn_ptr(join_strings_ref))
    m.method("reverseStrings", fn_ptr(reverse_strings_ref))
