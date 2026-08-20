## src/napi/framework/convert.mojo — type conversion traits for JS ↔ Mojo marshaling
##
## Defines ToJsValue and FromJsValue traits that standardize how Mojo values
## are converted to/from JavaScript NapiValues. Each wrapper type includes
## type validation in from_js(), throwing a TypeError on mismatch.
##
## Usage:
##   # Convert Mojo → JS:
##   var result = JsF64(42.0).to_js(b, env)
##
##   # Convert JS → Mojo (with type validation):
##   var n = JsF64.from_js(b, env, napi_val)
##   print(n.val)  # 42.0
##
##   # Parametric array conversion (works with any ToJsValue/FromJsValue type):
##   var arr = to_js_array(b, env, List[JsF64](...))
##   var items = from_js_array[JsStr](b, env, napi_val)
##
## Object helpers (to_js_object_str_f64 etc.) live in addon/convert_ops.mojo

from napi.types import (
    NapiEnv,
    NapiValue,
    NapiValueType,
    NAPI_TYPE_NUMBER,
    NAPI_TYPE_STRING,
    NAPI_TYPE_BOOLEAN,
)
from napi.bindings import Bindings
from napi.framework.js_number import JsNumber
from napi.framework.js_string import JsString
from napi.framework.js_boolean import JsBoolean
from napi.framework.js_int32 import JsInt32
from napi.framework.js_array import JsArray
from napi.framework.js_value import js_typeof, js_type_name, js_is_array
from napi.error import throw_js_type_error_dynamic


## ToJsValue — convert a Mojo value to a JavaScript NapiValue
##
## The trait method is Bindings-first, so generic code (to_js_array[T]) runs
## on cached function pointers — the env-only trait method that used to live
## here forced one dlopen(NULL)+dlsym PER ELEMENT in the parametric helpers.
trait ToJsValue:
    def to_js(self, b: Bindings, env: NapiEnv) raises -> NapiValue:
        ...


## FromJsValue — extract a Mojo value from a JavaScript NapiValue
##
## Implementations should validate the JS type and throw a TypeError
## if the value is not the expected type. Bindings-first for the same
## reason as ToJsValue.
trait FromJsValue:
    @staticmethod
    def from_js(b: Bindings, env: NapiEnv, val: NapiValue) raises -> Self:
        ...


## _check_type — validate that a NapiValue has the expected type, throw TypeError if not
##
## Error-signalling convention (applies to every validation helper here): on
## mismatch we BOTH set a pending JS TypeError (so JS sees a typed error with
## a real message) AND raise a Mojo error (so Mojo execution unwinds to the
## callback's except block, which returns null). Callers that catch the Mojo
## error must NOT make further N-API calls other than returning — the pending
## exception makes any subsequent call report napi_pending_exception.
def _check_type(
    b: Bindings,
    env: NapiEnv,
    val: NapiValue,
    expected: NapiValueType,
    expected_name: StringLiteral,
) raises:
    var actual = js_typeof(b, env, val)
    if actual != expected:
        throw_js_type_error_dynamic(
            b,
            env,
            "expected " + expected_name + ", got " + js_type_name(actual),
        )
        raise Error("type mismatch")


## JsF64 — Float64 ↔ JS number
struct JsF64(Copyable, FromJsValue, ToJsValue):
    var val: Float64

    def __init__(out self, val: Float64):
        self.val = val

    def __init__(out self, *, copy: Self):
        self.val = copy.val

    def __init__(out self, *, deinit move: Self):
        self.val = move.val

    def to_js(self, b: Bindings, env: NapiEnv) raises -> NapiValue:
        return JsNumber.create(b, env, self.val).value

    @staticmethod
    def from_js(b: Bindings, env: NapiEnv, val: NapiValue) raises -> Self:
        _check_type(b, env, val, NAPI_TYPE_NUMBER, "number")
        var n: Float64 = JsNumber.from_napi_value(b, env, val)
        return JsF64(n)


## JsI32 — Int32 ↔ JS number (int32)
struct JsI32(FromJsValue, ToJsValue):
    var val: Int32

    def __init__(out self, val: Int32):
        self.val = val

    def to_js(self, b: Bindings, env: NapiEnv) raises -> NapiValue:
        return JsInt32.create(b, env, self.val).value

    @staticmethod
    def from_js(b: Bindings, env: NapiEnv, val: NapiValue) raises -> Self:
        _check_type(b, env, val, NAPI_TYPE_NUMBER, "number")
        return JsI32(JsInt32.from_napi_value(b, env, val))


## JsBool — Bool ↔ JS boolean
struct JsBool(FromJsValue, ToJsValue):
    var val: Bool

    def __init__(out self, val: Bool):
        self.val = val

    def to_js(self, b: Bindings, env: NapiEnv) raises -> NapiValue:
        return JsBoolean.create(b, env, self.val).value

    @staticmethod
    def from_js(b: Bindings, env: NapiEnv, val: NapiValue) raises -> Self:
        _check_type(b, env, val, NAPI_TYPE_BOOLEAN, "boolean")
        return JsBool(JsBoolean.from_napi_value(b, env, val))


