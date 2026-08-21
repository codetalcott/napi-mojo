"""Status checking and JavaScript exception throwing.

Two distinct jobs that are easy to confuse:

- `check_status` turns a non-`napi_ok` status into a **Mojo** `Error`, so
  the failure propagates up your Mojo call stack. Every N-API call that
  returns a status must go through it.
- The `throw_js_*` functions set a **pending JavaScript exception** on the
  environment. They do not raise in Mojo and do not return a value.

**A callback must do both.** Raising in Mojo unwinds to your `except:`
block, but JavaScript learns nothing from that — so the `except:` block
must call a `throw_js_*` before returning. Returning a null napi_value
with no pending exception reaches JavaScript as `undefined`, turning a
failure into a silently successful call:

```mojo
except:
    throw_js_error(env, "myFunction failed")
    return NapiValue(unsafe_from_address=Int(0))
```

Throwing while an exception is already pending is a documented N-API
no-op, so an unconditional throw in `except:` is safe: an error that
originated in JavaScript keeps its own identity and code.

**Literal vs. dynamic.** The `StringLiteral` variants take a static,
NUL-terminated `.rodata` message — the type enforces at compile time that
only a literal is passed. Use the `_dynamic` variants for a computed
message; they copy the String to keep it alive across the FFI call.

**Overloads.** Each thrower exists twice: taking cached `Bindings`, and
env-only. The env-only forms resolve the symbol per call, and exist
precisely for `except:` blocks reached *because* fetching the bindings
failed. Prefer the Bindings form everywhere else.
"""


from napi.types import NapiEnv, NapiStatus, NAPI_OK
from napi.bindings import Bindings
from napi.raw import (
    raw_throw_error,
    raw_throw_type_error,
    raw_throw_range_error,
    raw_throw_syntax_error,
)


# ---------------------------------------------------------------------------
# napi_status_name — human-readable name for a NapiStatus code
#
# Maps all documented N-API status codes to their C enum names so that
# check_status() error messages are immediately actionable without looking
# up the napi_status enum.
# ---------------------------------------------------------------------------
def napi_status_name(status: NapiStatus) -> String:
    """Human-readable name for a napi_status code.

    Turns an opaque integer into the spelling used in the N-API docs, e.g.
    `napi_string_expected`, which is what makes a raised error legible.

    Args:
        status: The status code returned by an N-API call.

    Returns:
        The status name, or a generic label for an unknown code.
    """
    if status == 0:
        return "napi_ok"
    if status == 1:
        return "napi_invalid_arg"
    if status == 2:
        return "napi_object_expected"
    if status == 3:
        return "napi_string_expected"
    if status == 4:
        return "napi_name_expected"
    if status == 5:
        return "napi_function_expected"
    if status == 6:
        return "napi_number_expected"
    if status == 7:
        return "napi_boolean_expected"
    if status == 8:
        return "napi_array_expected"
    if status == 9:
        return "napi_generic_failure"
    if status == 10:
        return "napi_pending_exception"
    if status == 11:
        return "napi_cancelled"
    if status == 12:
        return "napi_escape_called_twice"
    if status == 13:
        return "napi_handle_scope_mismatch"
    if status == 14:
        return "napi_callback_scope_mismatch"
    if status == 15:
        return "napi_queue_full"
    if status == 16:
        return "napi_closing"
    if status == 17:
        return "napi_bigint_expected"
    if status == 18:
        return "napi_date_expected"
    if status == 19:
        return "napi_arraybuffer_expected"
    if status == 20:
        return "napi_detachable_arraybuffer_expected"
    if status == 21:
        return "napi_would_deadlock"
    if status == 22:
        return "napi_no_external_buffers_allowed"
    if status == 23:
        return "napi_cannot_run_js"
    return "napi_status_" + String(status)


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
def check_status(status: NapiStatus) raises:
    """Raise a Mojo Error unless the status is `napi_ok`.

    The single funnel for N-API failures. Call it on the result of every
    N-API call that returns a status, immediately.

    Note this raises in **Mojo** only — it does not set a pending JavaScript
    exception. A callback still has to throw one from its `except:` block.

    Args:
        status: The status code returned by an N-API call.

    Raises:
        If status is anything other than napi_ok; the message is
            the name from `napi_status_name`.
    """
    if status != NAPI_OK:
        raise Error(napi_status_name(status))


