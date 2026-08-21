# `js_int64`

Source: [`src/napi/framework/js_int64.mojo`](../../src/napi/framework/js_int64.mojo)

Ergonomic wrapper for JavaScript numbers read and written as `Int64`.

```mojo
var n = JsInt64.create(b, env, 9007199254740993)
```

**A JS number cannot hold every Int64 exactly.** JavaScript numbers are
Float64, so only integers up to 2**53 - 1 survive a round trip unchanged;
beyond that `create` silently loses precision. `from_napi_value` follows
`napi_get_value_int64`, which clamps out-of-range doubles and converts
NaN and the infinities to 0. When you need exact 64-bit integers across
the boundary, use `JsBigInt` instead — it is lossless by construction.

---

## `JsInt64`

Typed wrapper for a JavaScript number carrying an Int64 value.

### Fields

| field | type | description |
|---|---|---|
| `value` | `NapiValue` | The underlying napi_value handle. Valid within the current handle scope. |

### `__init__`

```mojo
def __init__(out self, value: Pointer[NoneType, MutUntrackedOrigin])
```

Wrap an existing napi_value of the matching JS type.

This does not validate the handle.

| argument | type | description |
|---|---|---|
| `value` | `NapiValue` | The napi_value to wrap. |

### `create`

```mojo
def create(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], n: Int64) -> Self
```

Create a JS number from a Mojo Int64.

Values beyond 2**53 - 1 lose precision, because the JS number is a
Float64. Use `JsBigInt` when that matters.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `n` | `Int64` | The value to represent. |

**Returns** — A JsInt64 wrapping the new napi_value.

**Raises** — If napi_create_int64 does not return napi_ok.

### `from_napi_value`

```mojo
def from_napi_value(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], val: Pointer[NoneType, MutUntrackedOrigin]) -> Int64
```

Read a napi_value as a Mojo Int64.

Out-of-range doubles are clamped; NaN and the infinities give 0.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `val` | `NapiValue` | A napi_value holding a JS number. |

**Returns** — The converted Int64.

**Raises** — `napi_number_expected` if val is not a number.
