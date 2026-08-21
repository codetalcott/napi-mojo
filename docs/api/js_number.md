# `js_number`

Source: [`src/napi/framework/js_number.mojo`](../../src/napi/framework/js_number.mojo)

Ergonomic wrapper for JavaScript number values.

```mojo
var n = JsNumber.create(b, env, 42.5)
var x = JsNumber.from_napi_value(b, env, n.value)   # 42.5
```

JavaScript has a single numeric type, IEEE 754 Float64, which is what
`create`/`from_napi_value` use. `create_int`/`to_int` are the Int-typed
convenience pair over the same JS type — they go through
`napi_create_int64`/`napi_get_value_int64`, so integers beyond 2**53 - 1
lose precision. Reach for `JsBigInt` when you need exact 64-bit values,
or `JsInt32`/`JsUInt32` when you want the wrapping ToInt32/ToUint32
conversions.

---

## `JsNumber`

Typed wrapper for a JavaScript number napi_value.

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
def create(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], n: Float64) -> Self
```

Create a JS number from a Mojo Float64.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `n` | `Float64` | The value to represent. |

**Returns** — A JsNumber wrapping the new napi_value.

**Raises** — If napi_create_double does not return napi_ok.

### `from_napi_value`

```mojo
def from_napi_value(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], val: Pointer[NoneType, MutUntrackedOrigin]) -> Float64
```

Read a napi_value as a Mojo Float64.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `val` | `NapiValue` | A napi_value holding a JS number. |

**Returns** — The Float64 value.

**Raises** — `napi_number_expected` if val is not a number.

### `create_int`

```mojo
def create_int(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], n: Int) -> Self
```

Create a JS number from a Mojo Int.

Goes through napi_create_int64, so values beyond 2**53 - 1 lose
precision in the resulting JS number.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `n` | `Int` | The value to represent. |

**Returns** — A JsNumber wrapping the new napi_value.

**Raises** — If napi_create_int64 does not return napi_ok.

### `to_int`

```mojo
def to_int(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], val: Pointer[NoneType, MutUntrackedOrigin]) -> Int
```

Read a napi_value as a Mojo Int.

Out-of-range doubles are clamped; NaN and the infinities give 0.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `val` | `NapiValue` | A napi_value holding a JS number. |

**Returns** — The Int value.

**Raises** — `napi_number_expected` if val is not a number.