# ---------------------------------------------------------------------------
# throw_js_error — set a pending JavaScript Error exception
#
# Calls napi_throw_error with a null error code and the given message.
# `msg` must be a StringLiteral so it has static (binary .rodata) lifetime —
# no ASAP destruction risk unlike heap Strings.
#
# The callback MUST return NapiValue(unsafe_from_address=Int(0)) immediately after calling this.
# Node.js propagates the pending exception when the callback returns.
#
# Usage:
#   throw_js_error(env, "expected a string argument")
#   return NapiValue(unsafe_from_address=Int(0))
# ---------------------------------------------------------------------------
def throw_js_error(env: NapiEnv, msg: StringLiteral):
    """Set a pending JavaScript `Error` with a static literal message.

    The StringLiteral parameter type enforces at compile time
    that only a static, NUL-terminated message is passed.

    Does not raise in Mojo and does not return a value — the exception
    surfaces when control returns to JavaScript. A no-op if an exception
    is already pending, so calling it unconditionally in an `except:`
    block is safe.

    Args:
        b: Cached N-API bindings (Bindings overload only).
        env: The N-API environment.
        msg: The error message.
    """
    try:
        var null_code = OpaquePointer[ImmutAnyOrigin](unsafe_from_address=Int(0))
        var msg_ptr: OpaquePointer[ImmutAnyOrigin] = msg.unsafe_ptr().unsafe_bitcast[
            NoneType
        ]().as_unsafe_any_origin()
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
#   return NapiValue(unsafe_from_address=Int(0))
# ---------------------------------------------------------------------------
def throw_js_error_dynamic(env: NapiEnv, msg: String):
    """Set a pending JavaScript `Error` with a computed String message.

    The String is copied so it stays alive across the FFI call.

    Does not raise in Mojo and does not return a value — the exception
    surfaces when control returns to JavaScript. A no-op if an exception
    is already pending, so calling it unconditionally in an `except:`
    block is safe.

    Args:
        b: Cached N-API bindings (Bindings overload only).
        env: The N-API environment.
        msg: The error message.
    """
    try:
        var msg_copy = msg  # owns the heap String bytes
        var null_code = OpaquePointer[ImmutAnyOrigin](unsafe_from_address=Int(0))
        var msg_ptr: OpaquePointer[
            ImmutAnyOrigin
        ] = msg_copy.unsafe_ptr().unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        _ = raw_throw_error(env, null_code, msg_ptr)
        _ = msg_copy^  # keep alive past the FFI call
    except:
        pass


# ---------------------------------------------------------------------------
# throw_js_type_error — set a pending JavaScript TypeError exception
# ---------------------------------------------------------------------------
def throw_js_type_error(env: NapiEnv, msg: StringLiteral):
    """Set a pending JavaScript `TypeError` with a static literal message.

    The StringLiteral parameter type enforces at compile time
    that only a static, NUL-terminated message is passed.

    Does not raise in Mojo and does not return a value — the exception
    surfaces when control returns to JavaScript. A no-op if an exception
    is already pending, so calling it unconditionally in an `except:`
    block is safe.

    Args:
        b: Cached N-API bindings (Bindings overload only).
        env: The N-API environment.
        msg: The error message.
    """
    try:
        var null_code = OpaquePointer[ImmutAnyOrigin](unsafe_from_address=Int(0))
        var msg_ptr: OpaquePointer[ImmutAnyOrigin] = msg.unsafe_ptr().unsafe_bitcast[
            NoneType
        ]().as_unsafe_any_origin()
        _ = raw_throw_type_error(env, null_code, msg_ptr)
    except:
        pass


