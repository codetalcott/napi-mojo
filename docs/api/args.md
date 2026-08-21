# `args`

Source: [`src/napi/framework/args.mojo`](../../src/napi/framework/args.mojo)

Reading a callback's arguments, receiver, and cached bindings.

`CbArgs` wraps `napi_get_cb_info`, which is the single call that unpacks
everything a `napi_callback` was invoked with. The first thing almost every
callback does is fetch its cached bindings:

```mojo
# inside a napi_callback — see examples/hello-addon.mojo for the whole file
try:
    var r = CbArgs.get_bindings_and_one(env, info)
    return JsString.create(r.b, env, "hi").value
except:
    throw_js_error(env, "greet failed")
    return NapiValue(unsafe_from_address=Int(0))
```

(The example shows the body rather than the `def` line on purpose:
scripts/check-compile-coverage.mjs scans for public declarations by regex, and
a `def` inside a doc fence reads to it as an uncovered method — the same
reason js_host.mojo writes its example that way.)

**Prefer the fused `get_bindings_and_*` accessors.** They make ONE
`napi_get_cb_info` call and return both the bindings and the arguments;
calling `get_bindings` and then `get_one` makes two.

**Overload pairs.** Most accessors exist twice — taking cached `Bindings`,
and env-only. The env-only forms resolve `napi_get_cb_info` per call and
exist for contexts where bindings are genuinely unavailable: async complete
callbacks, ThreadsafeFunction callbacks, finalizers, and `except:` blocks
reached because bindings retrieval itself failed. Everywhere else, pass
Bindings.

**Arity is checked, not padded.** `get_one`/`get_two`/`get_three`/`get_four`
raise when the caller supplied fewer arguments. For a variadic callback,
use `argc` to size a buffer and `get_argv` to fill it — N-API pads argv
with `undefined` and drops extras, so compare `get_argv`'s return value
against your buffer size to detect either case.

---

## `BindingsAndOne`

Result of a fused accessor: bindings plus one argument.

Returned by the matching `CbArgs.get_bindings_*` method, which fills
it from a single `napi_get_cb_info` call.

### Fields

| field | type | description |
|---|---|---|
| `b` | `Bindings` | The cached N-API bindings for this environment. |
| `arg0` | `NapiValue` | The first callback argument. |

### `__init__`

```mojo
def __init__(out self, b: Pointer[NapiBindings, MutUntrackedOrigin], arg0: Pointer[NoneType, MutUntrackedOrigin])
```

Build the result directly.

Normally produced by the matching `CbArgs.get_bindings_*` method
rather than constructed by hand.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | The cached N-API bindings for this environment. |
| `arg0` | `NapiValue` | The first callback argument. |

---

## `BindingsAndTwo`

Result of a fused accessor: bindings plus two arguments.

Returned by the matching `CbArgs.get_bindings_*` method, which fills
it from a single `napi_get_cb_info` call.

### Fields

| field | type | description |
|---|---|---|
| `b` | `Bindings` | The cached N-API bindings for this environment. |
| `arg0` | `NapiValue` | The first callback argument. |
| `arg1` | `NapiValue` | The second callback argument. |

### `__init__`

```mojo
def __init__(out self, b: Pointer[NapiBindings, MutUntrackedOrigin], arg0: Pointer[NoneType, MutUntrackedOrigin], arg1: Pointer[NoneType, MutUntrackedOrigin])
```

Build the result directly.

Normally produced by the matching `CbArgs.get_bindings_*` method
rather than constructed by hand.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | The cached N-API bindings for this environment. |
| `arg0` | `NapiValue` | The first callback argument. |
| `arg1` | `NapiValue` | The second callback argument. |

---

## `BindingsAndThree`

Result of a fused accessor: bindings plus three arguments.

Returned by the matching `CbArgs.get_bindings_*` method, which fills
it from a single `napi_get_cb_info` call.

### Fields

