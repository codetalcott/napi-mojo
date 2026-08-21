"""Generic `napi_value` inspection utilities.

Type-checking helpers that inspect a value *without* attempting to read it,
which is what lets a callback validate its arguments and produce a
descriptive error instead of a conversion failure:

```mojo
var t = js_typeof(b, env, val)
if t != NAPI_TYPE_STRING:
    throw_js_error_dynamic(env, "expected string, got " + js_type_name(t))
    return NapiValue(unsafe_from_address=Int(0))
var s = JsString.from_napi_value(b, env, val)
```

Note that `napi_typeof` reports `object` for arrays, for `null`, and for
plain objects alike — mirroring JavaScript's own `typeof`. Use
`js_is_array` to separate arrays from objects, and compare against
`NAPI_TYPE_NULL` to separate `null`, which `napi_typeof` does distinguish
even though `js_type_name` renders it as `object` to match `typeof`.
"""


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


def js_type_name(t: NapiValueType) -> String:
    """Human-readable name for a napi_valuetype code.

    Returns the name as JavaScript's own `typeof` would render it, which
    means `NAPI_TYPE_NULL` comes back as `"object"`. Intended for error
    messages.

    Returns String rather than StringLiteral because StringLiteral is
    parameterized on its compile-time value and cannot be returned from a
    function that branches at runtime.

    Args:
        t: The napi_valuetype code, typically from `js_typeof`.

    Returns:
        The type name, or "unknown" for an unrecognized code.
    """
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
    """Report the JavaScript type of a value, like `typeof`.

    Returns `NAPI_TYPE_OBJECT` for arrays and plain objects alike; use
    `js_is_array` to tell them apart.

    Args:
        b: Cached N-API bindings.
        env: The N-API environment.
        val: The value to inspect.

    Returns:
        One of the NAPI_TYPE_* constants in `napi.types`.

    Raises:
        If napi_typeof does not return napi_ok.
    """
    var t: NapiValueType = 0
    var t_ptr: OpaquePointer[MutAnyOrigin] = Pointer(to=t).unsafe_bitcast[
        NoneType
    ]().as_unsafe_any_origin()
    check_status(raw_typeof(b, env, val, t_ptr))
    return t


def js_is_array(b: Bindings, env: NapiEnv, val: NapiValue) raises -> Bool:
    """Report whether a value is a JavaScript Array.

    `js_typeof` cannot answer this — it returns `object` for arrays. This
    wraps `napi_is_array`, which is the `Array.isArray` semantics.

    Args:
        b: Cached N-API bindings.
        env: The N-API environment.
        val: The value to inspect.

    Returns:
        True if val is an Array.

    Raises:
        If napi_is_array does not return napi_ok.
    """
    var result: Bool = False
    var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
        to=result
    ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
    check_status(raw_is_array(b, env, val, result_ptr))
    return result


def js_strict_equals(
    b: Bindings, env: NapiEnv, lhs: NapiValue, rhs: NapiValue
) raises -> Bool:
    """Compare two values with JavaScript's `===`.

    No type coercion, and `NaN === NaN` is False, matching the language.

    Args:
        b: Cached N-API bindings.
        env: The N-API environment.
        lhs: Left operand.
        rhs: Right operand.

    Returns:
        True if the values are strictly equal.

    Raises:
        If napi_strict_equals does not return napi_ok.
    """
    var result: Bool = False
    var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
        to=result
    ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
    check_status(raw_strict_equals(b, env, lhs, rhs, result_ptr))
    return result


def js_get_global(b: Bindings, env: NapiEnv) raises -> JsObject:
    """Return the environment's `globalThis` object.

    The entry point for reaching built-ins that N-API exposes no direct call
    for — `JSON`, `Math`, `console` — by reading them off the global.

    Args:
        b: Cached N-API bindings.
        env: The N-API environment.

    Returns:
        A JsObject wrapping globalThis.

    Raises:
        If napi_get_global does not return napi_ok.
    """
    var result = NapiValue(unsafe_from_address=Int(0))
    check_status(
        raw_get_global(b, env, Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin())
    )
    return JsObject(result)


def js_is_error(b: Bindings, env: NapiEnv, val: NapiValue) raises -> Bool:
    """Report whether a value is a JavaScript Error object.

    Args:
        b: Cached N-API bindings.
        env: The N-API environment.
        val: The value to inspect.

    Returns:
        True if val is an Error.

    Raises:
        If napi_is_error does not return napi_ok.
    """
    var result: Bool = False
    var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
        to=result
    ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
    check_status(raw_is_error(b, env, val, result_ptr))
    return result


def js_adjust_external_memory(
    b: Bindings, env: NapiEnv, change_in_bytes: Int64
) raises -> Int64:
    """Tell the GC about memory held outside the JS heap.

    Report Mojo-owned memory that a JS object keeps alive, so V8 can factor
    it into when to collect. Pass a positive delta when you allocate and a
    negative one when you free; the two must balance over an object's life,
    or you skew the GC's picture in one direction permanently.

    Args:
        b: Cached N-API bindings.
        env: The N-API environment.
        change_in_bytes: Signed delta to apply.

    Returns:
        The adjusted total of externally-allocated memory.

    Raises:
        If napi_adjust_external_memory does not return napi_ok.
    """
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
    """Compile and run a JavaScript source string.

    Args:
        b: Cached N-API bindings.
        env: The N-API environment.
        script: A napi_value holding the source text as a JS string.

    Returns:
        The completion value of the script.

    Raises:
        If the script throws, or napi_run_script does not return napi_ok.
    """
    var result = NapiValue(unsafe_from_address=Int(0))
    check_status(
        raw_run_script(
            b, env, script, Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        )
    )
    return result
