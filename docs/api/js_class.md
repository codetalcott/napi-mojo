# `js_class`

Source: [`src/napi/framework/js_class.mojo`](../../src/napi/framework/js_class.mojo)

Registering Mojo-backed JavaScript classes.

Call `define_class` first, then add members to the returned constructor,
one property at a time:

```mojo
var ctor = define_class(b, env, "Counter", fn_ptr(counter_ctor))
register_instance_method(b, env, ctor, "increment", fn_ptr(inc_fn))
register_getter(b, env, ctor, "value", fn_ptr(value_getter))
```

**Instance members go on the PROTOTYPE, not the constructor** — these
helpers retrieve `constructor.prototype` for you. Static members go on the
constructor itself.

**Wrapping native state must be type-tagged, and this is a memory-safety
rule, not a nicety.** `napi_unwrap` alone only proves "some native pointer
is wrapped here". A method borrowed onto a foreign wrapped instance —
`Counter.prototype.increment.call(someAnimal)` — would reinterpret an
`AnimalData` as a `CounterData`. That is memory corruption reachable from
pure JavaScript. So wrap with `wrap_native` (which tags) and unwrap with
the `NapiTypeTag`-taking overloads of `unwrap_native` (which verify).

**An object can carry exactly ONE tag**: `napi_type_tag_object` fails on a
second. Inheritance is therefore an accept-set at the unwrap site — an
Animal method checks for the Animal OR Dog tag with
`check_object_type_tag`, then uses the untagged unwrap, which is sound only
because `DogData` is layout-compatible with `AnimalData`. The untagged
overloads exist for exactly that pattern and are otherwise unverified: reach
for a tagged one unless you are implementing an accept-set.

---

## Functions

### `define_class`

*Overload 1 of 2.*

```mojo
def define_class(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], name: StringLiteral, constructor_ptr: Pointer[NoneType, MutAnyOrigin]) -> NapiValue
```

Define a JavaScript class backed by a Mojo constructor callback.

Registers the class with no properties; add members afterwards with the
`register_*` helpers. The `data_ptr` overload attaches callback data,
which for a napi-mojo addon is the cached bindings pointer.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `name` | `StringLiteral` | The class name, as a compile-time literal. |
| `constructor_ptr` | `Pointer[NoneType, MutAnyOrigin]` | The constructor callback, via `fn_ptr(...)`. |

**Returns** — The constructor napi_value — pass it to the register_* helpers.

**Raises** — If napi_define_class does not return napi_ok.

*Overload 2 of 2.*

```mojo
def define_class(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], name: StringLiteral, constructor_ptr: Pointer[NoneType, MutAnyOrigin], data_ptr: Pointer[NoneType, MutAnyOrigin]) -> NapiValue
```

Define a JavaScript class backed by a Mojo constructor callback.

Registers the class with no properties; add members afterwards with the
`register_*` helpers. The `data_ptr` overload attaches callback data,
which for a napi-mojo addon is the cached bindings pointer.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `name` | `StringLiteral` | The class name, as a compile-time literal. |
| `constructor_ptr` | `Pointer[NoneType, MutAnyOrigin]` | The constructor callback, via `fn_ptr(...)`. |
| `data_ptr` | `Pointer[NoneType, MutAnyOrigin]` | Callback data for every member (data overload only). |

**Returns** — The constructor napi_value — pass it to the register_* helpers.

**Raises** — If napi_define_class does not return napi_ok.

### `register_instance_method`

```mojo
def register_instance_method(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], constructor: Pointer[NoneType, MutUntrackedOrigin], name: StringLiteral, method_ptr: Pointer[NoneType, MutAnyOrigin])
```

Add a method to the class prototype.

On the prototype, so every instance shares it.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `constructor` | `NapiValue` | The class constructor from `define_class`. |
| `name` | `StringLiteral` | The member name, as a compile-time literal. |
| `method_ptr` | `Pointer[NoneType, MutAnyOrigin]` | The callback, via `fn_ptr(...)`. |

**Raises** — If reading the prototype or defining the property fails.

### `register_getter`

```mojo
def register_getter(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], constructor: Pointer[NoneType, MutUntrackedOrigin], name: StringLiteral, getter_ptr: Pointer[NoneType, MutAnyOrigin])
```

Add a read-only accessor to the class prototype.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `constructor` | `NapiValue` | The class constructor from `define_class`. |
| `name` | `StringLiteral` | The member name, as a compile-time literal. |
| `getter_ptr` | `Pointer[NoneType, MutAnyOrigin]` | The getter callback, via `fn_ptr(...)`. |

**Raises** — If reading the prototype or defining the property fails.

### `register_getter_setter`