def throw_js_type_error_dynamic(env: NapiEnv, msg: String):
    """Set a pending JavaScript `TypeError` with a computed String message.

    The String is copied so it stays alive across the FFI call.

    Does not raise in Mojo and does not return a value — the exception
    surfaces when control returns to JavaScript. A no-op if an exception
    is already pending, so calling it unconditionally in an `except:`
    block is safe.

    Args:
        b: Cached N-API bindings (Bindings overload only).
        env: The N-API environment.
        msg: The error message.
    """
    try:
        var msg_copy = msg
        var null_code = OpaquePointer[ImmutAnyOrigin](unsafe_from_address=Int(0))
        var msg_ptr: OpaquePointer[
            ImmutAnyOrigin
        ] = msg_copy.unsafe_ptr().unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        _ = raw_throw_type_error(env, null_code, msg_ptr)
        _ = msg_copy^
    except:
        pass


# ---------------------------------------------------------------------------
# throw_js_range_error — set a pending JavaScript RangeError exception
# ---------------------------------------------------------------------------
def throw_js_range_error(env: NapiEnv, msg: StringLiteral):
    """Set a pending JavaScript `RangeError` with a static literal message.

    The StringLiteral parameter type enforces at compile time
    that only a static, NUL-terminated message is passed.

    Does not raise in Mojo and does not return a value — the exception
    surfaces when control returns to JavaScript. A no-op if an exception
    is already pending, so calling it unconditionally in an `except:`
    block is safe.

    Args:
        b: Cached N-API bindings (Bindings overload only).
        env: The N-API environment.
        msg: The error message.
    """
    try:
        var null_code = OpaquePointer[ImmutAnyOrigin](unsafe_from_address=Int(0))
        var msg_ptr: OpaquePointer[ImmutAnyOrigin] = msg.unsafe_ptr().unsafe_bitcast[
            NoneType
        ]().as_unsafe_any_origin()
        _ = raw_throw_range_error(env, null_code, msg_ptr)
    except:
        pass


def throw_js_range_error_dynamic(env: NapiEnv, msg: String):
    """Set a pending JavaScript `RangeError` with a computed String message.

    The String is copied so it stays alive across the FFI call.

    Does not raise in Mojo and does not return a value — the exception
    surfaces when control returns to JavaScript. A no-op if an exception
    is already pending, so calling it unconditionally in an `except:`
    block is safe.

    Args:
        b: Cached N-API bindings (Bindings overload only).
        env: The N-API environment.
        msg: The error message.
    """
    try:
        var msg_copy = msg
        var null_code = OpaquePointer[ImmutAnyOrigin](unsafe_from_address=Int(0))
        var msg_ptr: OpaquePointer[
            ImmutAnyOrigin
        ] = msg_copy.unsafe_ptr().unsafe_bitcast[
            NoneType
        ]().as_unsafe_any_origin()
        _ = raw_throw_range_error(env, null_code, msg_ptr)
        _ = msg_copy^
    except:
        pass


# --- Bindings-aware overloads (no OwnedDLHandle, no raises) ---


def throw_js_error(b: Bindings, env: NapiEnv, msg: StringLiteral):
    """Set a pending JavaScript `Error` with a static literal message.

    The StringLiteral parameter type enforces at compile time
    that only a static, NUL-terminated message is passed.

    Does not raise in Mojo and does not return a value — the exception
    surfaces when control returns to JavaScript. A no-op if an exception
    is already pending, so calling it unconditionally in an `except:`
    block is safe.

    Args:
        b: Cached N-API bindings (Bindings overload only).
        env: The N-API environment.
        msg: The error message.
    """
    var null_code = OpaquePointer[ImmutAnyOrigin](unsafe_from_address=Int(0))
    var msg_ptr: OpaquePointer[ImmutAnyOrigin] = msg.unsafe_ptr().unsafe_bitcast[
        NoneType
    ]().as_unsafe_any_origin()
    _ = raw_throw_error(b, env, null_code, msg_ptr)


def throw_js_error_dynamic(b: Bindings, env: NapiEnv, msg: String):
    """Set a pending JavaScript `Error` with a computed String message.

    The String is copied so it stays alive across the FFI call.

    Does not raise in Mojo and does not return a value — the exception
    surfaces when control returns to JavaScript. A no-op if an exception
    is already pending, so calling it unconditionally in an `except:`
    block is safe.

    Args:
        b: Cached N-API bindings (Bindings overload only).
        env: The N-API environment.
        msg: The error message.
    """
    var msg_copy = msg
    var null_code = OpaquePointer[ImmutAnyOrigin](unsafe_from_address=Int(0))
    var msg_ptr: OpaquePointer[ImmutAnyOrigin] = msg_copy.unsafe_ptr().unsafe_bitcast[
        NoneType
    ]().as_unsafe_any_origin()
    _ = raw_throw_error(b, env, null_code, msg_ptr)
    _ = msg_copy^


