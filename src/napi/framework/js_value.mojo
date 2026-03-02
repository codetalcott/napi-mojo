## src/napi/framework/js_value.mojo — generic NapiValue inspection utilities
##
## Provides type-checking helpers that inspect a NapiValue without attempting
## to read it, enabling proper input validation and descriptive error messages.
##
## Usage:
##   var t = js_typeof(env, val)
##   if t != NAPI_TYPE_STRING:
##       throw_js_error(env, "expected a string argument")
##       return NapiValue()
##   var s = JsString.from_napi_value(env, val)
##
##   # Human-readable type name for error messages:
##   throw_js_error_dynamic(env, "expected string, got " + js_type_name(t))

from napi.types import (
    NapiEnv, NapiValue, NapiValueType,
    NAPI_TYPE_UNDEFINED, NAPI_TYPE_NULL, NAPI_TYPE_BOOLEAN,
    NAPI_TYPE_NUMBER, NAPI_TYPE_STRING, NAPI_TYPE_SYMBOL,
    NAPI_TYPE_OBJECT, NAPI_TYPE_FUNCTION, NAPI_TYPE_EXTERNAL,
    NAPI_TYPE_BIGINT,
)
from napi.raw import raw_typeof
from napi.error import check_status

## js_typeof — return the napi_valuetype of a JavaScript value
##
## Calls napi_typeof and returns the result as a NapiValueType (Int32).
## Compare the result against the NAPI_TYPE_* constants from napi.types.
## Raises on N-API failure.
fn js_typeof(env: NapiEnv, val: NapiValue) raises -> NapiValueType:
    var t: NapiValueType = 0
    var t_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=t).bitcast[NoneType]()
    check_status(raw_typeof(env, val, t_ptr))
    return t

## js_type_name — human-readable name for a napi_valuetype code
##
## Returns the JavaScript type name as it would appear in `typeof` expressions
## (e.g., "string", "number", "boolean"). Useful for building error messages.
## Returns String (not StringLiteral) because StringLiteral is parameterized on
## its compile-time value and cannot be returned from a runtime-branch function.
fn js_type_name(t: NapiValueType) -> String:
    if t == NAPI_TYPE_UNDEFINED: return "undefined"
    if t == NAPI_TYPE_NULL:      return "object"   # typeof null === "object" in JS
    if t == NAPI_TYPE_BOOLEAN:   return "boolean"
    if t == NAPI_TYPE_NUMBER:    return "number"
    if t == NAPI_TYPE_STRING:    return "string"
    if t == NAPI_TYPE_SYMBOL:    return "symbol"
    if t == NAPI_TYPE_OBJECT:    return "object"
    if t == NAPI_TYPE_FUNCTION:  return "function"
    if t == NAPI_TYPE_EXTERNAL:  return "external"
    if t == NAPI_TYPE_BIGINT:    return "bigint"
    return "unknown"
