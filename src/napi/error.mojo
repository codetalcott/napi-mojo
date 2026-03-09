## src/napi/error.mojo — N-API error handling
##
## Provides `check_status()` which every N-API call must use after receiving
## its NapiStatus return value. Satisfies the CONTRIBUTING.md requirement:
## "Every N-API call returning napi_status must be immediately passed to
## check_status()."
##
## NapiError struct is defined for future use (e.g., typed error propagation
## in Phase 4+). Currently check_status() raises a built-in Error with a
## formatted message, which is compatible with Mojo v26.2's raises system.

from napi.types import NapiEnv, NapiStatus, NAPI_OK
from napi.bindings import Bindings
from napi.raw import raw_throw_error, raw_throw_type_error, raw_throw_range_error

# ---------------------------------------------------------------------------
# napi_status_name — human-readable name for a NapiStatus code
#
# Maps all documented N-API status codes to their C enum names so that
# check_status() error messages are immediately actionable without looking
# up the napi_status enum.
# ---------------------------------------------------------------------------
fn napi_status_name(status: NapiStatus) -> String:
    if status == 0:  return "napi_ok"
    if status == 1:  return "napi_invalid_arg"
    if status == 2:  return "napi_object_expected"
    if status == 3:  return "napi_string_expected"
    if status == 4:  return "napi_name_expected"
    if status == 5:  return "napi_function_expected"
    if status == 6:  return "napi_number_expected"
    if status == 7:  return "napi_boolean_expected"
    if status == 8:  return "napi_array_expected"
    if status == 9:  return "napi_generic_failure"
    if status == 10: return "napi_pending_exception"
    if status == 11: return "napi_cancelled"
    if status == 12: return "napi_escape_called_twice"
    if status == 13: return "napi_handle_scope_mismatch"
    if status == 14: return "napi_callback_scope_mismatch"
    if status == 15: return "napi_queue_full"
    if status == 16: return "napi_closing"
    if status == 17: return "napi_bigint_expected"
    if status == 18: return "napi_date_expected"
    if status == 19: return "napi_arraybuffer_expected"
    if status == 20: return "napi_detachable_arraybuffer_expected"
    if status == 21: return "napi_would_deadlock"
    if status == 22: return "napi_no_external_buffers_allowed"
    if status == 23: return "napi_cannot_run_js"
    return "napi_status_" + String(status)

# ---------------------------------------------------------------------------
# NapiError — typed wrapper around a failed napi_status code
#
# Kept for future use when Mojo's error system supports raising custom struct
# types. Currently check_status() raises Error(...) with a string message.
# ---------------------------------------------------------------------------
struct NapiError:
    ## The raw napi_status code that caused the error.
    var status: NapiStatus

    fn __init__(out self, status: NapiStatus):
        self.status = status

    fn __str__(self) -> String:
        return "NapiError: " + napi_status_name(self.status)

# ---------------------------------------------------------------------------
# check_status — verify every N-API call succeeded
#
# Call immediately after every N-API function that returns NapiStatus.
# Raises if status != napi_ok (0). The error message includes the human-
# readable status name (e.g., "napi_string_expected") for easy debugging.
#
# Usage:
#   var status = raw_create_string_utf8(env, str_ptr, len, result_ptr)
#   check_status(status)
# ---------------------------------------------------------------------------
fn check_status(status: NapiStatus) raises:
    if status != NAPI_OK:
        raise Error(napi_status_name(status))

# ---------------------------------------------------------------------------
# throw_js_error — set a pending JavaScript Error exception
#
# Calls napi_throw_error with a null error code and the given message.
# `msg` must be a StringLiteral so it has static (binary .rodata) lifetime —
# no ASAP destruction risk unlike heap Strings.
#
# The callback MUST return NapiValue() immediately after calling this.
# Node.js propagates the pending exception when the callback returns.
#
# Usage:
#   throw_js_error(env, "expected a string argument")
#   return NapiValue()
# ---------------------------------------------------------------------------
fn throw_js_error(env: NapiEnv, msg: StringLiteral):
    try:
        var null_code = OpaquePointer[ImmutAnyOrigin]()
        var msg_ptr: OpaquePointer[ImmutAnyOrigin] = msg.unsafe_ptr().bitcast[NoneType]()
        _ = raw_throw_error(env, null_code, msg_ptr)
    except:
        # If napi_throw_error itself fails (e.g., another exception is already
        # pending), there is no recoverable action — swallow and return.
        pass

# ---------------------------------------------------------------------------
# throw_js_error_dynamic — set a pending JavaScript Error with a heap String
#
# Use when the error message is computed at runtime (e.g., type mismatch
# messages that include the actual type name). The `msg` String is kept alive
# through the FFI call via an explicit `_ = msg_copy^` transfer-after-use.
#
# ASAP safety: `msg` is moved into `msg_copy`; the pointer is derived after
# the move, so `msg_copy` owns the bytes for the duration of the call.
#
# Usage:
#   throw_js_error_dynamic(env, "expected string but got " + type_name)
#   return NapiValue()
# ---------------------------------------------------------------------------
fn throw_js_error_dynamic(env: NapiEnv, msg: String):
    try:
        var msg_copy = msg   # owns the heap String bytes
        var null_code = OpaquePointer[ImmutAnyOrigin]()
        var msg_ptr: OpaquePointer[ImmutAnyOrigin] = msg_copy.unsafe_ptr().bitcast[NoneType]()
        _ = raw_throw_error(env, null_code, msg_ptr)
        _ = msg_copy^        # keep alive past the FFI call
    except:
        pass