def throw_js_type_error(b: Bindings, env: NapiEnv, msg: StringLiteral):
    """Set a pending JavaScript `TypeError` with a static literal message.

    The StringLiteral parameter type enforces at compile time
    that only a static, NUL-terminated message is passed.

    Does not raise in Mojo and does not return a value — the exception
    surfaces when control returns to JavaScript. A no-op if an exception
    is already pending, so calling it unconditionally in an `except:`
    block is safe.

    Args:
        b: Cached N-API bindings (Bindings overload only).
        env: The N-API environment.
        msg: The error message.
    """
    var null_code = OpaquePointer[ImmutAnyOrigin](unsafe_from_address=Int(0))
    var msg_ptr: OpaquePointer[ImmutAnyOrigin] = msg.unsafe_ptr().unsafe_bitcast[
        NoneType
    ]().as_unsafe_any_origin()
    _ = raw_throw_type_error(b, env, null_code, msg_ptr)


def throw_js_type_error_dynamic(b: Bindings, env: NapiEnv, msg: String):
    """Set a pending JavaScript `TypeError` with a computed String message.

    The String is copied so it stays alive across the FFI call.

    Does not raise in Mojo and does not return a value — the exception
    surfaces when control returns to JavaScript. A no-op if an exception
    is already pending, so calling it unconditionally in an `except:`
    block is safe.

    Args:
        b: Cached N-API bindings (Bindings overload only).
        env: The N-API environment.
        msg: The error message.
    """
    var msg_copy = msg
    var null_code = OpaquePointer[ImmutAnyOrigin](unsafe_from_address=Int(0))
    var msg_ptr: OpaquePointer[ImmutAnyOrigin] = msg_copy.unsafe_ptr().unsafe_bitcast[
        NoneType
    ]().as_unsafe_any_origin()
    _ = raw_throw_type_error(b, env, null_code, msg_ptr)
    _ = msg_copy^


def throw_js_range_error(b: Bindings, env: NapiEnv, msg: StringLiteral):
    """Set a pending JavaScript `RangeError` with a static literal message.

    The StringLiteral parameter type enforces at compile time
    that only a static, NUL-terminated message is passed.

    Does not raise in Mojo and does not return a value — the exception
    surfaces when control returns to JavaScript. A no-op if an exception
    is already pending, so calling it unconditionally in an `except:`
    block is safe.

    Args:
        b: Cached N-API bindings (Bindings overload only).
        env: The N-API environment.
        msg: The error message.
    """
    var null_code = OpaquePointer[ImmutAnyOrigin](unsafe_from_address=Int(0))
    var msg_ptr: OpaquePointer[ImmutAnyOrigin] = msg.unsafe_ptr().unsafe_bitcast[
        NoneType
    ]().as_unsafe_any_origin()
    _ = raw_throw_range_error(b, env, null_code, msg_ptr)


def throw_js_range_error_dynamic(b: Bindings, env: NapiEnv, msg: String):
    """Set a pending JavaScript `RangeError` with a computed String message.

    The String is copied so it stays alive across the FFI call.

    Does not raise in Mojo and does not return a value — the exception
    surfaces when control returns to JavaScript. A no-op if an exception
    is already pending, so calling it unconditionally in an `except:`
    block is safe.

    Args:
        b: Cached N-API bindings (Bindings overload only).
        env: The N-API environment.
        msg: The error message.
    """
    var msg_copy = msg
    var null_code = OpaquePointer[ImmutAnyOrigin](unsafe_from_address=Int(0))
    var msg_ptr: OpaquePointer[ImmutAnyOrigin] = msg_copy.unsafe_ptr().unsafe_bitcast[
        NoneType
    ]().as_unsafe_any_origin()
    _ = raw_throw_range_error(b, env, null_code, msg_ptr)
    _ = msg_copy^