```mojo
def register_getter_setter(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], constructor: Pointer[NoneType, MutUntrackedOrigin], name: StringLiteral, getter_ptr: Pointer[NoneType, MutAnyOrigin], setter_ptr: Pointer[NoneType, MutAnyOrigin])
```

Add a read/write accessor to the class prototype.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `constructor` | `NapiValue` | The class constructor from `define_class`. |
| `name` | `StringLiteral` | The member name, as a compile-time literal. |
| `getter_ptr` | `Pointer[NoneType, MutAnyOrigin]` | The getter callback, via `fn_ptr(...)`. |
| `setter_ptr` | `Pointer[NoneType, MutAnyOrigin]` | The setter callback, via `fn_ptr(...)`. |

**Raises** — If reading the prototype or defining the property fails.

### `register_static_method`

```mojo
def register_static_method(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], constructor: Pointer[NoneType, MutUntrackedOrigin], name: StringLiteral, method_ptr: Pointer[NoneType, MutAnyOrigin])
```

Add a static method to the constructor itself.

On the constructor, not the prototype — so it is `Counter.isCounter(x)`,
not an instance member, and it receives no wrapped instance state.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `constructor` | `NapiValue` | The class constructor from `define_class`. |
| `name` | `StringLiteral` | The member name, as a compile-time literal. |
| `method_ptr` | `Pointer[NoneType, MutAnyOrigin]` | The callback, via `fn_ptr(...)`. |

**Raises** — If napi_define_properties does not return napi_ok.

### `register_static_getter`

```mojo
def register_static_getter(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], constructor: Pointer[NoneType, MutUntrackedOrigin], name: StringLiteral, getter_ptr: Pointer[NoneType, MutAnyOrigin])
```

Add a read-only static accessor to the constructor itself.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `constructor` | `NapiValue` | The class constructor from `define_class`. |
| `name` | `StringLiteral` | The member name, as a compile-time literal. |
| `getter_ptr` | `Pointer[NoneType, MutAnyOrigin]` | The getter callback, via `fn_ptr(...)`. |

**Raises** — If napi_define_properties does not return napi_ok.

### `set_class_prototype`

```mojo
def set_class_prototype(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], child_ctor: Pointer[NoneType, MutUntrackedOrigin], parent_ctor: Pointer[NoneType, MutUntrackedOrigin])
```

Chain one class's prototype to another's, giving JS inheritance.

Sets `child.prototype.__proto__ = parent.prototype`, so instances of the
child inherit the parent's prototype members.

Note this does NOT let an object carry both classes' type tags — a second
tag fails. Handle the subclass at the unwrap site with an accept-set; see
the module docstring.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `child_ctor` | `NapiValue` | The subclass constructor. |
| `parent_ctor` | `NapiValue` | The superclass constructor. |

**Raises** — If reading either prototype or setting it fails.

### `register_static_getter_setter`

```mojo
def register_static_getter_setter(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], constructor: Pointer[NoneType, MutUntrackedOrigin], name: StringLiteral, getter_ptr: Pointer[NoneType, MutAnyOrigin], setter_ptr: Pointer[NoneType, MutAnyOrigin])
```

Add a read/write static accessor to the constructor itself.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `constructor` | `NapiValue` | The class constructor from `define_class`. |
| `name` | `StringLiteral` | The member name, as a compile-time literal. |
| `getter_ptr` | `Pointer[NoneType, MutAnyOrigin]` | The getter callback, via `fn_ptr(...)`. |
| `setter_ptr` | `Pointer[NoneType, MutAnyOrigin]` | The setter callback, via `fn_ptr(...)`. |

**Raises** — If napi_define_properties does not return napi_ok.

### `type_tag_object`

```mojo
def type_tag_object(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], value: Pointer[NoneType, MutUntrackedOrigin], tag: NapiTypeTag)
```

Stamp an object with a 128-bit type tag (N-API v8).

An object can carry exactly ONE tag — `napi_type_tag_object` fails with
`napi_invalid_arg` if the object is already tagged. Inheritance is
therefore expressed as an accept-set of tags at the unwrap site, never by
tagging an object twice.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `value` | `NapiValue` | The object to tag. |
| `tag` | `NapiTypeTag` | The class's fixed 128-bit tag. |

**Raises** — If the object is already tagged, or is not an object.

### `check_object_type_tag`

```mojo
def check_object_type_tag(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], value: Pointer[NoneType, MutUntrackedOrigin], tag: NapiTypeTag) -> Bool
```

Report whether an object carries exactly this type tag.

False for an untagged object and for one tagged with a different tag.
This is the accept-set primitive: a superclass method checks for its own
tag OR each subclass tag, then uses an untagged unwrap.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `value` | `NapiValue` | The object to inspect. |
| `tag` | `NapiTypeTag` | The tag to test for. |

