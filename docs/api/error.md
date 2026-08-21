# `error`

Source: [`src/napi/error.mojo`](../../src/napi/error.mojo)

Status checking and JavaScript exception throwing.

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

---

## Functions

### `napi_status_name`

```mojo
def napi_status_name(status: Int32) -> String
```

Human-readable name for a napi_status code.

Turns an opaque integer into the spelling used in the N-API docs, e.g.
`napi_string_expected`, which is what makes a raised error legible.

| argument | type | description |
|---|---|---|
| `status` | `Int32` | The status code returned by an N-API call. |

**Returns** — The status name, or a generic label for an unknown code.

### `check_status`

```mojo
def check_status(status: Int32)
```

Raise a Mojo Error unless the status is `napi_ok`.

The single funnel for N-API failures. Call it on the result of every
N-API call that returns a status, immediately.

Note this raises in **Mojo** only — it does not set a pending JavaScript
exception. A callback still has to throw one from its `except:` block.

| argument | type | description |
|---|---|---|
| `status` | `Int32` | The status code returned by an N-API call. |

**Raises** — If status is anything other than napi_ok; the message is the name from `napi_status_name`.

### `throw_js_error`

*Overload 1 of 2.*

```mojo
def throw_js_error(env: Pointer[NoneType, MutUntrackedOrigin], msg: StringLiteral)
```

Set a pending JavaScript `Error` with a static literal message.

The StringLiteral parameter type enforces at compile time
that only a static, NUL-terminated message is passed.

Does not raise in Mojo and does not return a value — the exception
surfaces when control returns to JavaScript. A no-op if an exception
is already pending, so calling it unconditionally in an `except:`
block is safe.

| argument | type | description |
|---|---|---|
| `env` | `NapiEnv` | The N-API environment. |
| `msg` | `StringLiteral` | The error message. |

*Overload 2 of 2.*

```mojo
def throw_js_error(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], msg: StringLiteral)
```

Set a pending JavaScript `Error` with a static literal message.

The StringLiteral parameter type enforces at compile time
that only a static, NUL-terminated message is passed.

Does not raise in Mojo and does not return a value — the exception
surfaces when control returns to JavaScript. A no-op if an exception
is already pending, so calling it unconditionally in an `except:`
block is safe.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings (Bindings overload only). |
| `env` | `NapiEnv` | The N-API environment. |
| `msg` | `StringLiteral` | The error message. |

### `throw_js_error_dynamic`

*Overload 1 of 2.*

```mojo
def throw_js_error_dynamic(env: Pointer[NoneType, MutUntrackedOrigin], msg: String)
```

Set a pending JavaScript `Error` with a computed String message.

The String is copied so it stays alive across the FFI call.

Does not raise in Mojo and does not return a value — the exception
surfaces when control returns to JavaScript. A no-op if an exception
is already pending, so calling it unconditionally in an `except:`
block is safe.

| argument | type | description |
|---|---|---|
| `env` | `NapiEnv` | The N-API environment. |
| `msg` | `String` | The error message. |

*Overload 2 of 2.*

```mojo
def throw_js_error_dynamic(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], msg: String)
```

Set a pending JavaScript `Error` with a computed String message.

The String is copied so it stays alive across the FFI call.

Does not raise in Mojo and does not return a value — the exception
surfaces when control returns to JavaScript. A no-op if an exception
is already pending, so calling it unconditionally in an `except:`
block is safe.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings (Bindings overload only). |
| `env` | `NapiEnv` | The N-API environment. |
| `msg` | `String` | The error message. |

### `throw_js_type_error`

*Overload 1 of 2.*

```mojo
def throw_js_type_error(env: Pointer[NoneType, MutUntrackedOrigin], msg: StringLiteral)
```

Set a pending JavaScript `TypeError` with a static literal message.

The StringLiteral parameter type enforces at compile time
that only a static, NUL-terminated message is passed.

Does not raise in Mojo and does not return a value — the exception
surfaces when control returns to JavaScript. A no-op if an exception
is already pending, so calling it unconditionally in an `except:`
block is safe.

| argument | type | description |
|---|---|---|
| `env` | `NapiEnv` | The N-API environment. |
| `msg` | `StringLiteral` | The error message. |

*Overload 2 of 2.*

```mojo
def throw_js_type_error(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], msg: StringLiteral)
```

Set a pending JavaScript `TypeError` with a static literal message.

The StringLiteral parameter type enforces at compile time
that only a static, NUL-terminated message is passed.

Does not raise in Mojo and does not return a value — the exception
surfaces when control returns to JavaScript. A no-op if an exception
is already pending, so calling it unconditionally in an `except:`
block is safe.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings (Bindings overload only). |
| `env` | `NapiEnv` | The N-API environment. |
| `msg` | `StringLiteral` | The error message. |

### `throw_js_type_error_dynamic`

*Overload 1 of 2.*

```mojo
def throw_js_type_error_dynamic(env: Pointer[NoneType, MutUntrackedOrigin], msg: String)
```

Set a pending JavaScript `TypeError` with a computed String message.

The String is copied so it stays alive across the FFI call.

Does not raise in Mojo and does not return a value — the exception
surfaces when control returns to JavaScript. A no-op if an exception
is already pending, so calling it unconditionally in an `except:`
block is safe.

| argument | type | description |
|---|---|---|
| `env` | `NapiEnv` | The N-API environment. |
| `msg` | `String` | The error message. |