| field | type | description |
|---|---|---|
| `b` | `Bindings` | The cached N-API bindings for this environment. |
| `arg0` | `NapiValue` | The first callback argument. |
| `arg1` | `NapiValue` | The second callback argument. |
| `arg2` | `NapiValue` | The third callback argument. |

### `__init__`

```mojo
def __init__(out self, b: Pointer[NapiBindings, MutUntrackedOrigin], arg0: Pointer[NoneType, MutUntrackedOrigin], arg1: Pointer[NoneType, MutUntrackedOrigin], arg2: Pointer[NoneType, MutUntrackedOrigin])
```

Build the result directly.

Normally produced by the matching `CbArgs.get_bindings_*` method
rather than constructed by hand.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | The cached N-API bindings for this environment. |
| `arg0` | `NapiValue` | The first callback argument. |
| `arg1` | `NapiValue` | The second callback argument. |
| `arg2` | `NapiValue` | The third callback argument. |

---

## `BindingsAndThis`

Result of a fused accessor: bindings plus the receiver.

Returned by the matching `CbArgs.get_bindings_*` method, which fills
it from a single `napi_get_cb_info` call.

### Fields

| field | type | description |
|---|---|---|
| `b` | `Bindings` | The cached N-API bindings for this environment. |
| `this_val` | `NapiValue` | The callback's receiver (`this`). |

### `__init__`

```mojo
def __init__(out self, b: Pointer[NapiBindings, MutUntrackedOrigin], this_val: Pointer[NoneType, MutUntrackedOrigin])
```

Build the result directly.

Normally produced by the matching `CbArgs.get_bindings_*` method
rather than constructed by hand.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | The cached N-API bindings for this environment. |
| `this_val` | `NapiValue` | The callback's receiver (`this`). |

---

## `BindingsThisAndOne`

Result of a fused accessor: bindings, the receiver, and one argument.

Returned by the matching `CbArgs.get_bindings_*` method, which fills
it from a single `napi_get_cb_info` call.

### Fields

| field | type | description |
|---|---|---|
| `b` | `Bindings` | The cached N-API bindings for this environment. |
| `this_val` | `NapiValue` | The callback's receiver (`this`). |
| `arg0` | `NapiValue` | The first callback argument. |

### `__init__`

```mojo
def __init__(out self, b: Pointer[NapiBindings, MutUntrackedOrigin], this_val: Pointer[NoneType, MutUntrackedOrigin], arg0: Pointer[NoneType, MutUntrackedOrigin])
```

Build the result directly.

Normally produced by the matching `CbArgs.get_bindings_*` method
rather than constructed by hand.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | The cached N-API bindings for this environment. |
| `this_val` | `NapiValue` | The callback's receiver (`this`). |
| `arg0` | `NapiValue` | The first callback argument. |

---

## `CbArgs`

Static accessors over `napi_get_cb_info`.

Never instantiated — a namespace for the callback-unpacking helpers.
See the module docstring for the overload and arity rules.

### `get_one`

*Overload 1 of 2.*

```mojo
def get_one(env: Pointer[NoneType, MutUntrackedOrigin], info: Pointer[NoneType, MutUntrackedOrigin]) -> NapiValue
```

Extract exactly one callback argument.

Raises when the caller supplied fewer than 1 — arguments are checked,
not silently padded with undefined.

Exists as a Bindings overload and an env-only overload; prefer the
Bindings form outside finalizer/TSFN/except contexts.

| argument | type | description |
|---|---|---|
| `env` | `NapiEnv` | The N-API environment. |
| `info` | `NapiValue` | The callback info handle. |

**Returns** — The argument.

**Raises** — If fewer than 1 arguments were supplied, or napi_get_cb_info fails.

*Overload 2 of 2.*

```mojo
def get_one(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], info: Pointer[NoneType, MutUntrackedOrigin]) -> NapiValue
```

Extract exactly one callback argument.

Raises when the caller supplied fewer than 1 — arguments are checked,
not silently padded with undefined.

Exists as a Bindings overload and an env-only overload; prefer the
Bindings form outside finalizer/TSFN/except contexts.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings (Bindings overload only). |
| `env` | `NapiEnv` | The N-API environment. |
| `info` | `NapiValue` | The callback info handle. |

