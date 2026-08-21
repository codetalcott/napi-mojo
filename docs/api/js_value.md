# `js_value`

Source: [`src/napi/framework/js_value.mojo`](../../src/napi/framework/js_value.mojo)

Generic `napi_value` inspection utilities.

Type-checking helpers that inspect a value *without* attempting to read it,
which is what lets a callback validate its arguments and produce a
descriptive error instead of a conversion failure:

```mojo
var t = js_typeof(b, env, val)
if t != NAPI_TYPE_STRING:
    throw_js_error_dynamic(env, "expected string, got " + js_type_name(t))
    return NapiValue(unsafe_from_address=Int(0))
var s = JsString.from_napi_value(b, env, val)
```

Note that `napi_typeof` reports `object` for arrays, for `null`, and for
plain objects alike — mirroring JavaScript's own `typeof`. Use
`js_is_array` to separate arrays from objects, and compare against
`NAPI_TYPE_NULL` to separate `null`, which `napi_typeof` does distinguish
even though `js_type_name` renders it as `object` to match `typeof`.

---

## Functions

### `js_type_name`

```mojo
def js_type_name(t: Int32) -> String
```

Human-readable name for a napi_valuetype code.

Returns the name as JavaScript's own `typeof` would render it, which
means `NAPI_TYPE_NULL` comes back as `"object"`. Intended for error
messages.

Returns String rather than StringLiteral because StringLiteral is
parameterized on its compile-time value and cannot be returned from a
function that branches at runtime.

| argument | type | description |
|---|---|---|
| `t` | `Int32` | The napi_valuetype code, typically from `js_typeof`. |

**Returns** — The type name, or "unknown" for an unrecognized code.

### `js_typeof`

```mojo
def js_typeof(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], val: Pointer[NoneType, MutUntrackedOrigin]) -> NapiValueType
```

Report the JavaScript type of a value, like `typeof`.

Returns `NAPI_TYPE_OBJECT` for arrays and plain objects alike; use
`js_is_array` to tell them apart.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `val` | `NapiValue` | The value to inspect. |

**Returns** — One of the NAPI_TYPE_* constants in `napi.types`.

**Raises** — If napi_typeof does not return napi_ok.

### `js_is_array`

```mojo
def js_is_array(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], val: Pointer[NoneType, MutUntrackedOrigin]) -> Bool
```

Report whether a value is a JavaScript Array.

`js_typeof` cannot answer this — it returns `object` for arrays. This
wraps `napi_is_array`, which is the `Array.isArray` semantics.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `val` | `NapiValue` | The value to inspect. |

**Returns** — True if val is an Array.

**Raises** — If napi_is_array does not return napi_ok.

### `js_strict_equals`

```mojo
def js_strict_equals(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], lhs: Pointer[NoneType, MutUntrackedOrigin], rhs: Pointer[NoneType, MutUntrackedOrigin]) -> Bool
```

Compare two values with JavaScript's `===`.

No type coercion, and `NaN === NaN` is False, matching the language.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `lhs` | `NapiValue` | Left operand. |
| `rhs` | `NapiValue` | Right operand. |

**Returns** — True if the values are strictly equal.

**Raises** — If napi_strict_equals does not return napi_ok.

### `js_get_global`

```mojo
def js_get_global(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin]) -> JsObject
```

Return the environment's `globalThis` object.

The entry point for reaching built-ins that N-API exposes no direct call
for — `JSON`, `Math`, `console` — by reading them off the global.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |

**Returns** — A JsObject wrapping globalThis.

**Raises** — If napi_get_global does not return napi_ok.

### `js_is_error`

```mojo
def js_is_error(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], val: Pointer[NoneType, MutUntrackedOrigin]) -> Bool
```

Report whether a value is a JavaScript Error object.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `val` | `NapiValue` | The value to inspect. |

**Returns** — True if val is an Error.

**Raises** — If napi_is_error does not return napi_ok.

### `js_adjust_external_memory`

```mojo
def js_adjust_external_memory(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], change_in_bytes: Int64) -> Int64
```

Tell the GC about memory held outside the JS heap.

Report Mojo-owned memory that a JS object keeps alive, so V8 can factor
it into when to collect. Pass a positive delta when you allocate and a
negative one when you free; the two must balance over an object's life,
or you skew the GC's picture in one direction permanently.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `change_in_bytes` | `Int64` | Signed delta to apply. |

**Returns** — The adjusted total of externally-allocated memory.

**Raises** — If napi_adjust_external_memory does not return napi_ok.

### `js_run_script`

```mojo
def js_run_script(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], script: Pointer[NoneType, MutUntrackedOrigin]) -> NapiValue
```

Compile and run a JavaScript source string.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `script` | `NapiValue` | A napi_value holding the source text as a JS string. |

**Returns** — The completion value of the script.

**Raises** — If the script throws, or napi_run_script does not return napi_ok.
