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
from napi.raw import raw_typeof, raw_is_array, raw_get_global, raw_strict_equals
from napi.error import check_status
from napi.framework.js_object import JsObject

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

## js_is_array — check whether a JavaScript value is an Array
##
## napi_typeof returns NAPI_TYPE_OBJECT for arrays, so this function uses
## napi_is_array to distinguish arrays from plain objects.
fn js_is_array(env: NapiEnv, val: NapiValue) raises -> Bool:
    var result: Bool = False
    var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
    check_status(raw_is_array(env, val, result_ptr))
    return result

## js_strict_equals — check strict equality (===) between any two JS values
##
## Works on all value types (primitives, objects, etc.).
fn js_strict_equals(env: NapiEnv, lhs: NapiValue, rhs: NapiValue) raises -> Bool:
    var result: Bool = False
    var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
    check_status(raw_strict_equals(env, lhs, rhs, result_ptr))
    return result

## js_get_global — return the global object (globalThis)
fn js_get_global(env: NapiEnv) raises -> JsObject:
    var result = NapiValue()
    check_status(raw_get_global(env,
        UnsafePointer(to=result).bitcast[NoneType]()))
    return JsObject(result)
