# `js_host`

Source: [`src/napi/framework/js_host.mojo`](../../src/napi/framework/js_host.mojo)

Node as a HOST for Mojo programs.

The rest of this framework serves the usual direction: JavaScript calls a
Mojo function. This module serves the other one — a Mojo program that drives
Node, using the JavaScript runtime and npm as its standard library.

```mojo
# inside mojo_main(b, env, ctx) — see examples/host/main.mojo for the whole file
var host = NodeHost.from_context(b, env, ctx)
var fs = host.require("fs")
var txt = fs.call_method(b, env, "readFileSync", args)
host.console_log("read the file")
```

(The example deliberately shows the body rather than the `def` line:
scripts/check-compile-coverage.mjs scans this file for public declarations by
regex, and a `def` inside a doc fence reads to it as an uncovered method.)

`napi-mojo run main.mojo` builds a wrapper that registers mojo_main and
launches Node on a bootstrap that calls it. The user writes no N-API
registration boilerplate.

**Why the context object exists.** `require` is MODULE-scoped, not a global,
so it is not reachable from Mojo through napi_get_global — measured:
`process.mainModule.require` resolves in a CJS entry but is `undefined` under
ESM or `node -e`. Rather than depend on that, the bootstrap constructs a
require with `module.createRequire` and hands it to Mojo on the ctx object.
The bootstrap holds the keys and passes them in; Mojo never scavenges.

**What this cannot do.** Mojo has no `await`. A JS function returning a
Promise returns a *pending* Promise to Mojo, and Mojo cannot suspend on it.
Two supported shapes:

1. Synchronous APIs (`readFileSync`, `execSync`) — the default, and simplest.
2. Continuation passing — build a Mojo callback with `JsFunction.create` and
   hand it to `.then()`. `mojo_main` returns, the event loop runs, and the
   callback fires later.

Do not add a blocking "await" helper here: draining the event loop from
inside a napi callback re-enters JS on a stack that is already inside one.

---

## `NodeHost`

The Node runtime, as seen from a Mojo program that it hosts.

### Fields

| field | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings, threaded through every call. |
| `env` | `NapiEnv` | The N-API environment this program is running in. |
| `ctx` | `NapiValue` | The bootstrap-supplied context object: { require, argv, cwd }. |

### `__init__`

```mojo
def __init__(out self, b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], ctx: Pointer[NoneType, MutUntrackedOrigin])
```

Wrap an already-validated bootstrap context.

Prefer `from_context`, which checks that the object actually carries
a callable `require` before you depend on it.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `ctx` | `NapiValue` | The bootstrap context object. |

### `from_context`

```mojo
def from_context(b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], ctx: Pointer[NoneType, MutUntrackedOrigin]) -> Self
```

Build a NodeHost from the bootstrap's context object.

Validates that `ctx.require` is present, so a mis-wired bootstrap
fails here with a clear message rather than at the first require()
with a confusing property-lookup error.

| argument | type | description |
|---|---|---|
| `b` | `Bindings` | Cached N-API bindings. |
| `env` | `NapiEnv` | The N-API environment. |
| `ctx` | `NapiValue` | The bootstrap context object: { require, argv, cwd }. |

**Returns** — A NodeHost bound to this environment.

**Raises** — Error: If ctx carries no `require` — the bootstrap is wrong, or mojo_main was called directly by a caller that is not the `napi-mojo run` bootstrap.

### `require`

```mojo
def require(self, name: String) -> JsObject
```

Load a module the way `require(name)` would in the entry file.

Resolution is relative to the entry module, so both builtins
("fs", "node:path") and installed packages resolve.

| argument | type | description |
|---|---|---|
| `name` | `String` | The module specifier. |

**Returns** — The module's exports.

**Raises** — Error: If resolution fails. The underlying JS error stays pending and keeps its identity, so the caller sees Node's own MODULE_NOT_FOUND rather than a generic wrapper.

### `global_object`

```mojo
def global_object(self) -> JsObject
```

Return `globalThis`.

The reachable surface is everything Node puts there: process, console,
fetch, JSON, URL, TextDecoder, setTimeout.

**Returns** — The global object.

**Raises** — Error: If the N-API call fails.

### `argv`

```mojo
def argv(self) -> List[String]
```

Return the program's arguments, excluding node and the bootstrap.

These are the arguments after `napi-mojo run <entry.mojo> --`.

**Returns** — The argument strings, in order.

**Raises** — Error: If ctx.argv is missing or is not an array of strings.

### `console_log`

```mojo
def console_log(self, msg: String)
```

Write one line to stdout via `console.log`.

Routed through console rather than a Mojo `print` so that output
interleaves correctly with the host's own writes and honours whatever
the embedder has done to console.

| argument | type | description |
|---|---|---|
| `msg` | `String` | The line to write. |

**Raises** — Error: If the console lookup or the call fails.
