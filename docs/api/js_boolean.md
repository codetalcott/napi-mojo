# `js_boolean`

Source: [`src/napi/framework/js_boolean.mojo`](../../src/napi/framework/js_boolean.mojo)

Ergonomic wrapper for JavaScript boolean values.

```mojo
var flag = JsBoolean.create(b, env, True)
var back = JsBoolean.from_napi_value(b, env, flag.value)
```

JavaScript has `true`/`false` singletons, so `napi_get_boolean` returns a
pre-existing value rather than allocating one.

`from_napi_value` requires an actual boolean and raises otherwise — it
does not apply JavaScript truthiness. For truthiness (`""` -> False,
`0` -> False, any object -> True), use `js_coerce_to_bool`.

---

## `JsBoolean`

Typed wrapper for a JavaScript boolean napi_value.

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
def create(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], bval: Bool) -> Self
```

Create a JS boolean from a Mojo Bool.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `bval` | `Bool` | The value to represent. |

**Returns** — A JsBoolean wrapping the JS true/false singleton.

**Raises** — If napi_get_boolean does not return napi_ok.

### `from_napi_value`

```mojo
def from_napi_value(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], val: Pointer[NoneType, MutUntrackedOrigin]) -> Bool
```

Read a napi_value as a Mojo Bool.

Requires an actual JS boolean; this is not a truthiness test.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `val` | `NapiValue` | A napi_value holding a JS boolean. |

**Returns** — The Mojo Bool.

**Raises** — `napi_boolean_expected` if val is not a boolean.