**Returns** — The argument.

**Raises** — If fewer than 1 arguments were supplied, or napi_get_cb_info fails.

### `get_two`

*Overload 1 of 2.*

```mojo
def get_two(env: Pointer[NoneType, MutUntrackedOrigin], info: Pointer[NoneType, MutUntrackedOrigin]) -> Array[Pointer[NoneType, MutUntrackedOrigin], Int(2)]
```

Extract exactly two callback arguments.

Raises when the caller supplied fewer than 2 — arguments are checked,
not silently padded with undefined.

Exists as a Bindings overload and an env-only overload; prefer the
Bindings form outside finalizer/TSFN/except contexts.

| argument | type | description |
|---|---|---|
| `env` | `NapiEnv` | The N-API environment. |
| `info` | `NapiValue` | The callback info handle. |

**Returns** — A tuple of the two arguments, in order.

**Raises** — If fewer than 2 arguments were supplied, or napi_get_cb_info fails.

*Overload 2 of 2.*

```mojo
def get_two(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], info: Pointer[NoneType, MutUntrackedOrigin]) -> Array[Pointer[NoneType, MutUntrackedOrigin], Int(2)]
```

Extract exactly two callback arguments.

Raises when the caller supplied fewer than 2 — arguments are checked,
not silently padded with undefined.

Exists as a Bindings overload and an env-only overload; prefer the
Bindings form outside finalizer/TSFN/except contexts.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings (Bindings overload only). |
| `env` | `NapiEnv` | The N-API environment. |
| `info` | `NapiValue` | The callback info handle. |

**Returns** — A tuple of the two arguments, in order.

**Raises** — If fewer than 2 arguments were supplied, or napi_get_cb_info fails.

### `get_three`

```mojo
def get_three(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], info: Pointer[NoneType, MutUntrackedOrigin]) -> Array[Pointer[NoneType, MutUntrackedOrigin], Int(3)]
```

Extract exactly three callback arguments.

Raises when the caller supplied fewer than 3 — arguments are checked,
not silently padded with undefined.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings (Bindings overload only). |
| `env` | `NapiEnv` | The N-API environment. |
| `info` | `NapiValue` | The callback info handle. |

**Returns** — A tuple of the three arguments, in order.

**Raises** — If fewer than 3 arguments were supplied, or napi_get_cb_info fails.

### `get_four`

```mojo
def get_four(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], info: Pointer[NoneType, MutUntrackedOrigin]) -> Array[Pointer[NoneType, MutUntrackedOrigin], Int(4)]
```

Extract exactly four callback arguments.

Raises when the caller supplied fewer than 4 — arguments are checked,
not silently padded with undefined.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings (Bindings overload only). |
| `env` | `NapiEnv` | The N-API environment. |
| `info` | `NapiValue` | The callback info handle. |

**Returns** — A tuple of the four arguments, in order.

**Raises** — If fewer than 4 arguments were supplied, or napi_get_cb_info fails.

### `get_this`

*Overload 1 of 2.*

```mojo
def get_this(env: Pointer[NoneType, MutUntrackedOrigin], info: Pointer[NoneType, MutUntrackedOrigin]) -> NapiValue
```

Return the callback's receiver (`this`).

The value a constructor wraps native state onto, and what an instance
method unwraps from.

Exists as a Bindings overload and an env-only overload; prefer the
Bindings form outside finalizer/TSFN/except contexts.

| argument | type | description |
|---|---|---|
| `env` | `NapiEnv` | The N-API environment. |
| `info` | `NapiValue` | The callback info handle. |

**Returns** — The receiver.

**Raises** — If napi_get_cb_info does not return napi_ok.

*Overload 2 of 2.*

```mojo
def get_this(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], info: Pointer[NoneType, MutUntrackedOrigin]) -> NapiValue
```

Return the callback's receiver (`this`).

The value a constructor wraps native state onto, and what an instance
method unwraps from.