# ---------------------------------------------------------------------------
# throw_js_syntax_error — set a pending JavaScript SyntaxError exception
#
# Uses node_api_throw_syntax_error (node_api_ prefix, N-API v9).
# ---------------------------------------------------------------------------
def throw_js_syntax_error(env: NapiEnv, msg: StringLiteral):
    """Set a pending JavaScript `SyntaxError` with a static literal message.

    The StringLiteral parameter type enforces at compile time
    that only a static, NUL-terminated message is passed.

    Does not raise in Mojo and does not return a value — the exception
    surfaces when control returns to JavaScript. A no-op if an exception
    is already pending, so calling it unconditionally in an `except:`
    block is safe.

    Args:
        b: Cached N-API bindings (Bindings overload only).
        env: The N-API environment.
        msg: The error message.
    """
    try:
        var null_code = OpaquePointer[ImmutAnyOrigin](unsafe_from_address=Int(0))
        var msg_ptr: OpaquePointer[ImmutAnyOrigin] = msg.unsafe_ptr().unsafe_bitcast[
            NoneType
        ]().as_unsafe_any_origin()
        _ = raw_throw_syntax_error(env, null_code, msg_ptr)
    except:
        pass


def throw_js_syntax_error_dynamic(env: NapiEnv, msg: String):
    """Set a pending JavaScript `SyntaxError` with a computed String message.

    The String is copied so it stays alive across the FFI call.

    Does not raise in Mojo and does not return a value — the exception
    surfaces when control returns to JavaScript. A no-op if an exception
    is already pending, so calling it unconditionally in an `except:`
    block is safe.

    Args:
        b: Cached N-API bindings (Bindings overload only).
        env: The N-API environment.
        msg: The error message.
    """
    try:
        var msg_copy = msg
        var null_code = OpaquePointer[ImmutAnyOrigin](unsafe_from_address=Int(0))
        var msg_ptr: OpaquePointer[
            ImmutAnyOrigin
        ] = msg_copy.unsafe_ptr().unsafe_bitcast[
            NoneType
        ]().as_unsafe_any_origin()
        _ = raw_throw_syntax_error(env, null_code, msg_ptr)
        _ = msg_copy^
    except:
        pass


def throw_js_syntax_error(b: Bindings, env: NapiEnv, msg: StringLiteral):
    """Set a pending JavaScript `SyntaxError` with a static literal message.

    The StringLiteral parameter type enforces at compile time
    that only a static, NUL-terminated message is passed.

    Does not raise in Mojo and does not return a value — the exception
    surfaces when control returns to JavaScript. A no-op if an exception
    is already pending, so calling it unconditionally in an `except:`
    block is safe.

    Args:
        b: Cached N-API bindings (Bindings overload only).
        env: The N-API environment.
        msg: The error message.
    """
    var null_code = OpaquePointer[ImmutAnyOrigin](unsafe_from_address=Int(0))
    var msg_ptr: OpaquePointer[ImmutAnyOrigin] = msg.unsafe_ptr().unsafe_bitcast[
        NoneType
    ]().as_unsafe_any_origin()
    _ = raw_throw_syntax_error(b, env, null_code, msg_ptr)


def throw_js_syntax_error_dynamic(b: Bindings, env: NapiEnv, msg: String):
    """Set a pending JavaScript `SyntaxError` with a computed String message.

    The String is copied so it stays alive across the FFI call.

    Does not raise in Mojo and does not return a value — the exception
    surfaces when control returns to JavaScript. A no-op if an exception
    is already pending, so calling it unconditionally in an `except:`
    block is safe.

    Args:
        b: Cached N-API bindings (Bindings overload only).
        env: The N-API environment.
        msg: The error message.
    """
    var msg_copy = msg
    var null_code = OpaquePointer[ImmutAnyOrigin](unsafe_from_address=Int(0))
    var msg_ptr: OpaquePointer[ImmutAnyOrigin] = msg_copy.unsafe_ptr().unsafe_bitcast[
        NoneType
    ]().as_unsafe_any_origin()
    _ = raw_throw_syntax_error(b, env, null_code, msg_ptr)
    _ = msg_copy^
