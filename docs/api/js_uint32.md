# `js_uint32`

Source: [`src/napi/framework/js_uint32.mojo`](../../src/napi/framework/js_uint32.mojo)

Ergonomic wrapper for JavaScript numbers read and written as `UInt32`.

```mojo
var n = JsUInt32.create(b, env, 0xDEADBEEF)
var back = JsUInt32.from_napi_value(b, env, n.value)
```

`from_napi_value` follows `napi_get_value_uint32`, which applies the
ECMAScript ToUint32 conversion rather than raising: negatives wrap into
the unsigned range (`-1` arrives as `4294967295`), non-integral values
truncate toward zero, and NaN and the infinities convert to 0. Use this
for bitmask-style values; use `JsNumber` when you want the exact double.

---

## `JsUInt32`

Typed wrapper for a JavaScript number carrying a UInt32 value.

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
def create(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], n: UInt32) -> Self
```

Create a JS number from a Mojo UInt32.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `n` | `UInt32` | The value to represent. |

**Returns** — A JsUInt32 wrapping the new napi_value.

**Raises** — If napi_create_uint32 does not return napi_ok.

### `from_napi_value`

```mojo
def from_napi_value(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], val: Pointer[NoneType, MutUntrackedOrigin]) -> UInt32
```

Read a napi_value as a Mojo UInt32.

Applies the ECMAScript ToUint32 conversion — negatives and
out-of-range values wrap rather than raising.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `val` | `NapiValue` | A napi_value holding a JS number. |

**Returns** — The converted UInt32.

**Raises** — `napi_number_expected` if val is not a number.