Exists as a Bindings overload and an env-only overload; prefer the
Bindings form outside finalizer/TSFN/except contexts.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings (Bindings overload only). |
| `env` | `NapiEnv` | The N-API environment. |
| `info` | `NapiValue` | The callback info handle. |

**Returns** — The receiver.

**Raises** — If napi_get_cb_info does not return napi_ok.

### `get_this_and_one`

*Overload 1 of 2.*

```mojo
def get_this_and_one(env: Pointer[NoneType, MutUntrackedOrigin], info: Pointer[NoneType, MutUntrackedOrigin]) -> Array[Pointer[NoneType, MutUntrackedOrigin], Int(2)]
```

Return the receiver and exactly one argument.

One `napi_get_cb_info` call — the shape a setter or a single-argument
instance method wants.

Exists as a Bindings overload and an env-only overload; prefer the
Bindings form outside finalizer/TSFN/except contexts.

| argument | type | description |
|---|---|---|
| `env` | `NapiEnv` | The N-API environment. |
| `info` | `NapiValue` | The callback info handle. |

**Returns** — A tuple of (this, arg0).

**Raises** — If fewer than one argument was supplied, or napi_get_cb_info fails.

*Overload 2 of 2.*

```mojo
def get_this_and_one(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], info: Pointer[NoneType, MutUntrackedOrigin]) -> Array[Pointer[NoneType, MutUntrackedOrigin], Int(2)]
```

Return the receiver and exactly one argument.

One `napi_get_cb_info` call — the shape a setter or a single-argument
instance method wants.

Exists as a Bindings overload and an env-only overload; prefer the
Bindings form outside finalizer/TSFN/except contexts.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings (Bindings overload only). |
| `env` | `NapiEnv` | The N-API environment. |
| `info` | `NapiValue` | The callback info handle. |

**Returns** — A tuple of (this, arg0).

**Raises** — If fewer than one argument was supplied, or napi_get_cb_info fails.

### `argc`

*Overload 1 of 2.*

```mojo
def argc(env: Pointer[NoneType, MutUntrackedOrigin], info: Pointer[NoneType, MutUntrackedOrigin]) -> UInt
```

Return how many arguments the caller actually supplied.

Use it to size a buffer before `get_argv` for a variadic callback.

Exists as a Bindings overload and an env-only overload; prefer the
Bindings form outside finalizer/TSFN/except contexts.

| argument | type | description |
|---|---|---|
| `env` | `NapiEnv` | The N-API environment. |
| `info` | `NapiValue` | The callback info handle. |

**Returns** — The supplied argument count.

**Raises** — If napi_get_cb_info does not return napi_ok.

*Overload 2 of 2.*

```mojo
def argc(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], info: Pointer[NoneType, MutUntrackedOrigin]) -> UInt
```

Return how many arguments the caller actually supplied.

Use it to size a buffer before `get_argv` for a variadic callback.

Exists as a Bindings overload and an env-only overload; prefer the
Bindings form outside finalizer/TSFN/except contexts.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings (Bindings overload only). |
| `env` | `NapiEnv` | The N-API environment. |
| `info` | `NapiValue` | The callback info handle. |

**Returns** — The supplied argument count.

**Raises** — If napi_get_cb_info does not return napi_ok.

### `get_argv`

*Overload 1 of 2.*

```mojo
def get_argv(env: Pointer[NoneType, MutUntrackedOrigin], info: Pointer[NoneType, MutUntrackedOrigin], count: UInt, argv_ptr: Pointer[Pointer[NoneType, MutUntrackedOrigin], MutAnyOrigin]) -> UInt
```

Fill a caller-provided buffer with the callback's arguments.

N-API pads the buffer with `undefined` when fewer arguments were
supplied and drops the extras when more were, so compare the RETURN
value against `count` to detect either case. Discard it with `_ =` when
the buffer was sized from `argc` and you do not care.

Exists as a Bindings overload and an env-only overload; prefer the
Bindings form outside finalizer/TSFN/except contexts.

