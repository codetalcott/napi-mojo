## src/napi/framework/js_exception.mojo — exception introspection and re-throwing
##
## Provides programmatic exception handling beyond the throw_js_error family
## (which creates-and-throws in one step). These functions enable:
##   - Re-throwing any JavaScript value as an exception
##   - Checking if an exception is currently pending
##   - Catching (clearing) a pending exception for native handling
##
## Usage:
##   # Re-throw an arbitrary JS value:
##   js_throw(env, some_value)
##   return NapiValue(unsafe_from_address=Int(0))
##
##   # Check + catch a pending exception:
##   if js_is_exception_pending(env):
##       var caught = js_get_and_clear_last_exception(env)
##       # ... inspect or return `caught`

from napi.types import NapiEnv, NapiValue
from napi.bindings import Bindings
from napi.raw import (
    raw_throw,
    raw_is_exception_pending,
    raw_get_and_clear_last_exception,
)
from napi.error import check_status
from napi.framework.js_object import JsObject
from napi.framework.js_string import JsString


# --- Bindings-aware overloads ---


def js_throw(b: Bindings, env: NapiEnv, error: NapiValue) raises:
    check_status(raw_throw(b, env, error))


def js_is_exception_pending(b: Bindings, env: NapiEnv) raises -> Bool:
    var result: Bool = False
    var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
        to=result
    ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
    check_status(raw_is_exception_pending(b, env, result_ptr))
    return result


def js_get_and_clear_last_exception(
    b: Bindings, env: NapiEnv
) raises -> NapiValue:
    var result = NapiValue(unsafe_from_address=Int(0))
    var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
        to=result
    ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
    check_status(raw_get_and_clear_last_exception(b, env, result_ptr))
    return result


def js_get_error_message(
    b: Bindings, env: NapiEnv, err: NapiValue
) raises -> String:
    return JsString.from_napi_value(
        b, env, JsObject(err).get_property(b, env, "message")
    )


def js_get_error_stack(
    b: Bindings, env: NapiEnv, err: NapiValue
) raises -> String:
    return JsString.from_napi_value(
        b, env, JsObject(err).get_property(b, env, "stack")
    )
