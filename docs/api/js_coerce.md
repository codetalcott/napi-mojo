# `js_coerce`

Source: [`src/napi/framework/js_coerce.mojo`](../../src/napi/framework/js_coerce.mojo)

---

## Functions

### `js_coerce_to_bool`

```mojo
def js_coerce_to_bool(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], val: Pointer[NoneType, MutUntrackedOrigin]) -> NapiValue
```

Equivalent to Boolean(value) in JavaScript.

### `js_coerce_to_number`

```mojo
def js_coerce_to_number(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], val: Pointer[NoneType, MutUntrackedOrigin]) -> NapiValue
```

Equivalent to Number(value) in JavaScript. Throws TypeError on Symbol values.

### `js_coerce_to_string`

```mojo
def js_coerce_to_string(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], val: Pointer[NoneType, MutUntrackedOrigin]) -> NapiValue
```

Equivalent to String(value) in JavaScript. Throws TypeError on Symbol values.

### `js_coerce_to_object`

```mojo
def js_coerce_to_object(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], val: Pointer[NoneType, MutUntrackedOrigin]) -> NapiValue
```

Equivalent to Object(value) in JavaScript. Wraps primitives in their object wrappers.
