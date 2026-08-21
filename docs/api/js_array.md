# `js_array`

Source: [`src/napi/framework/js_array.mojo`](../../src/napi/framework/js_array.mojo)

Ergonomic wrapper for JavaScript Array values.

```mojo
var arr = JsArray.create_with_length(b, env, 3)
arr.set(b, env, 0, JsNumber.create(b, env, 1.0).value)
return arr.value
```

Indices are `UInt32`, matching JavaScript's array index range.

**A loop that creates a napi_value per iteration needs a handle scope.**
Every handle stays alive until its enclosing scope closes, so building a
large array without one accumulates handles for the whole loop. Open a
`HandleScope` per iteration — and create the array itself *outside* it, or
it dies with the first iteration. Values stored into the array survive the
scope that created them.

---

## `JsArray`

Typed wrapper for a JavaScript Array napi_value.

### Fields

| field | type | description |
|---|---|---|
| `value` | `NapiValue` | The underlying napi_value handle. Valid within the current handle scope. |

### `__init__`

```mojo
def __init__(out self, value: Pointer[NoneType, MutUntrackedOrigin])
```

Wrap an existing napi_value known to be an Array.

This does not validate the handle; use `js_is_array` if unsure.

| argument | type | description |
|---|---|---|
| `value` | `NapiValue` | The napi_value to wrap. |

### `create_with_length`

```mojo
def create_with_length(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], len: UInt) -> Self
```

Create a JS Array with a given initial length.

The length is a hint for the engine, exactly like `new Array(n)` — the
elements are holes until assigned, not zeros.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `len` | `UInt` | The initial length. |

**Returns** — A JsArray wrapping the new napi_value.

**Raises** — If napi_create_array_with_length does not return napi_ok.

### `set`

```mojo
def set(self, b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], index: UInt32, val: Pointer[NoneType, MutUntrackedOrigin])
```

Store a value at an index.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `index` | `UInt32` | The array index. |
| `val` | `NapiValue` | The value to store. |

**Raises** — If napi_set_element does not return napi_ok.

### `get`

```mojo
def get(self, b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], index: UInt32) -> NapiValue
```

Read the value at an index.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `index` | `UInt32` | The array index. |

**Returns** — The element, or undefined if the index is a hole or out of range.

**Raises** — If napi_get_element does not return napi_ok.

### `length`

```mojo
def length(self, b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin]) -> UInt32
```

Return the array's `length`.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |

**Returns** — The length.

**Raises** — If napi_get_array_length does not return napi_ok.

### `has`

```mojo
def has(self, b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], index: UInt32) -> Bool
```

Report whether an index has a value.

False for a hole in a sparse array, even below `length`.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `index` | `UInt32` | The array index. |

**Returns** — True if the element exists.

**Raises** — If napi_has_element does not return napi_ok.

### `delete_element`

```mojo
def delete_element(self, b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], index: UInt32) -> Bool
```

Delete the element at an index, leaving a hole.

Like the `delete` operator: `length` is unchanged.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `index` | `UInt32` | The array index. |

**Returns** — True if the element was deleted or was already absent.

**Raises** — If napi_delete_element does not return napi_ok.
