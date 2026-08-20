# Plan: bidirectional napi-mojo — Node as a host for Mojo programs

**Status**: **Implemented** (2026-08-20). Call ergonomics
([`js_function.mojo`](../src/napi/framework/js_function.mojo),
[`js_object.mojo`](../src/napi/framework/js_object.mojo),
[`handle_scope.mojo`](../src/napi/framework/handle_scope.mojo)), the host
surface ([`js_host.mojo`](../src/napi/framework/js_host.mojo)), and the
`napi-mojo run` CLI verb all shipped, with
[`tests/host.test.js`](../tests/host.test.js),
[`examples/host/`](../examples/host/), and two CI end-to-end steps.

**Created**: 2026-08-20
**Driver**: positioning. The framework's pitch was "JS devs get a fast native
function." It could already drive Node from the Mojo side, but nothing said so
and the ergonomics stopped at `call2`.

## Context

The Mojo→JS direction was already built, and already correct. Probed against
the shipped `build/index.node` before any of this work:

```
getGlobal() === globalThis   : true     # process, fetch, console, JSON in reach
runScript('process.version') : v24.18.0
callFunction(() => { throw new TypeError('X') })  ->  TypeError: X
```

That last line is the load-bearing one. Exception *identity* survives a Mojo
frame because N-API's preamble makes `napi_throw_error` a no-op while an
exception is already pending — so an addon's `except:` block calling
`throw_js_error` cannot clobber the real error. This is why every host callback
throws unconditionally in its `except:` block: it is correct in both
directions, surfacing Mojo-side failures while leaving a pending JS error
intact. `tests/host.test.js` pins it with a `MODULE_NOT_FOUND` assertion.

So this was **surfacing and ergonomics, not a new subsystem** — which is what
made it affordable while the project is still Alpha.

### The one real gap: `require`

`require` is module-scoped and not on `globalThis`. Measured:

| Host | `process.mainModule.require` from Mojo |
|---|---|
| CJS file | resolves — Mojo can `require('fs')` |
| ESM / `node -e` | `undefined` |

Depending on `process.mainModule` is fragile. The design decision is that the
**bootstrap hands Mojo the keys**: it builds a require with
`module.createRequire` (rooted at the *entry's* directory, so the user's
`node_modules` and relative paths resolve) and passes it on the `ctx` object.
`NodeHost.from_context` validates it is there, so a mis-wired bootstrap fails
with a clear message rather than at the first property lookup.

### Why not embed libnode

Recorded because it will be asked again:

- N-API is a **guest** API. Every function takes a `napi_env`, and there is no
  public N-API to *create* one.
- Node's embedder API is **C++** — `v8::Isolate`, `std::unique_ptr`, by-value
  struct returns. Mojo's FFI is C-ABI only; this codebase already rejected
  `OwnedDLHandle.get_function` partly because by-value structs "would silently
  corrupt the call."
- There are no official cross-platform `libnode` prebuilts.
- It would cost the README's core promise: a **pure Mojo source framework** you
  compile against with `mojo build -I`. A C++ shim changes what the project is.

The sibling [`mojo-http`](https://github.com/codetalcott/mojo-http) shows the
shape of the alternative — its `m0-wsgi` package embeds CPython to get Django —
and that works precisely *because CPython exposes a stable C ABI*. Node does
not. `napi-mojo run` reaches the same practical goal (Mojo code, foreign
ecosystem) with no C++ and no libnode.

## What shipped

**Call ergonomics.** `JsFunction.call_n` (runtime-length `List[NapiValue]`,
`this` = undefined) and `JsFunction.call_with` (explicit `this`).
`call0`/`call1`/`call2` stay as the allocation-free fast paths.
`JsObject.call_method(name, args)` composes the two — that is what makes
`fs.readFileSync(...)` a one-liner with `this` bound correctly, which
`call1` silently gets wrong.

**`with_handle_scope[body]`** in `handle_scope.mojo`, encapsulating the
try/except discipline that module's header already described. It matters for
host mode specifically: a Mojo-driven loop calling JS pins every napi_value to
the enclosing scope until it closes. `tests/host.test.js` runs a 20,000-
iteration loop as the regression guard.

**`NodeHost`** in `js_host.mojo` — `from_context`, `require`,
`global_object`, `argv`, `console_log`. Deliberately small: every public `def`
costs a cover call in `framework_coverage.mojo` and a docstring.

**`napi-mojo run <entry.mojo> [-- args]`** and `napi-mojo init --host`. The
run verb generates `_napi_mojo_host_entry.mojo` *next to* the user's entry
(Mojo resolves a plain-module import relative to the main module's directory —
this is what makes `from main import mojo_main` work with no extra `-I`),
builds it into `.napi-mojo/`, writes a CJS bootstrap, and spawns Node. A
number returned from `mojo_main` becomes the process exit code. The wrapper is
removed after the run unless `--keep`.

## Constraints, and why they are not bugs

1. **No `await`.** A JS function returning a Promise hands Mojo a pending
   Promise it cannot suspend on. Supported shapes: synchronous APIs, or
   continuation-passing via `JsFunction.create` + `.then()`. **Do not add a
   blocking await helper** — draining the event loop from inside a napi
   callback re-enters JS on a stack already inside one.
2. **Handle scopes in Mojo-driven loops** — see `with_handle_scope`.
3. **A pending JS exception poisons every subsequent N-API call**
   (`napi_pending_exception`). Bail or clear; do not keep calling.
4. **`require` must be handed in** — table above.
5. **Per-call cost is real.** Host mode is for I/O-bound glue, not compute.

## Verification

- `tests/host.test.js` — 24 tests: require (builtins, `node:` prefix, module
  identity, MODULE_NOT_FOUND identity, missing-`require` rejection), globals,
  argv round-trip, console through the outer realm, `call_method` `this`
  binding and error identity, `call_n` at 0/1/2/3/8/32 args and argument
  order, and the 20k-iteration scoped loop.
- CI: **Host-mode program end-to-end** (runs `examples/host/main.mojo`, checks
  output, argv passthrough, and that the generated wrapper was cleaned up) and
  **Host-mode scaffold end-to-end** (`init --host` then `run`, unedited).
- `tests/compile/framework_coverage.mojo` covers every new public method,
  including the parametric `with_handle_scope` instantiation.

## Non-goals

- Embedding libnode / Mojo owning `main()` — rejected above.
- Any build-time dependency on `mojo-http`. The relationship is positioning
  only: Mojo owns `main` → mojo-http; Node owns `main` → `napi-mojo run`.
- An `await` abstraction over JS promises.
- Reworking `call0`/`call1`/`call2` into `call_n`.
