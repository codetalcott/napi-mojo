## src/napi/framework/convert.mojo — type conversion traits for JS ↔ Mojo marshaling
##
## Defines ToJsValue and FromJsValue traits that standardize how Mojo values
## are converted to/from JavaScript NapiValues. Each wrapper type includes
## type validation in from_js(), throwing a TypeError on mismatch.
##
## Usage:
##   # Convert Mojo → JS:
##   var result = JsF64(42.0).to_js(env)
##
##   # Convert JS → Mojo (with type validation):
##   var n = JsF64.from_js(env, napi_val)
##   print(n.val)  # 42.0

from napi.types import NapiEnv, NapiValue, NapiValueType, NAPI_TYPE_NUMBER, NAPI_TYPE_STRING, NAPI_TYPE_BOOLEAN
from napi.bindings import Bindings
from napi.framework.js_number import JsNumber
from napi.framework.js_string import JsString
from napi.framework.js_boolean import JsBoolean
from napi.framework.js_int32 import JsInt32
from napi.framework.js_array import JsArray
from napi.framework.js_value import js_typeof, js_type_name, js_is_array
from napi.error import throw_js_type_error_dynamic


## ToJsValue — convert a Mojo value to a JavaScript NapiValue
trait ToJsValue:
    fn to_js(self, env: NapiEnv) raises -> NapiValue


## FromJsValue — extract a Mojo value from a JavaScript NapiValue
##
## Implementations should validate the JS type and throw a TypeError
## if the value is not the expected type.
trait FromJsValue:
    @staticmethod
    fn from_js(env: NapiEnv, val: NapiValue) raises -> Self


## _check_type — validate that a NapiValue has the expected type, throw TypeError if not
fn _check_type(env: NapiEnv, val: NapiValue, expected: NapiValueType, expected_name: StringLiteral) raises:
    var actual = js_typeof(env, val)
    if actual != expected:
        throw_js_type_error_dynamic(env, "expected " + expected_name + ", got " + js_type_name(actual))
        raise Error("type mismatch")


## JsF64 — Float64 ↔ JS number
@value
struct JsF64(ToJsValue, FromJsValue):
    var val: Float64

    fn to_js(self, env: NapiEnv) raises -> NapiValue:
        return JsNumber.create(env, self.val).value

    @staticmethod
    fn from_js(env: NapiEnv, val: NapiValue) raises -> Self:
        _check_type(env, val, NAPI_TYPE_NUMBER, "number")
        return Self(JsNumber.from_napi_value(env, val))


## JsI32 — Int32 ↔ JS number (int32)
@value
struct JsI32(ToJsValue, FromJsValue):
    var val: Int32

    fn to_js(self, env: NapiEnv) raises -> NapiValue:
        return JsInt32.create(env, self.val).value

    @staticmethod
    fn from_js(env: NapiEnv, val: NapiValue) raises -> Self:
        _check_type(env, val, NAPI_TYPE_NUMBER, "number")
        return Self(JsInt32.from_napi_value(env, val))


## JsBool — Bool ↔ JS boolean
@value
struct JsBool(ToJsValue, FromJsValue):
    var val: Bool

    fn to_js(self, env: NapiEnv) raises -> NapiValue:
        return JsBoolean.create(env, self.val).value

    @staticmethod
    fn from_js(env: NapiEnv, val: NapiValue) raises -> Self:
        _check_type(env, val, NAPI_TYPE_BOOLEAN, "boolean")
        return Self(JsBoolean.from_napi_value(env, val))


## JsStr — String ↔ JS string
@value
struct JsStr(ToJsValue, FromJsValue):
    var val: String

    fn to_js(self, env: NapiEnv) raises -> NapiValue:
        return JsString.create(env, self.val).value

    @staticmethod
    fn from_js(env: NapiEnv, val: NapiValue) raises -> Self:
        _check_type(env, val, NAPI_TYPE_STRING, "string")
        return Self(JsString.from_napi_value(env, val))


## JsRaw — NapiValue pass-through (no type checking)
@value
struct JsRaw(ToJsValue, FromJsValue):
    var val: NapiValue

    fn to_js(self, env: NapiEnv) raises -> NapiValue:
        return self.val

    @staticmethod
    fn from_js(env: NapiEnv, val: NapiValue) raises -> Self:
        return Self(val)


# ---------------------------------------------------------------------------
# Collection helpers (E6): JS Array ↔ Mojo List conversions
#
# Concrete typed free functions for the most common element types.
# Uses cached Bindings for all N-API calls (array create/get/set).
# ---------------------------------------------------------------------------

## to_js_array_f64 — convert List[Float64] to a JavaScript Array<number>
fn to_js_array_f64(b: Bindings, env: NapiEnv, items: List[Float64]) raises -> NapiValue:
    var arr = JsArray.create_with_length(b, env, UInt(len(items)))
    for i in range(len(items)):
        arr.set(b, env, UInt32(i), JsNumber.create(b, env, items[i]).value)
    return arr.value

## from_js_array_f64 — convert a JavaScript Array<number> to List[Float64]
##
## Raises TypeError if val is not an array. Each element is read as Float64
## via napi_get_value_double. Non-number elements produce 0 (N-API behavior).
fn from_js_array_f64(b: Bindings, env: NapiEnv, val: NapiValue) raises -> List[Float64]:
    if not js_is_array(b, env, val):
        throw_js_type_error_dynamic(env, "from_js_array_f64: expected array")
        raise Error("type mismatch")
    var arr = JsArray(val)
    var n = Int(arr.length(b, env))
    var result = List[Float64]()
    for i in range(n):
        result.append(JsNumber.from_napi_value(b, env, arr.get(b, env, UInt32(i))))
    return result^

## to_js_array_str — convert List[String] to a JavaScript Array<string>
fn to_js_array_str(b: Bindings, env: NapiEnv, items: List[String]) raises -> NapiValue:
    var arr = JsArray.create_with_length(b, env, UInt(len(items)))
    for i in range(len(items)):
        arr.set(b, env, UInt32(i), JsString.create(b, env, items[i]).value)
    return arr.value

## from_js_array_str — convert a JavaScript Array<string> to List[String]
##
## Raises TypeError if val is not an array. Non-string elements become
## empty strings (N-API behavior when napi_get_value_string_utf8 fails).
fn from_js_array_str(b: Bindings, env: NapiEnv, val: NapiValue) raises -> List[String]:
    if not js_is_array(b, env, val):
        throw_js_type_error_dynamic(env, "from_js_array_str: expected array")
        raise Error("type mismatch")
    var arr = JsArray(val)
    var n = Int(arr.length(b, env))
    var result = List[String]()
    for i in range(n):
        result.append(JsString.from_napi_value(b, env, arr.get(b, env, UInt32(i))))
    return result^