*Overload 2 of 2.*

```mojo
def throw_js_type_error_dynamic(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], msg: String)
```

Set a pending JavaScript `TypeError` with a computed String message.

The String is copied so it stays alive across the FFI call.

Does not raise in Mojo and does not return a value — the exception
surfaces when control returns to JavaScript. A no-op if an exception
is already pending, so calling it unconditionally in an `except:`
block is safe.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings (Bindings overload only). |
| `env` | `NapiEnv` | The N-API environment. |
| `msg` | `String` | The error message. |

### `throw_js_range_error`

*Overload 1 of 2.*

```mojo
def throw_js_range_error(env: Pointer[NoneType, MutUntrackedOrigin], msg: StringLiteral)
```

Set a pending JavaScript `RangeError` with a static literal message.

The StringLiteral parameter type enforces at compile time
that only a static, NUL-terminated message is passed.

Does not raise in Mojo and does not return a value — the exception
surfaces when control returns to JavaScript. A no-op if an exception
is already pending, so calling it unconditionally in an `except:`
block is safe.

| argument | type | description |
|---|---|---|
| `env` | `NapiEnv` | The N-API environment. |
| `msg` | `StringLiteral` | The error message. |

*Overload 2 of 2.*

```mojo
def throw_js_range_error(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], msg: StringLiteral)
```

Set a pending JavaScript `RangeError` with a static literal message.

The StringLiteral parameter type enforces at compile time
that only a static, NUL-terminated message is passed.

Does not raise in Mojo and does not return a value — the exception
surfaces when control returns to JavaScript. A no-op if an exception
is already pending, so calling it unconditionally in an `except:`
block is safe.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings (Bindings overload only). |
| `env` | `NapiEnv` | The N-API environment. |
| `msg` | `StringLiteral` | The error message. |

### `throw_js_range_error_dynamic`

*Overload 1 of 2.*

```mojo
def throw_js_range_error_dynamic(env: Pointer[NoneType, MutUntrackedOrigin], msg: String)
```

Set a pending JavaScript `RangeError` with a computed String message.

The String is copied so it stays alive across the FFI call.

Does not raise in Mojo and does not return a value — the exception
surfaces when control returns to JavaScript. A no-op if an exception
is already pending, so calling it unconditionally in an `except:`
block is safe.

| argument | type | description |
|---|---|---|
| `env` | `NapiEnv` | The N-API environment. |
| `msg` | `String` | The error message. |

*Overload 2 of 2.*

```mojo
def throw_js_range_error_dynamic(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], msg: String)
```

Set a pending JavaScript `RangeError` with a computed String message.

The String is copied so it stays alive across the FFI call.

Does not raise in Mojo and does not return a value — the exception
surfaces when control returns to JavaScript. A no-op if an exception
is already pending, so calling it unconditionally in an `except:`
block is safe.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings (Bindings overload only). |
| `env` | `NapiEnv` | The N-API environment. |
| `msg` | `String` | The error message. |

### `throw_js_syntax_error`

*Overload 1 of 2.*

```mojo
def throw_js_syntax_error(env: Pointer[NoneType, MutUntrackedOrigin], msg: StringLiteral)
```

Set a pending JavaScript `SyntaxError` with a static literal message.

The StringLiteral parameter type enforces at compile time
that only a static, NUL-terminated message is passed.

Does not raise in Mojo and does not return a value — the exception
surfaces when control returns to JavaScript. A no-op if an exception
is already pending, so calling it unconditionally in an `except:`
block is safe.

| argument | type | description |
|---|---|---|
| `env` | `NapiEnv` | The N-API environment. |
| `msg` | `StringLiteral` | The error message. |

*Overload 2 of 2.*

```mojo
def throw_js_syntax_error(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], msg: StringLiteral)
```

Set a pending JavaScript `SyntaxError` with a static literal message.

The StringLiteral parameter type enforces at compile time
that only a static, NUL-terminated message is passed.

Does not raise in Mojo and does not return a value — the exception
surfaces when control returns to JavaScript. A no-op if an exception
is already pending, so calling it unconditionally in an `except:`
block is safe.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings (Bindings overload only). |
| `env` | `NapiEnv` | The N-API environment. |
| `msg` | `StringLiteral` | The error message. |

### `throw_js_syntax_error_dynamic`

*Overload 1 of 2.*

```mojo
def throw_js_syntax_error_dynamic(env: Pointer[NoneType, MutUntrackedOrigin], msg: String)
```

Set a pending JavaScript `SyntaxError` with a computed String message.

The String is copied so it stays alive across the FFI call.

Does not raise in Mojo and does not return a value — the exception
surfaces when control returns to JavaScript. A no-op if an exception
is already pending, so calling it unconditionally in an `except:`
block is safe.

| argument | type | description |
|---|---|---|
| `env` | `NapiEnv` | The N-API environment. |
| `msg` | `String` | The error message. |

*Overload 2 of 2.*

```mojo
def throw_js_syntax_error_dynamic(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], msg: String)
```

Set a pending JavaScript `SyntaxError` with a computed String message.

The String is copied so it stays alive across the FFI call.

Does not raise in Mojo and does not return a value — the exception
surfaces when control returns to JavaScript. A no-op if an exception
is already pending, so calling it unconditionally in an `except:`
block is safe.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings (Bindings overload only). |
| `env` | `NapiEnv` | The N-API environment. |
| `msg` | `String` | The error message. |