| argument | type | description |
|---|---|---|
| `env` | `NapiEnv` | The N-API environment. |
| `info` | `NapiValue` | The callback info handle. |
| `count` | `UInt` | Capacity of the buffer, in elements. |

**Returns** — The number of arguments the caller actually supplied.

**Raises** — If napi_get_cb_info does not return napi_ok.

*Overload 2 of 2.*

```mojo
def get_argv(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], info: Pointer[NoneType, MutUntrackedOrigin], count: UInt, argv_ptr: Pointer[Pointer[NoneType, MutUntrackedOrigin], MutAnyOrigin]) -> UInt
```

Fill a caller-provided buffer with the callback's arguments.

N-API pads the buffer with `undefined` when fewer arguments were
supplied and drops the extras when more were, so compare the RETURN
value against `count` to detect either case. Discard it with `_ =` when
the buffer was sized from `argc` and you do not care.

Exists as a Bindings overload and an env-only overload; prefer the
Bindings form outside finalizer/TSFN/except contexts.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings (Bindings overload only). |
| `env` | `NapiEnv` | The N-API environment. |
| `info` | `NapiValue` | The callback info handle. |
| `count` | `UInt` | Capacity of the buffer, in elements. |

**Returns** — The number of arguments the caller actually supplied.

**Raises** — If napi_get_cb_info does not return napi_ok.

### `get_data`

*Overload 1 of 2.*

```mojo
def get_data(env: Pointer[NoneType, MutUntrackedOrigin], info: Pointer[NoneType, MutUntrackedOrigin]) -> Pointer[NoneType, MutAnyOrigin]
```

Return the callback's associated data pointer.

For a function made by `JsFunction.create_with_data`, this is that
closure data. For a callback registered through `ModuleBuilder` or
`ClassBuilder`, it is the cached bindings pointer — which is what
`get_bindings` reads.

Exists as a Bindings overload and an env-only overload; prefer the
Bindings form outside finalizer/TSFN/except contexts.

| argument | type | description |
|---|---|---|
| `env` | `NapiEnv` | The N-API environment. |
| `info` | `NapiValue` | The callback info handle. |

**Returns** — The data pointer.

**Raises** — If napi_get_cb_info does not return napi_ok.

*Overload 2 of 2.*

```mojo
def get_data(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], info: Pointer[NoneType, MutUntrackedOrigin]) -> Pointer[NoneType, MutAnyOrigin]
```

Return the callback's associated data pointer.

For a function made by `JsFunction.create_with_data`, this is that
closure data. For a callback registered through `ModuleBuilder` or
`ClassBuilder`, it is the cached bindings pointer — which is what
`get_bindings` reads.

Exists as a Bindings overload and an env-only overload; prefer the
Bindings form outside finalizer/TSFN/except contexts.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings (Bindings overload only). |
| `env` | `NapiEnv` | The N-API environment. |
| `info` | `NapiValue` | The callback info handle. |

**Returns** — The data pointer.

**Raises** — If napi_get_cb_info does not return napi_ok.

### `get_bindings`

```mojo
def get_bindings(env: Pointer[NoneType, MutUntrackedOrigin], info: Pointer[NoneType, MutUntrackedOrigin]) -> Bindings
```

Fetch the cached N-API bindings attached to this callback.

The bootstrap almost every callback begins with. Prefer a fused
`get_bindings_and_*` accessor when you also need arguments — that is one
`napi_get_cb_info` call instead of two.

| argument | type | description |
|---|---|---|
| `env` | `NapiEnv` | The N-API environment. |
| `info` | `NapiValue` | The callback info handle. |

**Returns** — The cached Bindings.

**Raises** — If the data pointer is missing or fails the magic check.

### `get_bindings_and_one`

```mojo
def get_bindings_and_one(env: Pointer[NoneType, MutUntrackedOrigin], info: Pointer[NoneType, MutUntrackedOrigin]) -> BindingsAndOne
```

Fetch cached bindings and one argument in ONE napi_get_cb_info call.

