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
from napi.bindings import Bindings
from napi.raw import (
    raw_typeof, raw_is_array, raw_get_global, raw_strict_equals,
    raw_is_error, raw_adjust_external_memory, raw_run_script,
)
from napi.error import check_status
from napi.framework.js_object import JsObject

## js_typeof — return the napi_valuetype of a JavaScript value (env-only)
##
## env-only: for async complete, TSFN, finalizer, and except-block callbacks
## where NapiBindings is unavailable. Use js_typeof(b, env, val) in hot paths.
##
## Calls napi_typeof and returns the result as a NapiValueType (Int32).
## Compare the result against the NAPI_TYPE_* constants from napi.types.
## Raises on N-API failure.
def js_typeof(env: NapiEnv, val: NapiValue) raises -> NapiValueType:
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
def js_type_name(t: NapiValueType) -> String:
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
def js_is_array(env: NapiEnv, val: NapiValue) raises -> Bool:
    var result: Bool = False
    var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
    check_status(raw_is_array(env, val, result_ptr))
    return result

## js_strict_equals — check strict equality (===) between any two JS values
##
## Works on all value types (primitives, objects, etc.).
def js_strict_equals(env: NapiEnv, lhs: NapiValue, rhs: NapiValue) raises -> Bool:
    var result: Bool = False
    var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
    check_status(raw_strict_equals(env, lhs, rhs, result_ptr))
    return result

## js_get_global — return the global object (globalThis)
def js_get_global(env: NapiEnv) raises -> JsObject:
    var result = NapiValue()
    check_status(raw_get_global(env,
        UnsafePointer(to=result).bitcast[NoneType]()))
    return JsObject(result)

# --- Bindings-aware overloads ---

def js_typeof(b: Bindings, env: NapiEnv, val: NapiValue) raises -> NapiValueType:
    var t: NapiValueType = 0
    var t_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=t).bitcast[NoneType]()
    check_status(raw_typeof(b, env, val, t_ptr))
    return t

def js_is_array(b: Bindings, env: NapiEnv, val: NapiValue) raises -> Bool:
    var result: Bool = False
    var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
    check_status(raw_is_array(b, env, val, result_ptr))
    return result

def js_strict_equals(b: Bindings, env: NapiEnv, lhs: NapiValue, rhs: NapiValue) raises -> Bool:
    var result: Bool = False
    var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
    check_status(raw_strict_equals(b, env, lhs, rhs, result_ptr))
    return result

def js_get_global(b: Bindings, env: NapiEnv) raises -> JsObject:
    var result = NapiValue()
    check_status(raw_get_global(b, env,
        UnsafePointer(to=result).bitcast[NoneType]()))
    return JsObject(result)

## js_is_error — check whether a JavaScript value is an Error object
def js_is_error(env: NapiEnv, val: NapiValue) raises -> Bool:
    var result: Bool = False
    var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
    check_status(raw_is_error(env, val, result_ptr))
    return result

def js_is_error(b: Bindings, env: NapiEnv, val: NapiValue) raises -> Bool:
    var result: Bool = False
    var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
    check_status(raw_is_error(b, env, val, result_ptr))
    return result

## js_adjust_external_memory — inform V8 about native memory allocations
##
## Returns the adjusted external memory value.
def js_adjust_external_memory(env: NapiEnv, change_in_bytes: Int64) raises -> Int64:
    var result: Int64 = 0
    var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
    check_status(raw_adjust_external_memory(env, change_in_bytes, result_ptr))
    return result

def js_adjust_external_memory(b: Bindings, env: NapiEnv, change_in_bytes: Int64) raises -> Int64:
    var result: Int64 = 0
    var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
    check_status(raw_adjust_external_memory(b, env, change_in_bytes, result_ptr))
    return result

## js_run_script — evaluate a JavaScript string (like eval())
##
## Takes a napi_value containing the script string, returns the result.
def js_run_script(env: NapiEnv, script: NapiValue) raises -> NapiValue:
    var result = NapiValue()
    check_status(raw_run_script(env, script,
        UnsafePointer(to=result).bitcast[NoneType]()))
    return result

def js_run_script(b: Bindings, env: NapiEnv, script: NapiValue) raises -> NapiValue:
    var result = NapiValue()
    check_status(raw_run_script(b, env, script,
        UnsafePointer(to=result).bitcast[NoneType]()))
    return result
