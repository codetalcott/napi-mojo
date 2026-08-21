# `js_object`

Source: [`src/napi/framework/js_object.mojo`](../../src/napi/framework/js_object.mojo)

Ergonomic wrapper for JavaScript object values.

```mojo
var obj = JsObject.create(b, env)
var msg = JsString.create_literal(b, env, "Hello!")
obj.set_property(b, env, "message", msg.value)
return obj.value
```

**Three key flavours, and picking the wrong one is the classic bug here.**
Every accessor comes in three forms, distinguished by how the key is
spelled:

- `*_property` takes a **StringLiteral** — a static, NUL-terminated
  `.rodata` key handed straight to N-API's C-string API. Preferred for
  fixed names.
- `*_named_property` takes a heap **String**, for a key computed at
  runtime. It is converted to a length-delimited JS string key internally,
  never passed to the C-string API: a heap Mojo String has no guaranteed
  NUL terminator, so a strlen-based API would read out of bounds.
- `set`/`get`/`has`/`has_own`/`delete_prop` take a **NapiValue** key, for
  keys that came from JavaScript, and for Symbol keys. Pass a JS string
  value directly rather than round-tripping it through a Mojo String —
  that round trip loses the NUL terminator and the lookup silently fails.

---

## `JsObject`

Typed wrapper for a JavaScript object napi_value.

### Fields

| field | type | description |
|---|---|---|
| `value` | `NapiValue` | The underlying napi_value handle. Valid within the current handle scope. |

### `__init__`

```mojo
def __init__(out self, value: Pointer[NoneType, MutUntrackedOrigin])
```

Wrap an existing napi_value known to be an object.

This does not validate the handle. Prefer `create` for a fresh object.

| argument | type | description |
|---|---|---|
| `value` | `NapiValue` | The napi_value to wrap. |

### `create`

```mojo
def create(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin]) -> Self
```

Create a new, empty JavaScript object (`{}`).

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |

**Returns** — A JsObject wrapping the new napi_value.

**Raises** — If napi_create_object does not return napi_ok.

### `set_property`

```mojo
def set_property(self, b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], key: StringLiteral, val: Pointer[NoneType, MutUntrackedOrigin])
```

Set a property using a static string key.

The preferred form for fixed names — the literal is NUL-terminated
`.rodata`, so it is safe to hand to N-API's C-string API.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `key` | `StringLiteral` | The property name, as a compile-time literal. |
| `val` | `NapiValue` | The value to store. |

**Raises** — If napi_set_named_property does not return napi_ok.

### `set_named_property`

```mojo
def set_named_property(self, b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], name: String, val: Pointer[NoneType, MutUntrackedOrigin])
```

Set a property using a runtime-computed String key.

The key is converted to a JS string with an explicit byte length, not
passed to the C-string API — a heap Mojo String has no guaranteed NUL
terminator.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `name` | `String` | The property name. |
| `val` | `NapiValue` | The value to store. |

**Raises** — If the underlying N-API calls do not return napi_ok.

### `set`

```mojo
def set(self, b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], key: Pointer[NoneType, MutUntrackedOrigin], val: Pointer[NoneType, MutUntrackedOrigin])
```

Set a property using a napi_value key.

Use this for keys that came from JavaScript, and for Symbol keys.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `key` | `NapiValue` | The property key, as a JS value. |
| `val` | `NapiValue` | The value to store. |

**Raises** — If napi_set_property does not return napi_ok.

### `has`

```mojo
def has(self, b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], key: Pointer[NoneType, MutUntrackedOrigin]) -> Bool
```

Report whether a property exists, using a napi_value key.

Follows the `in` operator: inherited properties count. Use `has_own`
for own properties only.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `key` | `NapiValue` | The property key, as a JS value. |

**Returns** — True if the property is present.

**Raises** — If napi_has_property does not return napi_ok.

### `get`

```mojo
def get(self, b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], key: Pointer[NoneType, MutUntrackedOrigin]) -> NapiValue
```

Read a property using a napi_value key.

Use this for keys that came from JavaScript, and for Symbol keys.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `key` | `NapiValue` | The property key, as a JS value. |

**Returns** — The property value, or undefined if absent.

**Raises** — If napi_get_property does not return napi_ok.

### `get_property`

```mojo
def get_property(self, b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], key: StringLiteral) -> NapiValue
```

Read a property using a static string key.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `key` | `StringLiteral` | The property name, as a compile-time literal. |

**Returns** — The property value, or undefined if absent.

**Raises** — If napi_get_named_property does not return napi_ok.

### `get_named_property`

```mojo
def get_named_property(self, b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], name: String) -> NapiValue
```

Read a property using a runtime-computed String key.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `name` | `String` | The property name. |