The preferred entry point for a callback that needs both — the
unfused pair costs a second N-API call.

| argument | type | description |
|---|---|---|
| `env` | `NapiEnv` | The N-API environment. |
| `info` | `NapiValue` | The callback info handle. |

**Returns** — A BindingsAndOne.

**Raises** — If too few arguments were supplied, the data pointer is missing, or napi_get_cb_info fails.

### `get_bindings_and_two`

```mojo
def get_bindings_and_two(env: Pointer[NoneType, MutUntrackedOrigin], info: Pointer[NoneType, MutUntrackedOrigin]) -> BindingsAndTwo
```

Fetch cached bindings and two arguments in ONE napi_get_cb_info call.

The preferred entry point for a callback that needs both — the
unfused pair costs a second N-API call.

| argument | type | description |
|---|---|---|
| `env` | `NapiEnv` | The N-API environment. |
| `info` | `NapiValue` | The callback info handle. |

**Returns** — A BindingsAndTwo.

**Raises** — If too few arguments were supplied, the data pointer is missing, or napi_get_cb_info fails.

### `get_bindings_and_three`

```mojo
def get_bindings_and_three(env: Pointer[NoneType, MutUntrackedOrigin], info: Pointer[NoneType, MutUntrackedOrigin]) -> BindingsAndThree
```

Fetch cached bindings and three arguments in ONE napi_get_cb_info call.

The preferred entry point for a callback that needs both — the
unfused pair costs a second N-API call.

| argument | type | description |
|---|---|---|
| `env` | `NapiEnv` | The N-API environment. |
| `info` | `NapiValue` | The callback info handle. |

**Returns** — A BindingsAndThree.

**Raises** — If too few arguments were supplied, the data pointer is missing, or napi_get_cb_info fails.

### `get_bindings_and_this`

```mojo
def get_bindings_and_this(env: Pointer[NoneType, MutUntrackedOrigin], info: Pointer[NoneType, MutUntrackedOrigin]) -> BindingsAndThis
```

Fetch cached bindings and the receiver in ONE napi_get_cb_info call.

The preferred entry point for a callback that needs both — the
unfused pair costs a second N-API call.

| argument | type | description |
|---|---|---|
| `env` | `NapiEnv` | The N-API environment. |
| `info` | `NapiValue` | The callback info handle. |

**Returns** — A BindingsAndThis.

**Raises** — If too few arguments were supplied, the data pointer is missing, or napi_get_cb_info fails.

### `get_bindings_this_and_one`

```mojo
def get_bindings_this_and_one(env: Pointer[NoneType, MutUntrackedOrigin], info: Pointer[NoneType, MutUntrackedOrigin]) -> BindingsThisAndOne
```

Fetch cached bindings and the receiver and one argument in ONE napi_get_cb_info call.

The preferred entry point for a callback that needs both — the
unfused pair costs a second N-API call.

| argument | type | description |
|---|---|---|
| `env` | `NapiEnv` | The N-API environment. |
| `info` | `NapiValue` | The callback info handle. |

**Returns** — A BindingsThisAndOne.

**Raises** — If too few arguments were supplied, the data pointer is missing, or napi_get_cb_info fails.

---

## Functions

### `bindings_from_context`

```mojo
def bindings_from_context(context: Pointer[NoneType, MutAnyOrigin]) -> Bindings
```

Recover cached bindings from a designated carrier pointer.

For callbacks N-API does not hand `info` to, the bindings pointer travels
in whatever slot that callback *does* receive: the TSFN `context` (and
the same pointer as the TSFN finalize_cb's `finalize_hint`), or a
`wrap_native` finalizer's `finalize_hint`.

Verifies the BINDINGS_MAGIC sentinel. In a teardown path where a null is
expected, check `Int(ptr)` first and drop the call rather than relying on
the raise.

| argument | type | description |
|---|---|---|
| `context` | `Pointer[NoneType, MutAnyOrigin]` | The carrier pointer. |

**Returns** — The cached Bindings.

**Raises** — If the pointer is null or does not carry the magic sentinel.
