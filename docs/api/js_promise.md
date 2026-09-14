# `js_promise`

Source: [`src/napi/framework/js_promise.mojo`](../../src/napi/framework/js_promise.mojo)

JavaScript promises, in both directions.

**Producing a promise** — `JsPromise` pairs a Promise napi_value with its
deferred handle. Settle it once, then hand `value` to JavaScript:

```mojo
var p = JsPromise.create(b, env)
p.resolve(b, env, some_value)    # or p.reject(b, env, error_value)
return p.value
```

**Consuming a promise** — `JsPromise.on_settled` attaches a Mojo continuation,
and the continuation reads its outcome with `Settlement.read`:

```mojo
# in the calling callback — `on_done` is an ordinary napi callback
var cb_ref = on_done
return JsPromise.on_settled(b, env, promise, fn_ptr(cb_ref), captures)

# in on_done(env, info), inside its try block
var s = Settlement.read(env, info)
if not s.ok:
    ...                      # s.value is the rejection reason
...                          # s.value is the fulfilled value

# and in its except block — this rejects the promise on_settled returned
throw_js_error_dynamic(env, String(e))
```

Mojo code cannot wait for a promise. A napi callback runs on the JS thread,
and a promise settles only after that callback returns to the event loop, so
a continuation is the only shape: the callback returns, the loop runs, and the
continuation fires on a later tick. N-API offers no way to read a promise's
state or result, and re-entering the event loop from inside a callback runs
other JavaScript without ever running promise reactions.

---

## `JsPromise`

A JavaScript Promise and the deferred handle that settles it.

### Fields

| field | type | description |
|---|---|---|
| `value` | `NapiValue` | The promise itself — return this to JavaScript. |
| `deferred` | `NapiDeferred` | Settles the promise. Usable exactly once. |

### `__init__`

```mojo
def __init__(out self, value: Pointer[NoneType, MutUntrackedOrigin], deferred: Pointer[NoneType, MutUntrackedOrigin])
```

Pair an existing promise with its deferred handle.

Prefer `create`, which makes both.

| argument | type | description |
|---|---|---|
| `value` | `NapiValue` | The promise napi_value. |
| `deferred` | `NapiValue` | The deferred handle napi_create_promise returned with it. |

### `create`

```mojo
def create(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin]) -> Self
```

Create a pending promise and its deferred handle.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |

**Returns** — A JsPromise whose `value` is pending until `resolve` or `reject`.

**Raises** — If napi_create_promise does not return napi_ok.

### `resolve`

```mojo
def resolve(self, b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], resolution: Pointer[NoneType, MutUntrackedOrigin])
```

Fulfil the promise with `resolution`.

The deferred handle is consumed: do not call `resolve` or `reject`
on this JsPromise again.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `resolution` | `NapiValue` | The value the promise fulfils with. |

**Raises** — If napi_resolve_deferred does not return napi_ok.

### `reject`

```mojo
def reject(self, b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], rejection: Pointer[NoneType, MutUntrackedOrigin])
```

Reject the promise with `rejection`.

Build the reason with `raw_create_error` rather than a throw helper, so
no exception is left pending. The deferred handle is consumed.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `rejection` | `NapiValue` | The rejection reason, usually an Error object. |

**Raises** — If napi_reject_deferred does not return napi_ok.

### `on_settled`

*Overload 1 of 2.*

```mojo
def on_settled(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], value: Pointer[NoneType, MutUntrackedOrigin], cb_ptr: Pointer[NoneType, MutAnyOrigin], captures: List[Pointer[NoneType, MutUntrackedOrigin]]) -> NapiValue
```

Attach a Mojo continuation that runs once `value` settles.

The overload for a continuation that needs only JavaScript values.
See the `data` overload for the full contract.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `value` | `NapiValue` | A promise, a thenable, or any value — treated like `await`. |
| `cb_ptr` | `Pointer[NoneType, MutAnyOrigin]` | The continuation, a napi callback, via `fn_ptr(...)`. |
| `captures` | `List[Pointer[NoneType, MutUntrackedOrigin]]` | JavaScript values the continuation needs later. |

**Returns** — The promise `.then()` returned. It settles with whatever the continuation returns or throws.

**Raises** — If the continuation could not be attached.

*Overload 2 of 2.*

