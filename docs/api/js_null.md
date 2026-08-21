# `js_null`

Source: [`src/napi/framework/js_null.mojo`](../../src/napi/framework/js_null.mojo)

Ergonomic wrapper for the JavaScript `null` value.

`JsNull` wraps `napi_get_null`, which returns the pre-existing null singleton:

```mojo
var null_val = JsNull.create(b, env)
return null_val.value
```

JavaScript `null` is a singleton, so `napi_get_null` returns the same
`napi_value` every time within a given `napi_env`. Note that `null` and
`undefined` are distinct values in JavaScript — see `js_undefined` for the
other one; returning the wrong one is visible to callers through `===`.

---

## `JsNull`

Typed wrapper for the JavaScript `null` napi_value.

### Fields

| field | type | description |
|---|---|---|
| `value` | `NapiValue` | The underlying napi_value handle (the null singleton). |

### `__init__`

```mojo
def __init__(out self, value: Pointer[NoneType, MutUntrackedOrigin])
```

Wrap an existing napi_value known to be JavaScript `null`.

This does not validate the handle. Prefer `create` unless you already
hold a null from N-API.

| argument | type | description |
|---|---|---|
| `value` | `NapiValue` | The napi_value to wrap. |

### `create`

```mojo
def create(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin]) -> Self
```

Return the JavaScript `null` singleton.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |

**Returns** — A JsNull wrapping the environment's null singleton.

**Raises** — If napi_get_null does not return napi_ok.
