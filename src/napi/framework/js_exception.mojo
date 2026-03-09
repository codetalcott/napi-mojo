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
##   return NapiValue()
##
##   # Check + catch a pending exception:
##   if js_is_exception_pending(env):
##       var caught = js_get_and_clear_last_exception(env)
##       # ... inspect or return `caught`

from napi.types import NapiEnv, NapiValue
from napi.bindings import Bindings
from napi.raw import raw_throw, raw_is_exception_pending, raw_get_and_clear_last_exception
from napi.error import check_status
from napi.framework.js_object import JsObject
from napi.framework.js_string import JsString

## js_throw — throw any JavaScript value as an exception
##
## Unlike throw_js_error (which creates a new Error from a string message),
## this throws the value directly. Can throw strings, numbers, objects,
## Error instances, null, undefined, etc.
## The callback MUST return NapiValue() immediately after calling this.
fn js_throw(env: NapiEnv, error: NapiValue) raises:
    check_status(raw_throw(env, error))

## js_is_exception_pending — check if a JavaScript exception is pending
##
## Returns True if an exception is currently pending (set by napi_throw,
## napi_throw_error, or a failed N-API call that sets a pending exception).
fn js_is_exception_pending(env: NapiEnv) raises -> Bool:
    var result: Bool = False
    var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
    check_status(raw_is_exception_pending(env, result_ptr))
    return result

## js_get_and_clear_last_exception — retrieve and clear the pending exception
##
## Returns the pending exception value and clears the pending state,
## allowing the callback to continue executing N-API calls normally.
## Must only be called when an exception IS pending.
fn js_get_and_clear_last_exception(env: NapiEnv) raises -> NapiValue:
    var result = NapiValue()
    var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
    check_status(raw_get_and_clear_last_exception(env, result_ptr))
    return result

# --- Bindings-aware overloads ---

fn js_throw(b: Bindings, env: NapiEnv, error: NapiValue) raises:
    check_status(raw_throw(b, env, error))

fn js_is_exception_pending(b: Bindings, env: NapiEnv) raises -> Bool:
    var result: Bool = False
    var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
    check_status(raw_is_exception_pending(b, env, result_ptr))
    return result

fn js_get_and_clear_last_exception(b: Bindings, env: NapiEnv) raises -> NapiValue:
    var result = NapiValue()
    var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
    check_status(raw_get_and_clear_last_exception(b, env, result_ptr))
    return result

## js_get_error_message — read the .message property from a JS Error object
##
## Returns the error message as a Mojo String. Works on any JS object
## with a "message" property. Typically called after
## js_get_and_clear_last_exception() to inspect a caught exception.
fn js_get_error_message(env: NapiEnv, err: NapiValue) raises -> String:
    return JsString.from_napi_value(env, JsObject(err).get_property(env, "message"))

## js_get_error_stack — read the .stack property from a JS Error object
##
## Returns the stack trace as a Mojo String.
fn js_get_error_stack(env: NapiEnv, err: NapiValue) raises -> String:
    return JsString.from_napi_value(env, JsObject(err).get_property(env, "stack"))

fn js_get_error_message(b: Bindings, env: NapiEnv, err: NapiValue) raises -> String:
    return JsString.from_napi_value(b, env, JsObject(err).get_property(b, env, "message"))

fn js_get_error_stack(b: Bindings, env: NapiEnv, err: NapiValue) raises -> String:
    return JsString.from_napi_value(b, env, JsObject(err).get_property(b, env, "stack"))
