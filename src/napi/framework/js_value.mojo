## src/napi/framework/js_value.mojo — generic NapiValue inspection utilities
##
## Provides type-checking helpers that inspect a NapiValue without attempting
## to read it, enabling proper input validation and descriptive error messages.
##
## Usage:
##   var t = js_typeof(env, val)
##   if t != NAPI_TYPE_STRING:
##       throw_js_error(env, "expected a string argument")
##       return NapiValue(unsafe_from_address=Int(0))
##   var s = JsString.from_napi_value(env, val)
##
##   # Human-readable type name for error messages:
##   throw_js_error_dynamic(env, "expected string, got " + js_type_name(t))

from napi.types import (
    NapiEnv,
    NapiValue,
    NapiValueType,
    NAPI_TYPE_UNDEFINED,
    NAPI_TYPE_NULL,
    NAPI_TYPE_BOOLEAN,
    NAPI_TYPE_NUMBER,
    NAPI_TYPE_STRING,
    NAPI_TYPE_SYMBOL,
    NAPI_TYPE_OBJECT,
    NAPI_TYPE_FUNCTION,
    NAPI_TYPE_EXTERNAL,
    NAPI_TYPE_BIGINT,
)
from napi.bindings import Bindings
from napi.raw import (
    raw_typeof,
    raw_is_array,
    raw_get_global,
    raw_strict_equals,
    raw_is_error,
    raw_adjust_external_memory,
    raw_run_script,
)
from napi.error import check_status
from napi.framework.js_object import JsObject


## js_type_name — human-readable name for a napi_valuetype code
##
## Returns the JavaScript type name as it would appear in `typeof` expressions
## (e.g., "string", "number", "boolean"). Useful for building error messages.
## Returns String (not StringLiteral) because StringLiteral is parameterized on
## its compile-time value and cannot be returned from a runtime-branch function.
def js_type_name(t: NapiValueType) -> String:
    if t == NAPI_TYPE_UNDEFINED:
        return "undefined"
    if t == NAPI_TYPE_NULL:
        return "object"  # typeof null === "object" in JS
    if t == NAPI_TYPE_BOOLEAN:
        return "boolean"
    if t == NAPI_TYPE_NUMBER:
        return "number"
    if t == NAPI_TYPE_STRING:
        return "string"
    if t == NAPI_TYPE_SYMBOL:
        return "symbol"
    if t == NAPI_TYPE_OBJECT:
        return "object"
    if t == NAPI_TYPE_FUNCTION:
        return "function"
    if t == NAPI_TYPE_EXTERNAL:
        return "external"
    if t == NAPI_TYPE_BIGINT:
        return "bigint"
    return "unknown"


# --- Bindings-aware overloads ---


def js_typeof(
    b: Bindings, env: NapiEnv, val: NapiValue
) raises -> NapiValueType:
    var t: NapiValueType = 0
    var t_ptr: OpaquePointer[MutAnyOrigin] = Pointer(to=t).unsafe_bitcast[
        NoneType
    ]().as_unsafe_any_origin()
    check_status(raw_typeof(b, env, val, t_ptr))
    return t


def js_is_array(b: Bindings, env: NapiEnv, val: NapiValue) raises -> Bool:
    var result: Bool = False
    var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
        to=result
    ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
    check_status(raw_is_array(b, env, val, result_ptr))
    return result


def js_strict_equals(
    b: Bindings, env: NapiEnv, lhs: NapiValue, rhs: NapiValue
) raises -> Bool:
    var result: Bool = False
    var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
        to=result
    ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
    check_status(raw_strict_equals(b, env, lhs, rhs, result_ptr))
    return result


def js_get_global(b: Bindings, env: NapiEnv) raises -> JsObject:
    var result = NapiValue(unsafe_from_address=Int(0))
    check_status(
        raw_get_global(b, env, Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin())
    )
    return JsObject(result)


def js_is_error(b: Bindings, env: NapiEnv, val: NapiValue) raises -> Bool:
    var result: Bool = False
    var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
        to=result
    ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
    check_status(raw_is_error(b, env, val, result_ptr))
    return result


def js_adjust_external_memory(
    b: Bindings, env: NapiEnv, change_in_bytes: Int64
) raises -> Int64:
    var result: Int64 = 0
    var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
        to=result
    ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
    check_status(
        raw_adjust_external_memory(b, env, change_in_bytes, result_ptr)
    )
    return result


def js_run_script(
    b: Bindings, env: NapiEnv, script: NapiValue
) raises -> NapiValue:
    var result = NapiValue(unsafe_from_address=Int(0))
    check_status(
        raw_run_script(
            b, env, script, Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        )
    )
    return result
