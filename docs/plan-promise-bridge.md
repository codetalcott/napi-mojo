# Plan: awaiting a JS Promise from Mojo

**Status: not built, deliberately.** Mojo code that needs a promise's result
uses a continuation, `JsPromise.on_settled`. This document records why nothing
blocking is possible, what an await that actually *suspends* Mojo code would
take (napi-rs's design, read from source), and the gate for building it.

Studied 2026-09-13 against Mojo 1.0.0, Node 24.15.0 and napi-rs `napi` 3.12.1.

## What is and is not possible

| Question | Answer | Evidence |
|---|---|---|
| Does Mojo have `await`? | **Yes.** `async def`, `await`, `Task`, `create_task` | Compiled and ran on the pin; `spike/await_probe.mojo` header |
| Can host-mode code wait for a JS promise inside its callback? | **No.** | `spike/await_probe.mojo` — polling, callback scopes and `uv_run` re-entry all fail |
| Can N-API read a promise's state or result? | **No.** Only `napi_create_promise`, `napi_resolve_deferred`, `napi_reject_deferred`, `napi_is_promise` | `js_native_api.h`, Node 24 |
| Can Mojo code continue after a promise? | **Yes.** `JsPromise.on_settled` | `tests/host.test.js`, `tests/finalizer_gc.test.js` |
| Can a Mojo coroutine `await` a JS promise? | **Not with public APIs today** — see "Gaps" | Mojo stdlib docs |

The mechanism behind the second row: host-mode code runs synchronously on the
JS thread, and a promise's reactions run at a microtask checkpoint that happens
only after that code returns. Re-entering `uv_run` from inside a callback runs
libuv callbacks — the probe watched a `setTimeout` callback run on the nested
stack and call `resolve()` — but the resolved promise's `.then` still did not
run until the outer callback returned. So a "blocking await" helper would be
unsafe (arbitrary JS on a nested stack) and would not work.

A promise returned to Mojo is also not necessarily pending: an `async`
function that never awaits returns an already-fulfilled promise. Mojo cannot
tell the difference, which is the third row.

## How napi-rs does it

Source: napi-rs commit `956e4525` ("chore: release (#3448)"), the commit the
crates.io tarballs of `napi` 3.12.1, `napi-derive` 3.6.3 and
`napi-derive-backend` 6.1.2 record. `N/` is `crates/napi/src/`.

**napi-rs never waits on the JS thread either.** Rust code that awaits a JS
promise runs on a tokio worker thread; the JS thread only attaches handlers.

1. **`Promise<T>` is a one-shot receiver, nothing more**
   (`N/bindgen_runtime/js_values/promise.rs:34-36`). It holds no reference to
   the JS promise.
2. **The handlers are attached on the JS thread, during argument conversion**
   (`promise.rs:61-90`): `.then(send Ok).catch(send Err)`, both capturing the
   sender of a `futures::channel::oneshot`. `.catch` is chained on `.then`'s
   result, so a rejection — or a failure converting the value — is handled.
3. **The awaiting future runs on a process-global multi-thread tokio runtime**
   (`N/tokio_runtime.rs:970-997`). `#[napi] async fn` spawns it there
   (`crates/backend/src/codegen/fn.rs:277-296`).
4. **Results go back through a threadsafe function per call**
   (`N/js_values/deferred.rs:571-632`): the worker queues the settlement, and
   the JS thread converts the value and calls `napi_resolve_deferred`.
5. **Calling JS from a worker and awaiting its result** is `call_async` on a
   `ThreadsafeFunction`: the call-js callback converts the return value on the
   JS thread and sends it over another oneshot. If that value is a promise,
   step 2 repeats, giving a double await
   (`examples/napi/src/threadsafe_function.rs:228-231`):

   ```rust
   let val = func.call_async(Ok(1)).await?.await?;
   ```

6. **Closures are freed by the collector, not by being called.**
   `create_function_from_closure` uses `napi_add_finalizer` on the function
   (`N/env.rs:695-704`); `PromiseRaw::then` uses `napi_wrap` on the derived
   promise plus an "executed" flag, freeing the closure on the call or, if it
   never ran, in the finalizer (`promise_raw.rs:146-160, 537-552`).

`JsPromise.on_settled` is napi-rs's steps 2 and 6, adapted: both handlers are
attached, and everything is finalizer-owned. It differs in two deliberate
ways. Nothing is freed on the call path, so there is no executed flag and a
thenable that calls a handler twice cannot double-free. And JS values the
continuation needs are bound arguments rather than references, so the GC can
trace them — napi-rs's `Promise<T>` sidesteps that question because its
closures capture only a channel sender.

## What a bridge would need here

| napi-rs primitive | napi-mojo today |
|---|---|
| JS function backed by native state, freed by a finalizer | **Have** — `JsObject.add_finalizer`, used by `on_settled` |
| Handlers attached on the JS thread, rejections handled | **Have** — `JsPromise.on_settled` |
| Worker-thread executor | **Have** — AsyncRT (`create_task`), or libuv async work (`AsyncWork`) |
| Deferred resolved from a worker via a threadsafe function | **Have the pieces** — `JsPromise`, `ThreadsafeFunction` |
| Threadsafe call whose return value reaches the worker | **Missing** — `ThreadsafeFunction` has `call_blocking` / `call_nonblocking` only |
| Cross-thread one-shot channel | **Missing** — see Gaps |
| JS values held across threads, released on their own thread | **Missing** as a pattern |
| Env-teardown accounting for in-flight work | Partial — cleanup hooks and the TSFN teardown rules in CLAUDE.md |

### Gaps

- **No completable awaitable in Mojo's public stdlib.** A `Task` completes
  only when its own coroutine returns; `TaskGroup`'s completion chain is
  private. So a Mojo *coroutine* cannot be suspended on an event the JS thread
  signals. From the docs, not tested.
- **A blocking one-shot is buildable** from public primitives — `Atomic` plus
  `SpinWaiter` or `BlockingSpinLock` — so a *worker thread* could block until a
  JS promise settles. Blocking a worker is fine; blocking the JS thread is the
  thing that cannot work.
- **Awaiting code cannot touch JS directly.** It runs off the JS thread, so
  `NodeHost`, `JsObject.call_method` and every other N-API call are
  unavailable; every JS call becomes a threadsafe-function hop. That is a
  second API surface beside host mode, not an extension of it.

### Hazards in napi-rs not to copy

- An error in a threadsafe-function callback calls `napi_fatal_exception`,
  killing the process (`N/threadsafe_function.rs:922-924`).
- Inferred from source, not tested: an in-flight `call_async` never completes
  once its TSFN is torn down (`call_js_cb` returns early on a null env without
  dropping the sender, `:820-823`); a spawned future dropped by runtime
  shutdown never settles its promise (`JsDeferred` has no `Drop`); and a
  `finally` closure that never fires is never freed (`promise_raw.rs:236-282`).

## Gate

The same gate as P5 in [`plan-distribution.md`](plan-distribution.md): **a
host-mode program written by someone, anywhere, that is not in this repo** —
and one whose shape a continuation cannot serve.

If it opens, spike before designing an API:

1. A one-shot on `Atomic` + `SpinWaiter`, set from a JS-thread continuation
   and waited on from an AsyncRT task.
2. A `ThreadsafeFunction` call that carries a return value back to the waiting
   thread.
3. The Mojo equivalent of `tsfn_return_promise` above, with the teardown
   cases from "Hazards" as tests, under the `async-stress` job's checking
   allocator.
