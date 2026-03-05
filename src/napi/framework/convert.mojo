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
from napi.framework.js_number import JsNumber
from napi.framework.js_string import JsString
from napi.framework.js_boolean import JsBoolean
from napi.framework.js_int32 import JsInt32
from napi.framework.js_value import js_typeof, js_type_name
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