**Returns** — The property value, or undefined if absent.

**Raises** — If the underlying N-API calls do not return napi_ok.

### `call_method`

```mojo
def call_method(self, b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], name: String, args: List[Pointer[NoneType, MutUntrackedOrigin]]) -> NapiValue
```

Look up a method by name and call it with `this` bound to self.

This is the ergonomic form of driving JavaScript from Mojo:

    var fs = host.require("fs")
    var txt = fs.call_method(b, env, "readFileSync", args)

Binding `this` matters: `JsFunction.call1` uses `undefined` as the
receiver, which silently breaks any callee that reads `this`.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `name` | `String` | The method's property name on this object. |
| `args` | `List[Pointer[NoneType, MutUntrackedOrigin]]` | The arguments, in order. May be empty. |

**Returns** — The value the method returned.

**Raises** — Error: If the property is missing or not callable, or the method threw. A JS exception raised by the method stays pending and keeps its identity.

### `has_property`

```mojo
def has_property(self, b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], key: StringLiteral) -> Bool
```

Report whether a property exists, using a static string key.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `key` | `StringLiteral` | The property name, as a compile-time literal. |

**Returns** — True if the property is present.

**Raises** — If napi_has_named_property does not return napi_ok.

### `get_opt`

```mojo
def get_opt(self, b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], key: StringLiteral) -> Optional[Pointer[NoneType, MutUntrackedOrigin]]
```

Read a property, or None when it is absent.

Distinguishes "missing" from "present and undefined", which `get_property`
cannot: it returns undefined for both. Costs an extra `has` check.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `key` | `StringLiteral` | The property name, as a compile-time literal. |

**Returns** — The value, or None if the property does not exist.

**Raises** — If the underlying N-API calls do not return napi_ok.

### `keys`

```mojo
def keys(self, b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin]) -> NapiValue
```

List the object's own enumerable string keys.

Matches `Object.keys`: own properties only, enumerable only, symbols
skipped, integer indices rendered as strings. Use `keys_filtered` for
any other combination.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |

**Returns** — A JS Array of key strings.

**Raises** — If napi_get_all_property_names does not return napi_ok.

### `keys_filtered`

```mojo
def keys_filtered(self, b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], mode: Int32, filter: Int32, conversion: Int32) -> NapiValue
```

List property names with full control over the filters.

The unrestricted form of `napi_get_all_property_names`, for the cases
`keys` does not cover — inherited properties, non-enumerables, symbols.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `mode` | `Int32` | A NAPI_KEY_* collection mode (own vs. include prototypes). |
| `filter` | `Int32` | A bitwise OR of NAPI_KEY_* attribute filters. |
| `conversion` | `Int32` | A NAPI_KEY_* index-conversion mode. |

**Returns** — A JS Array of keys.

**Raises** — If napi_get_all_property_names does not return napi_ok.

### `has_own`

```mojo
def has_own(self, b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], key: Pointer[NoneType, MutUntrackedOrigin]) -> Bool
```

Report whether the object has the property as its **own**.

Unlike `has`, inherited properties do not count.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `key` | `NapiValue` | The property key, as a JS value. |

**Returns** — True if the property is an own property.

**Raises** — If napi_has_own_property does not return napi_ok.

### `delete_prop`

```mojo
def delete_prop(self, b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], key: Pointer[NoneType, MutUntrackedOrigin]) -> Bool
```

Delete a property, using a napi_value key.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `key` | `NapiValue` | The property key, as a JS value. |

**Returns** — True if the property was deleted, or was already absent; False if it exists but is non-configurable.

**Raises** — If napi_delete_property does not return napi_ok.

### `instance_of`

```mojo
def instance_of(self, b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], constructor: Pointer[NoneType, MutUntrackedOrigin]) -> Bool
```

Test the object against a constructor, like `instanceof`.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `constructor` | `NapiValue` | The constructor function to test against. |

**Returns** — True if the object is an instance.

**Raises** — If napi_instanceof does not return napi_ok.

### `freeze`

```mojo
def freeze(self, b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin])
```

Freeze the object, like `Object.freeze`.

Existing properties become non-writable and non-configurable, and no
new ones can be added. Irreversible.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |

**Raises** — If napi_object_freeze does not return napi_ok.

### `seal`

```mojo
def seal(self, b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin])
```

Seal the object, like `Object.seal`.

No properties may be added or removed, but existing writable ones can
still be assigned — the difference from `freeze`.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |

**Raises** — If napi_object_seal does not return napi_ok.

### `prototype`

```mojo
def prototype(self, b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin]) -> NapiValue
```

Return the object's prototype, like `Object.getPrototypeOf`.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |

**Returns** — The prototype value.

**Raises** — If napi_get_prototype does not return napi_ok.