## JsStr — String ↔ JS string
struct JsStr(Copyable, FromJsValue, ToJsValue):
    var val: String

    def __init__(out self, val: String):
        self.val = val

    def __init__(out self, *, copy: Self):
        self.val = copy.val

    def __init__(out self, *, deinit move: Self):
        self.val = move.val^

    def to_js(self, b: Bindings, env: NapiEnv) raises -> NapiValue:
        return JsString.create(b, env, self.val).value

    @staticmethod
    def from_js(b: Bindings, env: NapiEnv, val: NapiValue) raises -> Self:
        _check_type(b, env, val, NAPI_TYPE_STRING, "string")
        var s: String = JsString.from_napi_value(b, env, val)
        return JsStr(s)


## JsRaw — NapiValue pass-through (no type checking)
struct JsRaw(FromJsValue, ToJsValue):
    var val: NapiValue

    def __init__(out self, val: NapiValue):
        self.val = val

    def to_js(self, b: Bindings, env: NapiEnv) raises -> NapiValue:
        return self.val

    @staticmethod
    def from_js(b: Bindings, env: NapiEnv, val: NapiValue) raises -> Self:
        return JsRaw(val)


# ---------------------------------------------------------------------------
# Collection helpers (E6): JS Array ↔ Mojo List conversions
#
# Concrete typed free functions for the most common element types.
# Uses cached Bindings for all N-API calls (array create/get/set).
# ---------------------------------------------------------------------------


## to_js_array_f64 — convert List[Float64] to a JavaScript Array<number>
def to_js_array_f64(
    b: Bindings, env: NapiEnv, items: List[Float64]
) raises -> NapiValue:
    var arr = JsArray.create_with_length(b, env, UInt(len(items)))
    for i in range(len(items)):
        arr.set(b, env, UInt32(i), JsNumber.create(b, env, items[i]).value)
    return arr.value


## from_js_array_f64 — convert a JavaScript Array<number> to List[Float64]
##
## Raises TypeError if val is not an array. Each element is read as Float64
## via napi_get_value_double. Non-number elements produce 0 (N-API behavior).
def from_js_array_f64(
    b: Bindings, env: NapiEnv, val: NapiValue
) raises -> List[Float64]:
    if not js_is_array(b, env, val):
        throw_js_type_error_dynamic(
            b, env, "from_js_array_f64: expected array"
        )
        raise Error("type mismatch")
    var arr = JsArray(val)
    var n = Int(arr.length(b, env))
    var result = List[Float64]()
    for i in range(n):
        result.append(
            JsNumber.from_napi_value(b, env, arr.get(b, env, UInt32(i)))
        )
    return result^


## to_js_array_str — convert List[String] to a JavaScript Array<string>
def to_js_array_str(
    b: Bindings, env: NapiEnv, items: List[String]
) raises -> NapiValue:
    var arr = JsArray.create_with_length(b, env, UInt(len(items)))
    for i in range(len(items)):
        arr.set(b, env, UInt32(i), JsString.create(b, env, items[i]).value)
    return arr.value


## from_js_array_str — convert a JavaScript Array<string> to List[String]
##
## Raises TypeError if val is not an array. Non-string elements become
## empty strings (N-API behavior when napi_get_value_string_utf8 fails).
def from_js_array_str(
    b: Bindings, env: NapiEnv, val: NapiValue
) raises -> List[String]:
    if not js_is_array(b, env, val):
        throw_js_type_error_dynamic(
            b, env, "from_js_array_str: expected array"
        )
        raise Error("type mismatch")
    var arr = JsArray(val)
    var n = Int(arr.length(b, env))
    var result = List[String]()
    for i in range(n):
        result.append(
            JsString.from_napi_value(b, env, arr.get(b, env, UInt32(i)))
        )
    return result^


# ---------------------------------------------------------------------------
# Parametric helpers (Step 1): JS Array ↔ List[T] for any ToJsValue/FromJsValue T
#
# Element types must implement both trait overloads and be Copyable.
# Example: to_js_array(b, env, List[JsF64](...))
#          from_js_array[JsStr](b, env, napi_val)
# ---------------------------------------------------------------------------


## to_js_array — convert List[T] to a JavaScript Array using T.to_js(b, env)
##
## Fully on cached Bindings — the trait method is Bindings-first, so element
## conversion costs zero dlsym per element.
def to_js_array[
    T: ToJsValue & Copyable
](b: Bindings, env: NapiEnv, items: List[T]) raises -> NapiValue:
    var arr = JsArray.create_with_length(b, env, UInt(len(items)))
    for i in range(len(items)):
        arr.set(b, env, UInt32(i), items[i].to_js(b, env))
    return arr.value


## from_js_array — convert a JavaScript Array to List[T] using T.from_js(b, env, val)
##
## Raises TypeError if val is not an array. Fully on cached Bindings.
def from_js_array[
    T: FromJsValue & Copyable & Deinitable
](b: Bindings, env: NapiEnv, val: NapiValue) raises -> List[T]:
    if not js_is_array(b, env, val):
        throw_js_type_error_dynamic(b, env, "from_js_array: expected array")
        raise Error("type mismatch")
    var arr = JsArray(val)
    var n = Int(arr.length(b, env))
    var result = List[T]()
    for i in range(n):
        result.append(T.from_js(b, env, arr.get(b, env, UInt32(i))))
    return result^
