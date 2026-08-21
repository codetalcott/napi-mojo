# `js_int32`

Source: [`src/napi/framework/js_int32.mojo`](../../src/napi/framework/js_int32.mojo)

Ergonomic wrapper for JavaScript numbers read and written as `Int32`.

JavaScript has one numeric type (Float64), so these helpers are about how
the value is *converted* at the boundary, not about a distinct JS type:

```mojo
var n = JsInt32.create(b, env, -7)
var back = JsInt32.from_napi_value(b, env, n.value)   # -7
```

`from_napi_value` follows `napi_get_value_int32`, which does **not** raise
on out-of-range input: it applies the ECMAScript ToInt32 conversion, so
`2**31` arrives as `-2147483648` and a non-integral value is truncated
toward zero. Check the range yourself if wraparound would be a bug.
NaN and the infinities convert to 0.

---

## `JsInt32`

Typed wrapper for a JavaScript number carrying an Int32 value.

### Fields

| field | type | description |
|---|---|---|
| `value` | `NapiValue` | The underlying napi_value handle. Valid within the current handle scope. |

### `__init__`

```mojo
def __init__(out self, value: Pointer[NoneType, MutUntrackedOrigin])
```

Wrap an existing napi_value known to hold a number.

| argument | type | description |
|---|---|---|
| `value` | `NapiValue` | The napi_value to wrap. |

### `create`

```mojo
def create(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], n: Int32) -> Self
```

Create a JS number from a Mojo Int32.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `n` | `Int32` | The value to represent. |

**Returns** — A JsInt32 wrapping the new napi_value.

**Raises** — If napi_create_int32 does not return napi_ok.

### `from_napi_value`

```mojo
def from_napi_value(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], val: Pointer[NoneType, MutUntrackedOrigin]) -> Int32
```

Read a napi_value as a Mojo Int32.

Applies the ECMAScript ToInt32 conversion — out-of-range values wrap
rather than raising, and non-integral values truncate toward zero.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `val` | `NapiValue` | A napi_value holding a JS number. |

**Returns** — The converted Int32.

**Raises** — `napi_number_expected` if val is not a number.
