# `js_function`

Source: [`src/napi/framework/js_function.mojo`](../../src/napi/framework/js_function.mojo)

Ergonomic wrapper for calling and creating JavaScript functions.

```mojo
var f = JsFunction(some_callback_value)
var out = f.call1(b, env, arg)
```

**`this` binding is the trap here.** `call0`/`call1`/`call2`/`call_n` all
pass `undefined` as the receiver, which silently breaks any callee that
reads `this` — a method pulled off an object and called this way loses its
object. Use `call_with` for an explicit receiver, or
`JsObject.call_method`, which looks the method up and binds `this` for you.

**Argument lifetime.** The variadic forms build an argv buffer from a
`List[NapiValue]` and keep it alive across the FFI call. An empty list
passes a genuine null argv rather than the data pointer of an empty List.

**Closure data is freed by the collector, never by a call.** A created
function may be called many times or never, so there is no "right call" to
free its data in. Pass heap data to the `finalize_cb` overload of
`create_with_data`, which frees it when the function is collected. The plain
overload frees nothing: use it only for data that outlives every function,
such as the bindings pointer.

---

## `JsFunction`

Typed wrapper for a callable JavaScript napi_value.

### Fields

| field | type | description |
|---|---|---|
| `value` | `NapiValue` | The underlying napi_value handle. Valid within the current handle scope. |

### `__init__`

```mojo
def __init__(out self, value: Pointer[NoneType, MutUntrackedOrigin])
```

Wrap an existing napi_value known to be callable.

This does not validate the handle; `js_typeof` reports
`NAPI_TYPE_FUNCTION` for callables.

| argument | type | description |
|---|---|---|
| `value` | `NapiValue` | The napi_value to wrap. |

### `call0`

```mojo
def call0(self, b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin]) -> NapiValue
```

Call the function with no arguments and `undefined` as `this`.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |

**Returns** — The function's return value.

**Raises** — If the call throws, or napi_call_function fails.

### `call1`

```mojo
def call1(self, b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], arg0: Pointer[NoneType, MutUntrackedOrigin]) -> NapiValue
```

Call the function with one argument and `undefined` as `this`.

Use `call_with` if the callee reads `this`.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |

**Returns** — The function's return value.

**Raises** — If the call throws, or napi_call_function fails.

### `call2`

```mojo
def call2(self, b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], arg0: Pointer[NoneType, MutUntrackedOrigin], arg1: Pointer[NoneType, MutUntrackedOrigin]) -> NapiValue
```

Call the function with two arguments and `undefined` as `this`.

Use `call_with` if the callee reads `this`.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `arg1` | `NapiValue` | The first argument. |

**Returns** — The function's return value.

**Raises** — If the call throws, or napi_call_function fails.

### `call_n`

```mojo
def call_n(self, b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], args: List[Pointer[NoneType, MutUntrackedOrigin]]) -> NapiValue
```

Call the function with N arguments and `undefined` as `this`.

`call0`/`call1`/`call2` remain the allocation-free fast paths; reach
for this one when the argument count is only known at runtime.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `args` | `List[Pointer[NoneType, MutUntrackedOrigin]]` | The arguments, in order. May be empty. |

**Returns** — The value the function returned.

**Raises** — Error: If the call fails, or the callee threw. A JS exception raised by the callee stays pending and keeps its identity — do not throw a replacement error over it.

### `call_with`

```mojo
def call_with(self, b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], recv: Pointer[NoneType, MutUntrackedOrigin], args: List[Pointer[NoneType, MutUntrackedOrigin]]) -> NapiValue
```

Call the function with N arguments and an explicit `this`.

Method calls need this: `obj.method(...)` only behaves correctly when
`recv` is `obj`. `JsObject.call_method` is the ergonomic wrapper.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `recv` | `NapiValue` | The `this` value for the call. |
| `args` | `List[Pointer[NoneType, MutUntrackedOrigin]]` | The arguments, in order. May be empty. |

**Returns** — The value the function returned.

**Raises** — Error: If the call fails, or the callee threw. A JS exception raised by the callee stays pending and keeps its identity — do not throw a replacement error over it.

### `create`

```mojo
def create(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], name: StringLiteral, cb_ptr: Pointer[NoneType, MutAnyOrigin]) -> Self
```

Create a JS function backed by a Mojo callback.

The callback must have the napi_callback signature and must not let a
Mojo exception escape into C.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `name` | `StringLiteral` | The function's name, as a compile-time literal. |
| `cb_ptr` | `Pointer[NoneType, MutAnyOrigin]` | The callback, via `fn_ptr(...)`. |