```mojo
def on_settled(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], value: Pointer[NoneType, MutUntrackedOrigin], cb_ptr: Pointer[NoneType, MutAnyOrigin], captures: List[Pointer[NoneType, MutUntrackedOrigin]], data: Pointer[NoneType, MutAnyOrigin], finalize_cb: Pointer[NoneType, MutAnyOrigin]) -> NapiValue
```

Attach a Mojo continuation that runs once `value` settles.

Equivalent to `Promise.resolve(value).then(onFulfilled, onRejected)`,
where both handlers are the one continuation `cb_ptr`. It reads the
outcome with `Settlement.read(env, info)`. Because both handlers are
attached, a rejection is always observed — it never surfaces as an
unhandled rejection unless the continuation itself throws and nobody
handles the returned promise, exactly as in JavaScript.

**Nothing here is freed when the continuation fires**, because a
continuation may never fire: the promise can stay pending forever.
Everything is tied to the garbage collector instead:

- `captures` become bound arguments of the handler functions, so the
  GC traces them. No napi_ref roots them, so a capture that refers
  back to the promise cannot keep the whole graph alive.
- `data` is ADOPTED on every path, success or failure:
  `finalize_cb(env, data, null)` runs exactly once — when the handler
  functions are collected, or before this raises if the continuation
  could not be created. Never free `data` yourself after passing it.

Do not rely on the continuation running at most once. A thenable with
its own `then` can call a handler repeatedly, or both handlers; since
nothing is freed on the call path, that is memory-safe.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `value` | `NapiValue` | A promise, a thenable, or any value — treated like `await`. |
| `cb_ptr` | `Pointer[NoneType, MutAnyOrigin]` | The continuation, a napi callback, via `fn_ptr(...)`. |
| `captures` | `List[Pointer[NoneType, MutUntrackedOrigin]]` | JavaScript values the continuation needs later, read     back from `Settlement.captures` in the same order. |
| `data` | `Pointer[NoneType, MutAnyOrigin]` | Native state for the continuation, read back from     `Settlement.user_data()`. May be null. |
| `finalize_cb` | `Pointer[NoneType, MutAnyOrigin]` | A `def(env, data, hint)` that frees `data`. May be     null when `data` needs no freeing. |

**Returns** — The promise `.then()` returned. It settles with whatever the continuation returns or throws.

**Raises** — If the continuation could not be attached. `data` has been finalized or is owned by the collector either way.

---

## `Settlement`

The outcome a continuation attached by `JsPromise.on_settled` sees.

### Fields

| field | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings, recovered from the continuation's context. |
| `ok` | `Bool` | True if the promise fulfilled, False if it rejected. |
| `value` | `NapiValue` | The fulfilled value, or the rejection reason when `ok` is False. |
| `captures` | `List[Pointer[NoneType, MutUntrackedOrigin]]` | The `captures` passed to `on_settled`, in the same order. |

### `__init__`

```mojo
def __init__(out self, b: Pointer[NapiBindings, MutUntrackedOrigin], ok: Bool, value: Pointer[NoneType, MutUntrackedOrigin], var captures: List[Pointer[NoneType, MutUntrackedOrigin]], user_data: Pointer[NoneType, MutAnyOrigin])
```

Assemble a settlement. Continuations use `read` instead.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `ok` | `Bool` | Whether the promise fulfilled. |
| `value` | `NapiValue` | The fulfilled value or rejection reason. |
| `captures` | `List[Pointer[NoneType, MutUntrackedOrigin]]` | The captured JavaScript values. |
| `user_data` | `Pointer[NoneType, MutAnyOrigin]` | The native `data` passed to `on_settled`. |

### `read`

```mojo
def read(env: Pointer[NoneType, MutUntrackedOrigin], info: Pointer[NoneType, MutUntrackedOrigin]) -> Self
```

Read the outcome inside a continuation attached by `on_settled`.

Needs no bindings argument: the continuation's context carries them,
which is why this is the first call a continuation makes.

| argument | type | description |
|---|---|---|
| `env` | `NapiEnv` | The N-API environment. |
| `info` | `NapiValue` | The continuation's callback info. |

**Returns** — The settlement: bindings, outcome, value, captures and data.

**Raises** — If the callback was not attached by `on_settled`.

### `user_data`

```mojo
def user_data(self) -> Pointer[NoneType, MutAnyOrigin]
```

Return the native `data` passed to `on_settled`, or null.

**Returns** — The data pointer. It stays valid for as long as the continuation can run; do not free it — `on_settled` adopted it.