# ---------------------------------------------------------------------------
# throw_js_type_error — set a pending JavaScript TypeError exception
# ---------------------------------------------------------------------------
fn throw_js_type_error(env: NapiEnv, msg: StringLiteral):
    try:
        var null_code = OpaquePointer[ImmutAnyOrigin]()
        var msg_ptr: OpaquePointer[ImmutAnyOrigin] = msg.unsafe_ptr().bitcast[NoneType]()
        _ = raw_throw_type_error(env, null_code, msg_ptr)
    except:
        pass

fn throw_js_type_error_dynamic(env: NapiEnv, msg: String):
    try:
        var msg_copy = msg
        var null_code = OpaquePointer[ImmutAnyOrigin]()
        var msg_ptr: OpaquePointer[ImmutAnyOrigin] = msg_copy.unsafe_ptr().bitcast[NoneType]()
        _ = raw_throw_type_error(env, null_code, msg_ptr)
        _ = msg_copy^
    except:
        pass

# ---------------------------------------------------------------------------
# throw_js_range_error — set a pending JavaScript RangeError exception
# ---------------------------------------------------------------------------
fn throw_js_range_error(env: NapiEnv, msg: StringLiteral):
    try:
        var null_code = OpaquePointer[ImmutAnyOrigin]()
        var msg_ptr: OpaquePointer[ImmutAnyOrigin] = msg.unsafe_ptr().bitcast[NoneType]()
        _ = raw_throw_range_error(env, null_code, msg_ptr)
    except:
        pass

fn throw_js_range_error_dynamic(env: NapiEnv, msg: String):
    try:
        var msg_copy = msg
        var null_code = OpaquePointer[ImmutAnyOrigin]()
        var msg_ptr: OpaquePointer[ImmutAnyOrigin] = msg_copy.unsafe_ptr().bitcast[NoneType]()
        _ = raw_throw_range_error(env, null_code, msg_ptr)
        _ = msg_copy^
    except:
        pass

# --- Bindings-aware overloads (no OwnedDLHandle, no raises) ---

fn throw_js_error(b: Bindings, env: NapiEnv, msg: StringLiteral):
    var null_code = OpaquePointer[ImmutAnyOrigin]()
    var msg_ptr: OpaquePointer[ImmutAnyOrigin] = msg.unsafe_ptr().bitcast[NoneType]()
    _ = raw_throw_error(b, env, null_code, msg_ptr)

fn throw_js_error_dynamic(b: Bindings, env: NapiEnv, msg: String):
    var msg_copy = msg
    var null_code = OpaquePointer[ImmutAnyOrigin]()
    var msg_ptr: OpaquePointer[ImmutAnyOrigin] = msg_copy.unsafe_ptr().bitcast[NoneType]()
    _ = raw_throw_error(b, env, null_code, msg_ptr)
    _ = msg_copy^

fn throw_js_type_error(b: Bindings, env: NapiEnv, msg: StringLiteral):
    var null_code = OpaquePointer[ImmutAnyOrigin]()
    var msg_ptr: OpaquePointer[ImmutAnyOrigin] = msg.unsafe_ptr().bitcast[NoneType]()
    _ = raw_throw_type_error(b, env, null_code, msg_ptr)

fn throw_js_type_error_dynamic(b: Bindings, env: NapiEnv, msg: String):
    var msg_copy = msg
    var null_code = OpaquePointer[ImmutAnyOrigin]()
    var msg_ptr: OpaquePointer[ImmutAnyOrigin] = msg_copy.unsafe_ptr().bitcast[NoneType]()
    _ = raw_throw_type_error(b, env, null_code, msg_ptr)
    _ = msg_copy^

fn throw_js_range_error(b: Bindings, env: NapiEnv, msg: StringLiteral):
    var null_code = OpaquePointer[ImmutAnyOrigin]()
    var msg_ptr: OpaquePointer[ImmutAnyOrigin] = msg.unsafe_ptr().bitcast[NoneType]()
    _ = raw_throw_range_error(b, env, null_code, msg_ptr)

fn throw_js_range_error_dynamic(b: Bindings, env: NapiEnv, msg: String):
    var msg_copy = msg
    var null_code = OpaquePointer[ImmutAnyOrigin]()
    var msg_ptr: OpaquePointer[ImmutAnyOrigin] = msg_copy.unsafe_ptr().bitcast[NoneType]()
    _ = raw_throw_range_error(b, env, null_code, msg_ptr)
    _ = msg_copy^