**Returns** — A JsFunction wrapping the new function.

**Raises** — If napi_create_function does not return napi_ok.

### `create_with_data`

*Overload 1 of 2.*

```mojo
def create_with_data(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], name: StringLiteral, cb_ptr: Pointer[NoneType, MutAnyOrigin], data: Pointer[NoneType, MutAnyOrigin]) -> Self
```

Create a JS function carrying an arbitrary data pointer.

The callback retrieves the pointer with `CbArgs.get_data`. This is the
closure mechanism for plain functions.

**The data is never freed for you.** For heap data, use the
`finalize_cb` overload, which frees it when the function is collected
— never free it when the callback fires, which may be never or many
times. For a promise continuation, use `JsPromise.on_settled`.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `name` | `StringLiteral` | The function's name, as a compile-time literal. |
| `cb_ptr` | `Pointer[NoneType, MutAnyOrigin]` | The callback, via `fn_ptr(...)`. |
| `data` | `Pointer[NoneType, MutAnyOrigin]` | Pointer handed to the callback on every invocation. |

**Returns** — A JsFunction wrapping the new function.

**Raises** — If napi_create_function does not return napi_ok.

*Overload 2 of 2.*

```mojo
def create_with_data(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], name: StringLiteral, cb_ptr: Pointer[NoneType, MutAnyOrigin], data: Pointer[NoneType, MutAnyOrigin], finalize_cb: Pointer[NoneType, MutAnyOrigin]) -> Self
```

Create a JS function whose closure data the collector frees.

The closure mechanism for heap data. The callback retrieves `data`
with `CbArgs.get_data`, on every call, for as long as the function is
reachable; `finalize_cb(env, data, null)` runs once the function has
been collected. Nothing is freed on the call path, so a function that
is called many times — or never — is equally safe.

`data` is ADOPTED on every path: if the function cannot be created or
the finalizer cannot be attached, `finalize_cb` runs before this
raises. Never free `data` yourself after passing it.

The finalizer runs on the main thread after collection. Free memory
there; do not call into JavaScript.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `name` | `StringLiteral` | The function's name, as a compile-time literal. |
| `cb_ptr` | `Pointer[NoneType, MutAnyOrigin]` | The callback, via `fn_ptr(...)`. |
| `data` | `Pointer[NoneType, MutAnyOrigin]` | Pointer handed to the callback on every invocation. |
| `finalize_cb` | `Pointer[NoneType, MutAnyOrigin]` | A `def(env, data, hint)` that frees `data`, via     `fn_ptr(...)`. May be null, making this the plain overload. |

**Returns** — A JsFunction wrapping the new function.

**Raises** — If the function could not be created or the finalizer attached. `data` has been finalized either way.

### `create_named`

*Overload 1 of 2.*

```mojo
def create_named(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], name: String, length: Int, cb_ptr: Pointer[NoneType, MutAnyOrigin]) -> Self
```

Create a JS function with a runtime name and declared arity.

The String overload of `create`, for a name computed at runtime. The
`data_ptr` overload additionally carries closure data and frees none
of it, like the plain `create_with_data`; tie heap data to the result
with `JsObject(fn.value).add_finalizer(...)`.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `name` | `String` | The function's name. |
| `length` | `Int` | The value reported as the function's `length`. |
| `cb_ptr` | `Pointer[NoneType, MutAnyOrigin]` | The callback, via `fn_ptr(...)`. |

**Returns** — A JsFunction wrapping the new function.

**Raises** — If napi_create_function does not return napi_ok.

*Overload 2 of 2.*

```mojo
def create_named(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], name: String, length: Int, cb_ptr: Pointer[NoneType, MutAnyOrigin], data_ptr: Pointer[NoneType, MutAnyOrigin]) -> Self
```

Create a JS function with a runtime name and declared arity.

The String overload of `create`, for a name computed at runtime. The
`data_ptr` overload additionally carries closure data and frees none
of it, like the plain `create_with_data`; tie heap data to the result
with `JsObject(fn.value).add_finalizer(...)`.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `name` | `String` | The function's name. |
| `length` | `Int` | The value reported as the function's `length`. |
| `cb_ptr` | `Pointer[NoneType, MutAnyOrigin]` | The callback, via `fn_ptr(...)`. |
| `data_ptr` | `Pointer[NoneType, MutAnyOrigin]` | Closure data (data overload only). |

**Returns** — A JsFunction wrapping the new function.

**Raises** — If napi_create_function does not return napi_ok.
