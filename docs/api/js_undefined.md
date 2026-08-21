# `js_undefined`

Source: [`src/napi/framework/js_undefined.mojo`](../../src/napi/framework/js_undefined.mojo)

Ergonomic wrapper for the JavaScript `undefined` value.

```mojo
var undef = JsUndefined.create(b, env)
return undef.value
```

`undefined` is a singleton, so `napi_get_undefined` returns the same
`napi_value` every time within a given `napi_env`.

This is the right value to return from a callback that has nothing to
return. It is **not** interchangeable with a null napi_value handle: a
null handle returned with no pending exception is what makes a failed
callback look like a successful one that produced `undefined`. Return
this explicitly when you mean it, and throw when you do not.

---

## `JsUndefined`

Typed wrapper for the JavaScript `undefined` napi_value.

### Fields

| field | type | description |
|---|---|---|
| `value` | `NapiValue` | The underlying napi_value handle (the undefined singleton). |

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
def create(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin]) -> Self
```

Return the JavaScript `undefined` singleton.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |

**Returns** — A JsUndefined wrapping the environment's undefined singleton.

**Raises** — If napi_get_undefined does not return napi_ok.