**Returns** — True if the object carries this exact tag.

**Raises** — `napi_object_expected` if value is not an object.

### `wrap_native`

```mojo
def wrap_native(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], this_val: Pointer[NoneType, MutUntrackedOrigin], data_ptr: Pointer[NoneType, MutAnyOrigin], finalize_ptr: Pointer[NoneType, MutAnyOrigin], tag: NapiTypeTag)
```

Attach a native pointer to `this` and type-tag it.

The tag is what makes the tagged `unwrap_native` safe. Without it,
`napi_unwrap` proves only that *some* native pointer is wrapped, so a
method borrowed onto a foreign instance would reinterpret the wrong
struct — memory corruption reachable from pure JavaScript.

**Ownership of `data_ptr`:** on success the finalizer owns it. On raise
the CALLER still owns it and must free it. The wrap happens first, and if
tagging then fails the wrap is removed again (`napi_remove_wrap`) before
raising, so the caller's cleanup cannot double-free against the finalizer.

The finalizer's `finalize_hint` is the cached-bindings pointer, which
lives for the whole env lifetime, so a finalizer needing N-API can recover
them with `bindings_from_context(hint)`.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `this_val` | `NapiValue` | The instance to wrap onto, from `CbArgs.get_this`. |
| `data_ptr` | `Pointer[NoneType, MutAnyOrigin]` | The heap-allocated native state. |
| `finalize_ptr` | `Pointer[NoneType, MutAnyOrigin]` | The finalizer callback, which frees data_ptr. |
| `tag` | `NapiTypeTag` | The class's fixed 128-bit tag. |

**Raises** — If wrapping or tagging fails; on a tagging failure the wrap is removed first and data_ptr remains the caller's to free.

### `unwrap_native`

*Overload 1 of 2.*

```mojo
def unwrap_native[T: AnyType](b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], info: Pointer[NoneType, MutUntrackedOrigin]) -> Pointer[T, MutAnyOrigin]
```

Retrieve the native state wrapped on the callback's `this`.

**Untagged, and therefore unchecked.** It verifies only that
something is wrapped. Use it ONLY to implement an accept-set, after
`check_object_type_tag` has confirmed one of the acceptable tags — the
inheritance pattern described in the module docstring. Anywhere else,
use the `tag`-taking overload.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `info` | `NapiValue` | The callback info handle. |

**Returns** — A pointer to the wrapped T.

**Raises** — If nothing is wrapped on `this`.

*Overload 2 of 2.*

```mojo
def unwrap_native[T: AnyType](b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], info: Pointer[NoneType, MutUntrackedOrigin], tag: NapiTypeTag) -> Pointer[T, MutAnyOrigin]
```

Retrieve the native state wrapped on `this`, checking its type tag.

Verifies the type tag first, so a method borrowed onto a foreign
wrapped instance throws a JS TypeError instead of reinterpreting the
wrong struct. **This is the overload to use.**

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `info` | `NapiValue` | The callback info handle. |
| `tag` | `NapiTypeTag` | The class's fixed 128-bit tag. |

**Returns** — A pointer to the wrapped T.

**Raises** — On a tag mismatch, after setting a pending JS TypeError; or if nothing is wrapped.

### `unwrap_native_from_this`

*Overload 1 of 2.*

```mojo
def unwrap_native_from_this[T: AnyType](b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], this_val: Pointer[NoneType, MutUntrackedOrigin]) -> Pointer[T, MutAnyOrigin]
```

Retrieve the native state wrapped on an explicit object.

The form to use when you already hold the instance rather than the
callback info.

**Untagged, and therefore unchecked.** It verifies only that
something is wrapped. Use it ONLY to implement an accept-set, after
`check_object_type_tag` has confirmed one of the acceptable tags — the
inheritance pattern described in the module docstring. Anywhere else,
use the `tag`-taking overload.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `this_val` | `NapiValue` | The wrapped instance. |

**Returns** — A pointer to the wrapped T.

**Raises** — If nothing is wrapped on the object.

*Overload 2 of 2.*

```mojo
def unwrap_native_from_this[T: AnyType](b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], this_val: Pointer[NoneType, MutUntrackedOrigin], tag: NapiTypeTag) -> Pointer[T, MutAnyOrigin]
```

Retrieve native state from an explicit object, checking its type tag.

Verifies the type tag first, so a method borrowed onto a foreign
wrapped instance throws a JS TypeError instead of reinterpreting the
wrong struct. **This is the overload to use.**

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `this_val` | `NapiValue` | The wrapped instance. |
| `tag` | `NapiTypeTag` | The class's fixed 128-bit tag. |

**Returns** — A pointer to the wrapped T.

**Raises** — On a tag mismatch, after setting a pending JS TypeError; or if nothing is wrapped.
