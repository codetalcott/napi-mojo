# `convert`

Source: [`src/napi/framework/convert.mojo`](../../src/napi/framework/convert.mojo)

Type-conversion traits for JS <-> Mojo marshalling.

`ToJsValue` and `FromJsValue` standardise how a Mojo value crosses the
boundary, so generic code can be written once over any convertible type:

```mojo
var result = JsF64(42.0).to_js(b, env)          # Mojo -> JS
var n = JsF64.from_js(b, env, napi_val)         # JS -> Mojo, type-checked
var arr = to_js_array(b, env, List[JsF64](...)) # parametric over the traits
var items = from_js_array[JsStr](b, env, napi_val)
```

**The error-signalling convention, which every `from_js` here follows:** on a
type mismatch it BOTH sets a pending JS `TypeError` (so JavaScript sees a
typed error with a real message) AND raises a Mojo error (so execution
unwinds to the callback's `except:` block). A caller that catches the Mojo
error must NOT make further N-API calls other than returning — a pending
exception makes every subsequent call report `napi_pending_exception`.

**Both trait methods take `Bindings` first, and that is load-bearing.** An
env-only trait method used to live here, and it forced one
`dlopen(NULL)` + `dlsym` *per element* inside the parametric helpers.

Object helpers (`to_js_object_str_f64` and friends) live in
`addon/convert_ops.mojo`, not here.

---

## `JsF64`

`Float64` wrapper implementing both conversion traits.

Round-trips through `napi_create_double` / `napi_get_value_double`, so it is the exact JS numeric type.

### Fields

| field | type | description |
|---|---|---|
| `val` | `Float64` | The wrapped Mojo value. |

### `__init__`

*Overload 1 of 3.*

```mojo
def __init__(out self, val: Float64)
```

Wrap a Mojo Float64.

| argument | type | description |
|---|---|---|
| `val` | `Float64` | The value to wrap. |

*Overload 2 of 3.*

```mojo
def __init__(out self, *, copy: Self)
```

Copy-construct from another JsF64.

| argument | type | description |
|---|---|---|
| `copy` | `Self` | The value to copy. |

*Overload 3 of 3.*

```mojo
def __init__(out self, *, deinit move: Self)
```

Move-construct from another JsF64.

| argument | type | description |
|---|---|---|
| `move` | `Self` | The value to move from. |

### `to_js`

```mojo
def to_js(self, b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin]) -> NapiValue
```

Convert the wrapped value to a JS number.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |

**Returns** — The JavaScript value.

**Raises** — If the underlying N-API call fails.

### `from_js`

```mojo
def from_js(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], val: Pointer[NoneType, MutUntrackedOrigin]) -> Self
```

Read a napi_value as a JS number.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `val` | `NapiValue` | The JavaScript value. |

**Returns** — The wrapped Mojo value.

**Raises** — If val is not a JS number, after setting a pending TypeError.

---

## `JsI32`

`Int32` wrapper implementing both conversion traits.

Reads via the ECMAScript ToInt32 conversion, so an out-of-range value wraps rather than raising.

### Fields

| field | type | description |
|---|---|---|
| `val` | `Int32` | The wrapped Mojo value. |

### `__init__`

```mojo
def __init__(out self, val: Int32)
```

Wrap a Mojo Int32.

| argument | type | description |
|---|---|---|
| `val` | `Int32` | The value to wrap. |

### `to_js`

```mojo
def to_js(self, b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin]) -> NapiValue
```

Convert the wrapped value to a JS number read as Int32.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |

**Returns** — The JavaScript value.

**Raises** — If the underlying N-API call fails.

### `from_js`

```mojo
def from_js(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], val: Pointer[NoneType, MutUntrackedOrigin]) -> Self
```

Read a napi_value as a JS number read as Int32.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `val` | `NapiValue` | The JavaScript value. |

**Returns** — The wrapped Mojo value.

**Raises** — If val is not a JS number, after setting a pending TypeError.

---

## `JsBool`

`Bool` wrapper implementing both conversion traits.

Requires an actual boolean; this is not a truthiness test.

### Fields

| field | type | description |
|---|---|---|
| `val` | `Bool` | The wrapped Mojo value. |

### `__init__`

```mojo
def __init__(out self, val: Bool)
```

Wrap a Mojo Bool.

| argument | type | description |
|---|---|---|
| `val` | `Bool` | The value to wrap. |

### `to_js`

```mojo
def to_js(self, b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin]) -> NapiValue
```

Convert the wrapped value to a JS boolean.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |

**Returns** — The JavaScript value.

**Raises** — If the underlying N-API call fails.

### `from_js`

```mojo
def from_js(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], val: Pointer[NoneType, MutUntrackedOrigin]) -> Self
```

Read a napi_value as a JS boolean.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `val` | `NapiValue` | The JavaScript value. |

**Returns** — The wrapped Mojo value.

**Raises** — If val is not a JS boolean, after setting a pending TypeError.

---

## `JsStr`

`String` wrapper implementing both conversion traits.

The Mojo String owns its bytes; the JS string is built with an explicit byte length.

### Fields

| field | type | description |
|---|---|---|
| `val` | `String` | The wrapped Mojo value. |

### `__init__`

*Overload 1 of 3.*

```mojo
def __init__(out self, val: String)
```

Wrap a Mojo String.

| argument | type | description |
|---|---|---|
| `val` | `String` | The value to wrap. |

*Overload 2 of 3.*

```mojo
def __init__(out self, *, copy: Self)
```

Copy-construct from another JsStr.

| argument | type | description |
|---|---|---|
| `copy` | `Self` | The value to copy. |

*Overload 3 of 3.*

```mojo
def __init__(out self, *, deinit move: Self)
```

Move-construct from another JsStr.

| argument | type | description |
|---|---|---|
| `move` | `Self` | The value to move from. |

### `to_js`

```mojo
def to_js(self, b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin]) -> NapiValue
```

Convert the wrapped value to a JS string.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |

**Returns** — The JavaScript value.

**Raises** — If the underlying N-API call fails.

### `from_js`

```mojo
def from_js(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], val: Pointer[NoneType, MutUntrackedOrigin]) -> Self
```

Read a napi_value as a JS string.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `val` | `NapiValue` | The JavaScript value. |

**Returns** — The wrapped Mojo value.

**Raises** — If val is not a JS string, after setting a pending TypeError.

---

## `JsRaw`

`NapiValue` wrapper implementing both conversion traits.

The escape hatch: it performs no conversion and no type check, so it lets an already-obtained napi_value flow through the generic helpers unchanged.

### Fields

| field | type | description |
|---|---|---|
| `val` | `NapiValue` | The wrapped Mojo value. |

### `__init__`

```mojo
def __init__(out self, val: Pointer[NoneType, MutUntrackedOrigin])
```

Wrap a Mojo NapiValue.

| argument | type | description |
|---|---|---|
| `val` | `NapiValue` | The value to wrap. |

### `to_js`

```mojo
def to_js(self, b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin]) -> NapiValue
```

Convert the wrapped value to any JS value.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |

**Returns** — The JavaScript value.

**Raises** — If the underlying N-API call fails.

### `from_js`

```mojo
def from_js(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], val: Pointer[NoneType, MutUntrackedOrigin]) -> Self
```

Read a napi_value as any JS value.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `val` | `NapiValue` | The JavaScript value. |

**Returns** — The wrapped Mojo value.

**Raises** — Never for a type mismatch — this wrapper does no checking.

---

## Functions

### `to_js_array_f64`

```mojo
def to_js_array_f64(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], items: List[Float64]) -> NapiValue
```

Convert a `List[Float64]` to a JavaScript `Array<number>`.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `items` | `List[Float64]` | The values, in order. |

**Returns** — The JS Array.

**Raises** — If an underlying N-API call fails.

### `from_js_array_f64`

```mojo
def from_js_array_f64(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], val: Pointer[NoneType, MutUntrackedOrigin]) -> List[Float64]
```

Convert a JavaScript `Array<number>` to a `List[Float64]`.

Each element is read with `napi_get_value_double`, whose behaviour on a
**non-number element is to yield 0 rather than to fail** — so a mixed
array converts silently. Check element types yourself if that matters.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `val` | `NapiValue` | A napi_value holding a JS Array. |

**Returns** — The converted values, in order.

**Raises** — If val is not an array, after setting a pending TypeError.

### `to_js_array_str`

```mojo
def to_js_array_str(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], items: List[String]) -> NapiValue
```

Convert a `List[String]` to a JavaScript `Array<string>`.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `items` | `List[String]` | The values, in order. |

**Returns** — The JS Array.

**Raises** — If an underlying N-API call fails.

### `from_js_array_str`

```mojo
def from_js_array_str(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], val: Pointer[NoneType, MutUntrackedOrigin]) -> List[String]
```

Convert a JavaScript `Array<string>` to a `List[String]`.

Unlike the Float64 form, a non-string element does not convert silently:
`napi_get_value_string_utf8` reports a type error for it.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `val` | `NapiValue` | A napi_value holding a JS Array. |

**Returns** — The converted values, in order.

**Raises** — If val is not an array, or an element is not a string.

### `to_js_array`

```mojo
def to_js_array[T: ToJsValue & Copyable](b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], items: List[T]) -> NapiValue
```

Convert a `List[T]` to a JavaScript Array, for any `ToJsValue` type.

The generic form of `to_js_array_f64`/`_str`. Because the trait method
takes cached bindings, element conversion costs no dlsym per element.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `items` | `List[T]` | The values, in order. |

**Returns** — The JS Array.

**Raises** — If an element's conversion or an N-API call fails.

### `from_js_array`

```mojo
def from_js_array[T: FromJsValue & Copyable & Deinitable](b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], val: Pointer[NoneType, MutUntrackedOrigin]) -> List[T]
```

Convert a JavaScript Array to a `List[T]`, for any `FromJsValue` type.

Each element goes through `T.from_js`, so it inherits that type's
validation and the module's error-signalling convention.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `val` | `NapiValue` | A napi_value holding a JS Array. |

**Returns** — The converted values, in order.

**Raises** — If val is not an array, or any element fails to convert. A pending JS TypeError is set in both cases.
