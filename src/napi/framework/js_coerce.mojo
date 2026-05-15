## src/napi/framework/js_coerce.mojo — JavaScript type coercion wrappers
##
## Wraps the napi_coerce_to_* family of functions. These implement
## JavaScript's abstract coercion operations:
##   Boolean(value), Number(value), String(value), Object(value)
##
## Note: napi_coerce_to_string and napi_coerce_to_number throw a pending
## TypeError when given a Symbol value (matching JS behavior).

from napi.types import NapiEnv, NapiValue
from napi.bindings import Bindings
from napi.raw import (
    raw_coerce_to_bool,
    raw_coerce_to_number,
    raw_coerce_to_string,
    raw_coerce_to_object,
)
from napi.error import check_status

## env-only overloads below: for async complete, TSFN, finalizer, and
## except-block callbacks where NapiBindings is unavailable.
## Use the bindings overloads (b, env, val) in hot paths.


def js_coerce_to_bool(env: NapiEnv, val: NapiValue) raises -> NapiValue:
    """Equivalent to Boolean(value) in JavaScript."""
    var result = NapiValue(unsafe_from_address=0)
    check_status(
        raw_coerce_to_bool(
            env, val, UnsafePointer(to=result).bitcast[NoneType]()
        )
    )
    return result


def js_coerce_to_number(env: NapiEnv, val: NapiValue) raises -> NapiValue:
    """Equivalent to Number(value) in JavaScript.
    Throws TypeError on Symbol values."""
    var result = NapiValue(unsafe_from_address=0)
    check_status(
        raw_coerce_to_number(
            env, val, UnsafePointer(to=result).bitcast[NoneType]()
        )
    )
    return result


def js_coerce_to_string(env: NapiEnv, val: NapiValue) raises -> NapiValue:
    """Equivalent to String(value) in JavaScript.
    Throws TypeError on Symbol values."""
    var result = NapiValue(unsafe_from_address=0)
    check_status(
        raw_coerce_to_string(
            env, val, UnsafePointer(to=result).bitcast[NoneType]()
        )
    )
    return result


def js_coerce_to_object(env: NapiEnv, val: NapiValue) raises -> NapiValue:
    """Equivalent to Object(value) in JavaScript.
    Wraps primitives in their object wrappers."""
    var result = NapiValue(unsafe_from_address=0)
    check_status(
        raw_coerce_to_object(
            env, val, UnsafePointer(to=result).bitcast[NoneType]()
        )
    )
    return result


# --- Bindings-aware overloads ---


def js_coerce_to_bool(
    b: Bindings, env: NapiEnv, val: NapiValue
) raises -> NapiValue:
    """Equivalent to Boolean(value) in JavaScript."""
    var result = NapiValue(unsafe_from_address=0)
    check_status(
        raw_coerce_to_bool(
            b, env, val, UnsafePointer(to=result).bitcast[NoneType]()
        )
    )
    return result


def js_coerce_to_number(
    b: Bindings, env: NapiEnv, val: NapiValue
) raises -> NapiValue:
    """Equivalent to Number(value) in JavaScript.
    Throws TypeError on Symbol values."""
    var result = NapiValue(unsafe_from_address=0)
    check_status(
        raw_coerce_to_number(
            b, env, val, UnsafePointer(to=result).bitcast[NoneType]()
        )
    )
    return result


def js_coerce_to_string(
    b: Bindings, env: NapiEnv, val: NapiValue
) raises -> NapiValue:
    """Equivalent to String(value) in JavaScript.
    Throws TypeError on Symbol values."""
    var result = NapiValue(unsafe_from_address=0)
    check_status(
        raw_coerce_to_string(
            b, env, val, UnsafePointer(to=result).bitcast[NoneType]()
        )
    )
    return result


def js_coerce_to_object(
    b: Bindings, env: NapiEnv, val: NapiValue
) raises -> NapiValue:
    """Equivalent to Object(value) in JavaScript.
    Wraps primitives in their object wrappers."""
    var result = NapiValue(unsafe_from_address=0)
    check_status(
        raw_coerce_to_object(
            b, env, val, UnsafePointer(to=result).bitcast[NoneType]()
        )
    )
    return result
