# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**napi-mojo** — the Mojo equivalent of Rust's `napi-rs`. A framework for building Node.js native addons in Mojo via the Node-API (N-API) C interface. All planned phases complete — 153 exported functions + 5 classes covering the full N-API surface (650+ tests, plus 7 GC finalizer tests behind `--expose-gc`; the exact count is whatever `npm test` reports — don't embed it in prose, nothing updates numbers embedded in prose): primitive types, integer types (Int32/UInt32/Int64), object property reading/enumeration/deletion, function calling/creation, array mapping with handle scopes, variable-length arguments, type checking, error propagation (Error/TypeError/RangeError/SyntaxError), promises (create/resolve/reject), async work (worker thread execution + cancellation), ThreadsafeFunction (call JS from worker threads), ArrayBuffer (including external/Mojo-owned memory), Buffer, TypedArray, DataView, class construction (wrap/unwrap, prototype methods, getter/setter, static methods, class inheritance via prototype chain), persistent references, escapable handle scopes, global object access, BigInt (including arbitrary-precision word arrays), Date, Symbol, strict equality, instanceof, object freeze/seal/detach, prototype access, array element has/delete, external data (opaque native pointers with GC finalizers), napi_add_finalizer on arbitrary objects, instance data (per-env singleton), environment cleanup hooks (sync + async), type coercion (Boolean/Number/String/Object), TypeScript definition generation with JSDoc, exception handling (throw/catch any value), property set/has by napi_value key (symbol keys), version info (N-API + Node.js), script execution, async context + callback scope, type tagging, and external memory tracking. Higher-level API includes `fn_ptr()`, `ModuleBuilder`/`ClassBuilder` for ergonomic registration, `unwrap_native[T]()` for class methods, `ToJsValue`/`FromJsValue` conversion traits, parametric array helpers (`to/from_js_array_f64/str`), an `AsyncWork` helper for ergonomic async work (promise + queue + resolve/reject), a TOML code generator (`scripts/generate-addon.mjs` + `src/exports.toml`) with `mojo_fn` auto-trampolines, nullable returns (`Optional[T]` → `T | null`), struct-to-object mapping (`[structs.*]` → bidirectional converters), async/class generation, and auto-generated TypeScript `.d.ts` with interfaces, `MojoFloat64Array` for zero-copy TypedArray output, `parallelize_safe()` for SIMD parallel computation with automatic runtime init, **typed handles** (`JsExternal.create_typed[T]` / `get_typed[T]`, `set_instance_data[T]` / `get_instance_data[T]` with generic finalizers), and **cached NapiBindings** — all 142 N-API function pointers resolved once at module init, passed through callback data to every entry-point callback (zero per-call dlsym). The framework is **bidirectional**: besides addons (JS calls Mojo) it supports **host mode** (`napi-mojo run` — a Mojo program that drives Node and uses npm as its standard library), via `NodeHost`, `JsObject.call_method`, `JsFunction.call_n`/`call_with` and `with_handle_scope`.

## Commands

```bash
pixi run bash build.sh               # compile src/lib.mojo → build/index.node
npm test                              # run the full Jest suite
npm run test:gc                       # run GC finalizer tests (requires --expose-gc)
npx jest tests/basic.test.js          # run a single test file
npm run generate:addon                # regenerate src/generated/ from src/exports.toml
node scripts/benchmark.mjs            # per-call overhead benchmark

# Host mode — a Mojo PROGRAM that Node hosts (the other direction):
node bin/napi-mojo.mjs init myprog --host   # scaffold main.mojo with mojo_main
node bin/napi-mojo.mjs run examples/host/main.mojo -- one two

# Spike (run before anything else if starting fresh):
pixi run mojo build --emit shared-lib spike/ffi_probe.mojo -o build/probe.dylib
mv build/probe.dylib build/probe.node
node -e "console.log(require('./build/probe.node').hello())"
```

## Architecture

### The core FFI problem

N-API functions (`napi_create_string_utf8`, `napi_define_properties`, etc.) are **not in libc** — they live in the Node.js host process. When Node.js loads our `.node` file via `dlopen`, N-API symbols are already in the process address space. We access them via `OwnedDLHandle()` (equivalent to `dlopen(NULL, ...)`), which opens the host process symbol table at runtime, and resolve individual symbols with `get_symbol` (see the `get_function` rule below — `get_function` is no longer usable for C FFI).

### Cached NapiBindings (zero per-call dlsym)

All 142 N-API function pointers are resolved once at module init via a single `OwnedDLHandle()` + 142 `get_symbol` lookups, stored in the `NapiBindings` struct (`src/napi/bindings.mojo`). Each slot holds the symbol address directly (`_slot()`); `raw.mojo`'s `_sym[F]` reinterprets a slot as a `thin abi("C")` function pointer at the call, and `assert_fn_ptr_is_one_word()` guards that reinterpret at compile time. The pointer is passed through `NapiPropertyDescriptor.data` to every callback. Each callback retrieves it via `CbArgs.get_bindings(env, info)` (1 bootstrap dlsym for `napi_get_cb_info`, then all subsequent calls use cached pointers). This eliminates the per-call `OwnedDLHandle()` + `dlsym` overhead that would otherwise occur on every N-API call.

**The env-only overload surface is DELETED.** Every `raw_*` wrapper and framework method used to exist twice — an env-only variant doing per-call `OwnedDLHandle()`+dlsym, and the cached-Bindings variant. Once every "bindings unavailable" context had a designated carrier (below), the ~1,600-line env-only half of `raw.mojo` plus ~173 duplicated framework halves were removed. What SURVIVES env-only, deliberately:

- **`raw_get_cb_info`** — the per-callback bootstrap that fetches the bindings pointer from callback data; by definition it runs before bindings are available. All of `args.mojo`'s env-only `CbArgs` methods build on only this symbol.
- **`raw_throw_error/_type_error/_range_error/_syntax_error`** and `error.mojo`'s env-only throw helpers — the `except:`-block fallback surface, used when bindings retrieval itself failed.

Everything else takes `b: Bindings` first. `ModuleBuilder`/`ClassBuilder` registration methods keep their b-less signatures but derive cached bindings internally from `self.data` via `bindings_from_context()` — `data` MUST be the bindings pointer (the 2-arg no-bindings ctors are gone).

**Cached bindings reach non-entry callbacks through designated carriers** (`bindings_from_context()` in `args.mojo` is the magic-checked accessor):

- **TSFN `call_js_cb`**: `ThreadsafeFunction.create(b, …)` registers the bindings pointer as the TSFN *context*, which N-API hands to `call_js_cb` as its 3rd parameter — and to the TSFN `finalize_cb` as `finalize_hint`.
- **`wrap_native` class finalizers**: the bindings pointer is the `finalize_hint` (alive for the env's whole lifetime — the bindings heap allocation is never freed). Bespoke finalizers whose hint carries other data put `bindings_addr: Int` in their payload struct instead (`TypedPayload` does).
- **Async complete callbacks**: the data struct carries `bindings_addr: Int` (written by the entry callback, read by complete — both main thread). GENERATED async completes have this built in; every handwritten async data struct now carries it too (`AsyncProgressData`'s worker-thread execute also uses it, but only for `napi_call_threadsafe_function`, the one any-thread-safe N-API call, avoiding the per-iteration `dlopen(NULL)` loader-lock).
- **Async cleanup hooks**: the hook's `arg` is the bindings pointer.
- **Dynamically created inner callbacks**: their data slot either IS the bindings pointer (`inner_callback_fn`) or a capture struct that embeds it (`AdderCapture.b_raw`).

**The per-callback bootstrap dlsym is GONE — `src/napi/global_cache.mojo`.**
`raw_get_cb_info`'s env-only overload used to run `OwnedDLHandle()` +
`get_symbol` on EVERY callback: ~346 ns/call, of which ~280 ns was dlsym itself
(the Mojo wrapper adds ~66 ns; the `String` copy inside `get_symbol` only ~8 ns,
so bypassing the wrapper was never the fix). That was essentially the entire
napi-rs gap — a FLAT ~330 ns delta across calls whose absolute cost varied 8x.
Removing it moved `bench/napi-rs` from **3.95x slower to 0.42x**, and the
benchmark ceilings were reseeded because the old ones had ~50x headroom and
would no longer have caught the regression they exist for.

**Mojo has no module-level `var`, but it does have `pop.global_alloc`.** The
language-surface hard error ("global variables are not supported") is still
real — `spike/global_probe.mojo` documents it. What is NOT true, and what this
file claimed until it was measured, is that a process-lifetime cache is
therefore impossible. `__mlir_op.pop.global_alloc` — the mutable sibling of the
op behind `builtin/globals.global_constant` — lowers to
`llvm.mlir.global internal @<name>`: a zero-initialised, module-private slot in
the data segment. Verified stable across call sites, across a `-I` package
boundary, and across separate JS→Mojo callback entries on later event-loop
ticks.

**`@no_inline` on the accessor is load-bearing.** `pop.global_alloc` is `Pure`,
so every inlined copy materialises its OWN global: without it the probe returns
sequential addresses 8 bytes apart and stores vanish. Do not remove it; do not
add `@always_inline`.

**Only the symbol ADDRESS is cached, never the `NapiBindings`.** The struct's
`registry` holds `NapiRef`s to class constructors, and a napi_ref is
env-specific — under `worker_threads` a callback in env B could read env A's
refs. A resolved symbol address is process-image state, so it is safe; per-env
bindings still travel through callback data as before.

**The failure mode is graceful, which is what makes the internal-API risk
affordable.** `__mlir_op` has no stability guarantee and `_get_kgen_string` is a
private stdlib import. If either breaks, each call site sees a zero slot and
falls back to dlsym — slower, never wrong. Because that is silent,
`globalCacheActive()` (`src/addon/global_cache_ops.mojo`) exports the state and
`tests/global_cache.test.js` asserts it, the same way `runtime.test.js` guards
`parallelize_safe`'s silent sequential fallback.

### How a `.node` addon works

1. `mojo build --emit shared-lib` produces a `.dylib` renamed to `.node`
2. Node.js calls `dlopen` on the `.node` file, then `dlsym("napi_register_module_v1")`
3. Our `@export("napi_register_module_v1", ABI="C")` function is called with `(env, exports)`
4. We allocate `NapiBindings`, resolve all 142 symbols, pass pointer through `ModuleBuilder`
5. Each exported Mojo function acts as a `napi_callback`: `fn(NapiEnv, NapiValue) -> NapiValue`

### Module structure

```
src/lib.mojo                             # entry point: thin orchestrator calling src/addon/ register_* fns
src/addon/*.mojo                         # 17 callback implementation files (primitives, collections, async_ops, class_counter, etc.)
src/addon/user_fns.mojo                  # pure Mojo functions for mojo_fn trampolines (no N-API deps)
src/addon/struct_fns.mojo                # pure Mojo functions that use generated struct types
src/napi/types.mojo                      # NapiEnv, NapiValue, NapiStatus, NapiDeferred, NapiAsyncWork, NapiPropertyDescriptor, NapiValueType constants, TypedArray type constants, property attribute constants
src/napi/bindings.mojo                   # NapiBindings struct (142 cached fn ptrs + registry + magic sentinel = 144 fields), init_bindings(), Bindings type alias, BINDINGS_MAGIC
src/napi/raw.mojo                        # raw_* wrappers over cached bindings slots (+ 5 kept env-only bootstrap/throw wrappers)
src/napi/error.mojo                      # napi_status_name(), check_status(), throw_js_error(), throw_js_error_dynamic(), throw_js_type_error(), throw_js_range_error()
src/napi/keepalive.mojo                  # pin_across_ffi() — non-elidable keep-alive for a local's stack slot across an N-API call
src/napi/module.mojo                     # define_property(), register_method()
src/napi/framework/js_string.mojo        # JsString.create(), create_literal(), from_napi_value(), read_arg_0()
src/napi/framework/js_object.mojo        # JsObject.create(), set_property(), set_named_property(), set(), get(), get_property(), get_named_property(), has(), has_property(), keys(), has_own(), delete_prop(), instance_of(), freeze(), seal(), prototype()
src/napi/framework/js_number.mojo        # JsNumber.create(), create_int(), from_napi_value(), to_int()
src/napi/framework/js_boolean.mojo       # JsBoolean.create(), from_napi_value()
src/napi/framework/js_int32.mojo         # JsInt32.create(), from_napi_value()
src/napi/framework/js_uint32.mojo        # JsUInt32.create(), from_napi_value()
src/napi/framework/js_int64.mojo         # JsInt64.create(), from_napi_value()
src/napi/framework/js_null.mojo          # JsNull.create()
src/napi/framework/js_undefined.mojo     # JsUndefined.create()
src/napi/framework/js_array.mojo         # JsArray.create_with_length(), set(), get(), length(), has(), delete_element()
src/napi/framework/js_function.mojo      # JsFunction.call0(), call1(), call2(), create(), create_with_data()
src/napi/framework/js_value.mojo         # js_typeof(), js_type_name(), js_is_array(), js_strict_equals(), js_get_global()
src/napi/framework/handle_scope.mojo     # HandleScope.open(), close()
src/napi/framework/js_promise.mojo       # JsPromise.create(), resolve(), reject()
src/napi/framework/js_arraybuffer.mojo   # JsArrayBuffer.create(), byte_length(), data_ptr(), is_arraybuffer()
src/napi/framework/js_buffer.mojo        # JsBuffer.create(), data_ptr(), length(), is_buffer()
src/napi/framework/js_typedarray.mojo    # JsTypedArray.create_float64/uint8/int32/int8/uint8_clamped/int16/uint16/uint32/float32/bigint64/biguint64(), array_type(), length(), data_ptr(), arraybuffer(), is_typedarray()
src/napi/framework/js_class.mojo         # define_class(), register_instance_method(), register_getter(), register_getter_setter(), register_static_method(), register_static_getter(), register_static_getter_setter(), set_class_prototype()
src/napi/framework/js_ref.mojo           # JsRef.create(), get(), delete(), inc(), dec()
src/napi/framework/escapable_handle_scope.mojo # EscapableHandleScope.open(), escape(), close()
src/napi/framework/js_bigint.mojo        # JsBigInt.from_int64(), from_uint64(), to_int64(), to_uint64(), from_words(), word_count(), to_words()
src/napi/framework/js_date.mojo          # JsDate.create(), timestamp_ms(), is_date()
src/napi/framework/js_symbol.mojo        # JsSymbol.create(), create_for()
src/napi/framework/js_external.mojo      # JsExternal.create(), create_no_release(), get_data(), create_typed[T](), get_typed[T]()
src/napi/framework/instance_data.mojo    # set_instance_data[T](), get_instance_data[T]() — typed per-env singleton
src/napi/framework/js_coerce.mojo        # js_coerce_to_bool(), js_coerce_to_number(), js_coerce_to_string(), js_coerce_to_object()
src/napi/framework/js_exception.mojo     # js_throw(), js_is_exception_pending(), js_get_and_clear_last_exception()
src/napi/framework/js_version.mojo       # get_napi_version(), get_node_version_ptr()
src/napi/framework/js_dataview.mojo      # JsDataView.create(), byte_length(), byte_offset(), data_ptr(), arraybuffer(), is_dataview()
src/napi/framework/threadsafe_function.mojo # ThreadsafeFunction.create(), call_blocking(), call_nonblocking(), acquire(), release(), abort()
src/napi/framework/args.mojo             # CbArgs.get_one(), get_two(), get_this(), get_this_and_one(), argc(), get_argv(), get_data()
src/napi/framework/register.mojo         # fn_ptr(), ModuleBuilder, ClassBuilder — ergonomic registration helpers
src/napi/framework/convert.mojo          # ToJsValue/FromJsValue traits, JsF64/JsI32/JsBool/JsStr/JsRaw wrappers; to/from_js_array_f64/str parametric helpers
src/napi/framework/async_work.mojo       # AsyncWork.queue/resolve/reject_with_error — async work ergonomics
src/napi/framework/runtime.mojo          # init_async_runtime(), parallelize_safe() — async runtime init + safe parallel dispatch
src/napi/framework/js_mojo_array.mojo    # MojoFloat64Array — Mojo-owned Float64 buffer with zero-copy to_js() output
src/napi/framework/js_async_context.mojo # JsAsyncContext — napi_async_init/destroy wrappers
src/napi/framework/callback_scope.mojo   # CallbackScope — napi_open/close_callback_scope wrappers
src/napi/framework/js_host.mojo          # NodeHost — host mode: require(), global_object(), argv(), console_log()
src/exports.toml                         # Function/class/struct declarations for code generator
src/generated/callbacks.mojo             # AUTO-GENERATED callbacks from exports.toml
src/generated/structs.mojo               # AUTO-GENERATED struct definitions + from_js/to_js converters
src/addon/runtime_ops.mojo               # asyncRuntimeInitOk() — makes a silent parallelize() regression testable
src/addon/host_ops.mojo                  # host-mode surface exercised at runtime by tests/host.test.js
examples/host/main.mojo                  # host-mode example; CI runs it via `napi-mojo run`
spike/ffi_probe.mojo                     # FFI contract + origin-migration recipe; BUILT AND RUN in CI
spike/elaboration_probe.mojo             # throwaway: proves per-method lazy elaboration (+ spike/elab_pkg/)
spike/runtime_probe.mojo                 # throwaway: AsyncRT init + parallelize, run from inside Node
spike/keepalive_probe.mojo               # counterfactual behind napi.keepalive; IR-checked in CI
bin/napi-mojo.mjs                        # CLI: init (--host) / generate (--dts) / build (--bundle) / run — wraps the generators + bundle-runtime.sh; e2e-tested in CI
scripts/generate-dts.js                  # auto-generate build/index.d.ts from lib.mojo
scripts/toml-dts.js                      # TOML → .d.ts emitter shared by generate-dts.js and the CLI (one emitter, two callers)
scripts/generate-addon.mjs              # auto-generate callback trampolines from src/exports.toml (bindings-aware)
scripts/benchmark.mjs                   # per-call overhead benchmark (node scripts/benchmark.mjs)
scripts/check-compile-coverage.mjs      # drift guard: every framework def name must be called by the coverage target
scripts/check-keepalive-barrier.mjs     # IR gate: pin_across_ffi still binds, `_ = x^` still does not
tests/                                   # Jest tests — TDD outside-in
tests/compile/framework_coverage.mojo    # compile-only: forces elaboration of every public framework method
tests/codegen/                           # compile-only kitchen sink: every generator template branch (kitchen-sink.toml + build.sh)
```

### Exported addon functions

153 exported functions covering the full N-API surface. See `docs/EXPORTS.md` for the complete table.

## Mojo dialect and FFI rules

> **Current pin: Mojo 1.0.0 (stable), `max = "==26.5.0"`, stable channel
> `https://conda.modular.com/max/`.**
>
> **The framework tracks STABLE Mojo releases, not nightlies.** napi-mojo ships
> source that downstream packages compile against (`@qkstat/retrieve`,
> `@qkstat/embed` build with `-I node_modules/napi-mojo/src`), so the pin is part
> of the public contract: a nightly pin forces every consumer onto that exact
> nightly. The Nightly Canary is the only thing here that touches the nightly
> channel, and it must repoint the **channel**, not just the version — pixi uses
> strict channel priority, so with only the stable channel listed `max = "*"`
> resolves to the newest *stable* build and the canary reports green while
> testing nothing new.
>
> **Upgrading the pin? Read [`docs/toolchain-migrations.md`](docs/toolchain-migrations.md) first.**
> It carries the upgrade runbook, the changelog-diffing recipe (the single
> highest-value step in a bump), the Guard Malloc recipe for GC-time heap
> corruption, and the dated record of every API migration this codebase has
> been through. The rules below are stated in the present tense: they are what
> to write today, not when we adopted it.

### Current spellings

These are the only forms that compile on the pin. Most are renames of an older
API; `docs/toolchain-migrations.md` has the before/after and the reasoning.

- **`def`, never `fn`.** `def` does **not** auto-raise — annotate `raises`
  explicitly. No `@value` decorator: write `__init__`/`__moveinit__`/copy
  constructors. Trait method bodies may use `...`.
- **Stdlib imports take the `std.` prefix**: `from std.ffi import OwnedDLHandle`,
  `from std.collections import Optional`. Heap allocation is
  `from std.memory.alloc import unsafe_alloc` — the `std.memory` package
  `__init__` does not re-export it, so the module path is required.
  **`parallelize` is in MAX, not stdlib**: `from max.algorithm import parallelize`.
- **C-ABI function types need `thin abi("C")`**: `def(args…) thin abi("C") -> R`.
  A bare `def(…) -> X` resolves to a callable trait, not a thin function
  pointer, and fails the `TrivialRegisterPassable` constraint. Parametric
  generics like `parallelize_safe[func: def(Int) capturing -> None]` are not
  C-ABI and stay unannotated. Module entry: `@export("name")` + the `abi("C")`
  effect on the def.
- **Raw-pointer surface**: `Pointer` (not `UnsafePointer`), `.unsafe_bitcast[T]()`,
  `.unsafe_free()`, `unsafe_alloc[T](n)`, `ptr[unsafe_offset=i]`,
  `ptr.unsafe_offset(n)`, `.unsafe_load[width=w](i)`, `unsafe_write`,
  `unsafe_deinit_pointee`. Bare deref `ptr[]` is unchanged. `OpaquePointer` is
  unchanged. `Array[T, N]`, not `InlineArray`. `Span(unsafe_ptr=…)`, not
  `Span(ptr=…)`. `__deinit__` and `Deinitable`, not `__del__` /
  `ImplicitlyDestructible`.
- **Null pointers**: the bare `Pointer[T, O]()` constructor does not compile.
  The uniform target here is **`(unsafe_from_address=Int(0))`** — a *runtime*
  `Int`, because a comptime literal `0` is rejected. It serves both roles this
  codebase needs: write-target output slots and genuine null-sentinel inputs.
  **DO NOT use `.unsafe_dangling()`** — it compiles and yields a real garbage
  non-null pointer; it SIGBUS-crashed 78/80 suites when N-API dereferenced it
  as a null sentinel. `Bool(ptr)` / `if not ptr:` no longer detects null; use
  `Int(ptr) == 0`, or `Optional[…] + is None` for a slot where you must detect a
  written null.
- **`s.byte_length()`**, not `len(s)`, for the UTF-8 byte count N-API wants
  (`s.count_codepoints()` for logical characters).
- **Explicit `__moveinit__` fails in a main-module file** — `'None' has no
  attributes` on `self` — while compiling fine inside the `napi` package.
  `Movable` is auto-derived, so drop the explicit move ctor there. `mojo doc`
  compiles its target as a main module too, which is why three framework files
  are listed in `KNOWN_UNDOCUMENTABLE` in `scripts/check-docstring-coverage.mjs`;
  that gate fails if one ever starts working, so the skip cannot outlive the bug.

### Symbol resolution: `get_symbol`, never `get_function`

`OwnedDLHandle.get_function` is unusable here — it returns an origin-carrying
`_DLCallable` (so it can never be a `NapiBindings` field), and its own docstring
says argument forwarding uses the Mojo calling convention rather than strict
`abi("C")`. Two forms, and you must use the right one:

```mojo
# raw.mojo — when you need a CALLABLE. The reinterpret lives in _sym ONLY.
@always_inline
def _sym[F: TrivialRegisterPassable](ref h: OwnedDLHandle, name: StaticString) raises -> F:
    var opt = h.get_symbol[NoneType](name)
    if opt is None:
        raise Error("napi-mojo: symbol not found: ", name)
    var addr = opt.value()
    return Pointer(to=addr).unsafe_bitcast[F]()[]

# bindings.mojo — when you need a CACHE SLOT. No bitcast at all: get_symbol
# returns the address as a value, and the slot IS that address.
bindings.create_object = _slot(h, "napi_create_object")   # _slot = get_symbol + mut/origin cast to MutAnyOrigin
```

> **The trap that makes `_sym` mandatory — both of these compile:**
>
> - `Pointer(to=addr).unsafe_bitcast[F]()[]` — **correct.** Reinterprets the word *holding* the address.
> - `addr.unsafe_bitcast[F]()[]` — **catastrophically wrong.** Loads the function's first 8 bytes of *machine code* and calls that as a pointer. Jump to garbage, no compiler signal.
>
> Never spell the bitcast inline at a call site. Keeping it in one function is what made 130 edits safe.

`assert_fn_ptr_is_one_word()` in `bindings.mojo` guards that remaining reinterpret
at compile time. `get_symbol` *raises* on a missing symbol (`get_function`
aborted the process), which is why `parallelize_safe` degrades to sequential
instead of killing Node. Validate anything new in `spike/ffi_probe.mojo` before
touching call sites.

`get_symbol` **borrows the handle**, returning `Optional[Pointer[T, origin-of-handle]]`,
so inside a generic `ref h` function the mutability is symbolic and `_slot` must
spell the widening explicitly:
`opt.value().unsafe_mut_cast[True]().unsafe_origin_cast[MutAnyOrigin]()`. That is
sound for symbols specifically — a symbol address is a static code address with
no lifetime, and `OwnedDLHandle()` is `dlopen(NULL)` on a process image that is
never unmapped. It is **not** precedent for `UntrackedOrigin` at transient
slot-cast sites. A *named* library would need an explicit `_ = lib^` keep-alive,
since a resolved pointer does not borrow the handle; there are no named-library
sites left in `src/`.

### Origins: the rules that have actually caused SIGSEGVs

**Struct fields may not expose `AnyOrigin`.** Fields carry a *storage* type:
`src/napi/types.mojo` defines `NapiStore = OpaquePointer[MutUntrackedOrigin]` /
`NapiConstStore = OpaquePointer[ImmUntrackedOrigin]`, and the ten handle aliases
(`NapiEnv`, `NapiValue`, `NapiRef`, `NapiDeferred`, `NapiAsyncWork`,
`NapiHandleScope`, `NapiEscapableHandleScope`, `NapiThreadsafeFunction`,
`NapiAsyncContext`, `NapiCallbackScope`) are all `MutUntrackedOrigin`. A new
field gets one of those. It never gets a literal `MutAnyOrigin`, and it never
gets the `@__allow_legacy_any_origin_fields` decorator — that was a stopgap,
it is gone from the tree (243 → 0), and it must not come back.

**The rule, in one line: storage-type the FIELD; leave every parameter and
return type alone. Narrow at the write into the field
(`.unsafe_origin_cast[MutUntrackedOrigin]()`), widen at the read out of it
(`.as_unsafe_any_origin()`).** Over-applying it to pass-through parameters broke
14 sites once; `ModuleBuilder`/`ClassBuilder` constructors deliberately keep
`data: OpaquePointer[MutAnyOrigin]` so every addon's `register_module`
boilerplate still compiles. `raw.mojo`'s 143 FFI type expressions are spelled
with a **literal** `OpaquePointer[MutAnyOrigin]`, never the aliases, so a future
alias change cannot move them.

**Implicit `Pointer` → `Mut/ImmutAnyOrigin` conversion is gone**, so every site
handing a concrete pointer to a C-FFI signature needs an explicit
`.as_unsafe_any_origin()`. Semantics are unchanged — this is the explicit
spelling of the *same* widening, and it preserves the load-bearing lifetime
extension described next. Fix these from compiler diagnostics, never a global
sed: the mechanical pass mis-places them onto void statements
(`CbArgs.get_argv(...).as_unsafe_any_origin()` — belongs on the `argv` argument)
and onto an enclosing call's result when the un-widened pointer is an inner
argument.

**DO NOT do a naive global `MutAnyOrigin` → `MutUntrackedOrigin` rename.**
`AnyOrigin` silently extends unrelated lifetimes, and that extension is
**load-bearing**: a `Pointer(to=local).unsafe_bitcast[NoneType]()` slot cast
assigned to an `AnyOrigin` var keeps `local`'s (often register-passable,
transient-spill) stack slot alive across the FFI call. Reconstructing the
pointer via `unsafe_from_address=Int(Pointer(to=local))` — the obvious
`UntrackedOrigin` migration — **severs that**, and the slot is freed or reused
before or during the N-API read or write. Confirmed deterministic failures:
`JsFunction.call1/2` and `make_callback` argv (SIGSEGV on garbage napi_value),
`CbArgs.get_argv`'s in/out `argc` capacity (buffer overflow → heap corruption),
`Counter.fromValue` argv (constructs the wrong value), and *ignored output
slots* like `create_buffer`'s `data`. The only correct migration gives the
handle structs a concrete parameter **and** keeps every transient
input/argv/argc/ignored-output local alive across the call.

**`_ = x^` is NOT that keep-alive — it is a no-op for trivially
register-passable types**, which is `UInt`, `Bool`, `Int32` and every
`OpaquePointer` alias including `NapiValue`, i.e. nearly the whole population.
The compiler says so (`warning: transfer from a value of trivial register type
'UInt' has no effect`), and the IR is unambiguous: the `_ = slot^` form loses
its `alloca` entirely, while the pinned form keeps it behind
`call void asm sideeffect "", "r,~{memory}"`. Use **`pin_across_ffi`**
(`src/napi/keepalive.mojo`), which wraps `std.benchmark.keep`: a tracked `ref`
use plus an empty `~{memory}` barrier. It emits no instructions and costs
nothing measurable — it sits right after an opaque external call that already
clobbers memory. `spike/keepalive_probe.mojo` +
`scripts/check-keepalive-barrier.mjs` assert **both halves** of that
counterfactual in CI, including that the unpinned form is still optimized away;
without that half the gate would stop being evidence.

**Status of the migration.** The keep-alives are done: population B is 247 sites
(derive it fresh with `scripts/derive-population-b.mjs` rather than trusting a
number in a document — most are line-wrapped, so a same-line grep undercounts).
19 had no tracked use after the FFI call and carry an explicit barrier; the
other 228 are pinned by a real post-call use, usually `return`. **Still
deferred, and the only part left: the FFI signature flip itself** —
`raw.mojo`'s 143 literal `OpaquePointer[MutAnyOrigin]` type expressions. Every
warning above applies to it in full. Background:
[`docs/plan-origin-migration.md`](docs/plan-origin-migration.md) and
[`docs/handoff-argv-origin-migration.md`](docs/handoff-argv-origin-migration.md).

**On `AnyOrigin` vs `UnsafeAnyOrigin`.** They are now distinct spellings over an
identical MLIR attribute. Upstream's "slated for deprecation and removal" notice
is attached to the `Unsafe*` spelling only, and this codebase is on the other
one; the 26.6 alias-removal sweep deleted `ImmutUnsafeAnyOrigin` while leaving
`ImmutAnyOrigin` alone. A forced migration is possible but is not scheduled, and
nothing in the tree uses a removed spelling.

### Build and codegen invariants

**Codegen moves in lockstep with the code.** `src/generated/` is checked in but `npm run build` never regenerates it, so `scripts/generate-addon.mjs` can silently drift from its own output — it did, twice, and regenerating would have regressed the build (11 templates still emitting the `unsafe_from_address=0` literal form that stopped compiling at dev2026061206, and an async data struct missing `@__allow_legacy_any_origin_fields`). Both had been hand-patched in the *output* and never fed back. Any FFI or idiom migration must patch the templates too. The gate, now in `test.yml`, is:

```bash
npm run generate:addon && git diff --exit-code src/generated/
```

**The drift gate only proves templates that `src/exports.toml` instantiates.** A third latent template bug (bare `_argv` missing `.as_unsafe_any_origin()` in the ≥5-arg path — could never have compiled) shipped through a branch nothing instantiates. `tests/codegen/kitchen-sink.toml` + `tests/codegen/build.sh` close that class: the TOML instantiates every emitter branch (every token in every position, every arity per emitter — the coverage map is in its header), and the CI step "Compile codegen kitchen sink" generates from it into a scratch dir and compiles the result. **A new generator feature gets its kitchen-sink instantiation in the same commit** — a template branch that file does not reach is unverified, exactly like an uncovered framework method.

**`pixi.toml` and `pixi.lock` always move together.** Commit `92bc2d4` bumped the toml alone; `pixi install --locked` then hard-failed on `main`, which took the Nightly Canary down for two weeks (`setup-pixi` runs `--locked` *before* the workflow's own unpin step) and made two open nightly PRs conflict. A lock-less bump is never "just a version string".

**Build flag**: `mojo build --emit shared-lib` — not `-shared`.

### N-API craft rules

These are properties of N-API and of this framework's design, not of any Mojo
version — they have outlived every toolchain bump in
[`docs/toolchain-migrations.md`](docs/toolchain-migrations.md).

**ASAP destruction + string lifetimes**: Mojo's ASAP (eager) destruction frees a value at its last tracked use. Raw pointer derivations (`unsafe_ptr()`) are NOT tracked uses. For FFI string arguments:

- **String literals** for static names: `"propname".unsafe_ptr().unsafe_bitcast[NoneType]()` — static `.rodata` lifetime, never freed. Use `JsString.create_literal` and `JsObject.set_property`.
- **Heap Strings** for dynamic content: bind to a named `var`, derive pointer after binding, keep the var alive past the FFI call. Use `throw_js_error_dynamic` for computed error messages.
- **`StringLiteral` parameter type** on `throw_js_error` enforces compile-time that only literals are passed.

**Function pointers** (confirmed in spike):
```mojo
var fn_ref = my_callback
desc.method = Pointer(to=fn_ref).unsafe_bitcast[OpaquePointer[MutAnyOrigin]]()[]
```

**`NapiPropertyDescriptor` struct layout**: Must exactly match the C definition (8 fields in order: `utf8name`, `name`, `method`, `getter`, `setter`, `value`, `attributes`, `data`). Wrong layout causes silent corruption in `napi_define_properties`.

**Status checking**: Every N-API call returning `NapiStatus` must be immediately passed to `check_status()`. Errors now surface as readable names (e.g., `napi_string_expected`) via `napi_status_name()`.

**String construction from bytes** (Mojo 0.26.3+): Use `String(from_utf8: Span[Byte])` to build a Mojo String from a raw byte buffer — validates UTF-8 and handles all Unicode correctly. The old `chr()` byte-by-byte approach is ASCII-only and broken for multi-byte sequences.

**`StringLiteral` cannot be returned from runtime-branch functions** — it is parameterized on its compile-time value. Use `String` as the return type for any function that picks from multiple string literals at runtime (see `js_type_name`, `napi_status_name`).

**Type checking before reading**: Use `js_typeof(env, val)` to inspect a value's type before attempting to read it. Compare against `NAPI_TYPE_STRING`, `NAPI_TYPE_NUMBER`, etc. from `napi.types`. This enables descriptive type-mismatch errors. Use `js_is_array(env, val)` to distinguish arrays from plain objects (`napi_typeof` returns `object` for both).

**Property reading with napi_value keys**: Use `napi_get_property(env, obj, key_napi_value, result)` (via `JsObject.get()`) instead of `napi_get_named_property(env, obj, c_string, result)` when the key comes from JavaScript. The named variant requires a null-terminated C string; round-tripping a JS string through `JsString.from_napi_value` → `String.unsafe_ptr()` loses the null terminator, causing property lookup failures. Pass the JS string napi_value directly as the key.

**Handle scopes for loops**: When a loop creates many temporary `napi_value` handles (e.g., `mapArray`), wrap each iteration in `HandleScope.open(env)` / `hs.close(env)`. Values set on objects/arrays outside the scope survive closure. The result container (array/object) MUST be created outside the loop's handle scope. Mojo has no RAII — `close()` must be called explicitly.

**Heap allocation** (dev2026080905): Use `unsafe_alloc[T](count)` via `from std.memory.alloc import unsafe_alloc`. The struct must implement `Movable` with `def __moveinit__(out self, deinit take: Self)`. Free with `ptr.unsafe_deinit_pointee()` then `ptr.unsafe_free()`. For destructors use `def __deinit__(deinit self)`.

**Async work callbacks**: The execute callback (`fn(NapiEnv, OpaquePointer[MutAnyOrigin])`) runs on a **worker thread** and MUST NOT call any N-API functions — only pure computation on the heap-allocated data struct. The complete callback (`fn(NapiEnv, NapiStatus, OpaquePointer[MutAnyOrigin])`) runs on the **main thread** and can safely call N-API functions. Both return `None` (not `NapiValue`). The same bitcast pattern works for extracting function pointers.

**Async data struct lifetime**: Heap-allocate with `alloc[T](1)` + `init_pointee_move()`. The data struct was long documented as "simple types only (no Mojo `String` or objects with destructors)"; the generator now emits `String` fields for `returns = "string"`, and the blanket rule was folklore. What is actually load-bearing on the worker thread is narrower and documented elsewhere: **no N-API calls** and **no dlopen/dlsym** (the loader lock — see the `asyncProgress` fix). A Mojo `String` is malloc underneath, the struct is owned exclusively by the async work while it runs, and libuv orders the completion callback after execute, which is the handoff edge; the destructor runs on the main thread when the complete callback deinitializes the struct. Concurrency: `tests/async_stress.test.js` runs many string-returning async calls in flight (mixed sizes, interleaved with numeric async, GC forced between rounds), and the `async-stress` CI job runs it under a checking allocator on both platforms. Guard Malloc **does** engage on GitHub `macos-latest` runners — verified by the `GuardMalloc[node-…]` banner in the job log, which is the thing to check, because macOS strips `DYLD_INSERT_LIBRARIES` for hardened binaries and a stripped insertion is not an error: the suite would run on the normal allocator with the step still green. The job probes for that banner and warns if insertion ever stops working, and always additionally runs the libmalloc knobs (`MallocScribble`, `MallocGuardEdges`, `MallocErrorAbort`, `MallocNanoZone=0`), which the allocator honours with no insertion at all. **Read the banner, not the step timing** — the Guard Malloc run and the plain forced-GC run sit next to each other in the log, and it is easy to read the wrong one's duration (I did). That is allocator-level evidence, not a proof of race-freedom — there is still no thread sanitizer in the loop. Pass `data_ptr.bitcast[NoneType]()` as the `void*` data argument. Clean up in the complete callback with `ptr.destroy_pointee()` + `ptr.free()`. The `NapiAsyncWork` handle has a chicken-and-egg: initialize as `NapiAsyncWork()`, create async work, then write the handle back into the data struct before queuing.

**Promise creation**: `napi_create_promise` returns both a deferred handle and a promise napi_value. Use `JsPromise.create(env)` which pairs them. Each deferred can only be resolved OR rejected once. For rejection, create an Error object with `raw_create_error` (not `throw_js_error`) to get a value without setting a pending exception.

**Class construction (napi_define_class + napi_wrap)**: Use `define_class(env, "Name", constructor_ptr)` to register a class with a bare constructor (property_count=0). Instance methods/getters go on the **prototype** — retrieve via `napi_get_named_property(env, constructor, "prototype", &proto)`, then call `napi_define_properties` on the prototype (NOT the constructor). In the constructor callback, use `CbArgs.get_this()` to get the `this` object, heap-allocate a native data struct with `alloc[T](1)`, and wrap it onto `this` with a finalizer. In method callbacks, retrieve the native pointer via unwrap. The finalizer (`fn(NapiEnv, OpaquePointer, OpaquePointer)`) calls `ptr.destroy_pointee()` + `ptr.free()`.

**Class wrap/unwrap MUST be type-tagged**: `napi_unwrap` alone only proves "some native pointer is wrapped here" — a method borrowed onto a foreign wrapped instance (`Counter.prototype.increment.call(someAnimal)`) reinterprets the wrong struct type: memory corruption reachable from pure JS. Wrap with `wrap_native(b, env, this_val, data_ptr, fin_ptr, tag)` (napi_wrap + napi_type_tag_object; on tag failure it removes the wrap again so the caller still owns the data on raise — no double-free against the finalizer) and unwrap with the `NapiTypeTag`-taking overloads of `unwrap_native[T]` / `unwrap_native_from_this[T]`, which throw a JS TypeError + raise on mismatch. Each class defines two fixed random `comptime` UInt64 tag halves. An object can carry exactly ONE tag (napi_type_tag_object fails on a second), so inheritance is an accept-set at the unwrap site — Animal methods check `check_object_type_tag` for the Animal OR Dog tag, then use the untagged unwrap (`DogData` is layout-compatible with `AnimalData`); Dog-only methods require the Dog tag exactly. The untagged unwrap overloads remain public for exactly this accept-set pattern and are otherwise unverified.

**Pointer origin requirement**: `Pointer[Byte]` cannot infer the mutability parameter in return type position. Use `Pointer[Byte, MutAnyOrigin]` explicitly for data pointer return types (e.g., in Buffer/ArrayBuffer/TypedArray wrappers).

**Jest cross-realm instanceof**: `instanceof TypeError` / `instanceof RangeError` / `instanceof Date` fails in Jest's sandboxed VM (separate realms). Use `try/catch` with `expect(e.name).toBe('TypeError')` instead of `.toThrow(TypeError)`. For Date, use `Object.prototype.toString.call(d) === '[object Date]'` or check for `typeof d.getTime === 'function'`.

**`ref` is a keyword in Mojo**: Cannot use `ref` as a variable/field name. Use `handle`, `napi_ref`, or `js_ref` instead.

**ThreadsafeFunction (TSFN) race condition**: `napi_call_threadsafe_function` queues calls — the `call_js_cb` may not have fired by the time the async work `complete` callback runs. Use `thread_finalize_cb` (not `complete`) to resolve promises, since `thread_finalize_cb` fires only after ALL pending `call_js_cb` invocations complete. The `complete` callback should only store status and call `napi_release_threadsafe_function`.

**`napi_call_threadsafe_function` has no `env` parameter**: Unlike every other N-API function, it takes `(tsfn, data, mode)` only — designed to be called from any thread. `OwnedDLHandle()` works from worker threads since `dlopen(NULL)` is POSIX thread-safe.

**TSFN `call_js_cb` teardown safety**: During Node.js shutdown, `call_js_cb` may receive `env=NULL` and `js_callback=NULL`. Must check before calling N-API functions — only free the data pointer and return.

**napi_create_reference supports all value types at N-API v10+**: At N-API v9 and earlier, only objects, functions, and symbols could be stored in napi_ref. At N-API v10+ (Node.js 22.12+ / 24+), primitives (numbers, strings, booleans) also work — but they do not support weak reference semantics (count reaching 0 releases the value). No wrapping in an object is needed on modern Node.js.

**Variable-length arguments**: Use `CbArgs.argc(env, info)` to query count, `alloc[NapiValue](count)` for the buffer, `CbArgs.get_argv(env, info, count, argv_ptr)` to fill it. The argv_ptr parameter requires `UnsafePointer[NapiValue, MutAnyOrigin]` (explicit origin). `get_argv` returns the invocation's actual argument count — N-API pads argv with `undefined` when fewer were supplied and drops extras when more were, so compare the return value against `count` to detect either; discard with `_ =` when the buffer was pre-sized via `argc()`.

**Function creation with closure data**: `JsFunction.create_with_data(env, name, cb_ptr, data_ptr)` passes an arbitrary data pointer to the callback. Retrieve in the callback via `CbArgs.get_data(env, info)`. Heap-allocated data leaks unless manually freed (no destructor hook on plain functions).

**`node_api_symbol_for`**: Uses `node_api_` prefix (not `napi_`). Takes a C string + length, not a napi_value description.

## Code generator (`exports.toml` → `generate-addon.mjs`)

The TOML code generator reduces N-API boilerplate to near-zero for common patterns. Three main features:

**`mojo_fn` auto-trampolines**: Declare a pure Mojo function in TOML with typed args/returns, and the generator creates a full N-API callback with type checking, arg extraction, return wrapping, and error handling. The pure function lives in `src/addon/user_fns.mojo` (no N-API imports). Supported type tokens: `number`, `string`, `boolean`/`bool`, `int32`, `uint32`, `int64`, `object`, `array`, `number[]`, `string[]`, `any`, `any?`, and any declared struct name. All `mojo_fn` functions must be listed in `extra_imports` in `exports.toml`.

**Nullable returns** (`returns = "number?"`): When a `mojo_fn` function returns `Optional[T]`, the generated callback checks for `None` and returns `JsNull`. TypeScript emits `T | null`. Works with all type tokens.

**Struct-to-object mapping** (`[structs.*]`): Define a named JS object shape with typed fields. The generator produces a Mojo struct (`ConfigData`) + `config_from_js()`/`config_to_js()` converters in `src/generated/structs.mojo`. Struct names become valid type tokens for function args/returns. TypeScript emits `interface` declarations. Pure functions that use struct types go in `src/addon/struct_fns.mojo` (imports from `generated.structs`, avoids circular imports with `generated.callbacks`).

**`mojo_fn` on class members** (`state = "<struct>"`): the generator wraps a heap copy of the struct onto each JS instance and hands every member the unwrapped state. Instance methods, getters and **setters** take it first (`mut` to mutate); a setter additionally declares `type = "<token>"` for the incoming value, which is type-checked with the same `emitTypeCheck` every argument goes through. **Static methods take no state** — there is no instance to unwrap, so their `mojo_fn` is an ordinary pure function over the declared args and works on a class with no `state` at all. Every unwrap is type-tagged, so borrowing a member onto a foreign wrapped instance is a `TypeError` rather than a reinterpret. `Tally` in `src/exports.toml` exercises all of it at runtime (`tests/class_state.test.js`); the kitchen sink covers the same surface at compile time.

**Circular import note**: `callbacks.mojo` imports `user_fns.mojo` and `struct_fns.mojo`. Functions using generated struct types MUST go in `struct_fns.mojo` (not `user_fns.mojo`) because `struct_fns.mojo` imports from `generated.structs` while `callbacks.mojo` imports from `struct_fns.mojo` — no circular dependency. Functions that don't need struct types go in `user_fns.mojo`.

## Development workflow

Follow the RED → GREEN → REFACTOR TDD cycle (see `docs/METHODOLOGY.md`). Every feature starts with a failing Jest test. The spike (`spike/ffi_probe.mojo`) is the exception — it is validated experimentally rather than TDD'd, though CI does now build it and assert both its exports, so it can no longer rot unnoticed.

## Scope: no GPU code here

**napi-mojo is the framework — the Mojo equivalent of `napi-rs` — and GPU workloads live downstream.** `matmulHandle` / `searchHandle` have RAG-specific top-k semantics; `linalg.matmul` and `DeviceContext` are a workload, not a framework primitive. A framework contributor refactoring addon code should never have to understand them.

GPU work lives in **`@qkstat/retrieve`** (`mojo-addon-examples/packages/retrieve`), whose `src/kernels.mojo` holds `matmulHandle`/`searchHandle` and their async forms; `@qkstat/embed` is the sibling consumer (`embedTokens`). Both build against this framework via `-I node_modules/napi-mojo/src`. **Consequence: that package can only adopt a new Mojo nightly after napi-mojo publishes the corresponding framework release** — it compiles against the *published* `src/`, not a local checkout.

The `gpu/` subpackage that briefly lived here was a scaffold (handle registry only — never had matmul or search) and was removed in favour of `@qkstat/retrieve`, which already had the complete surface. Recover it from `89b441c` if ever needed; the older in-tree GPU generation plus the distribution spike are on the `spike/gpu-fatbin` branch. Don't re-vendor GPU code into this repo without revisiting the framework-shaped argument first — the last attempt rotted for three months with no CI and produced a stale binary that read as an `index.node` regression.

**Decided 2026-07-23 — napi-mojo is an outside-facing framework, not personal infrastructure.** This settles the recurring GPU *boundary plumbing* question (distinct from kernels, which unambiguously belong downstream): the "a contributor shouldn't need to understand `DeviceContext`" argument holds, so `napi.framework.gpu` stays deferred at the threshold `docs/plan-typed-helpers.md` already records — **revisit at 6+ cached GPU addons; currently 4**. The counter-argument on file, worth re-reading before reopening this: the framework already ships `parallelize_safe()`, `MojoFloat64Array`, and `data_ptr_float64()`, so the line it actually holds is "the JS↔Mojo boundary, not the compute" — under which GPU plumbing would be in scope. What tips it is the rot risk, not the layering: napi-mojo ships source and Mojo compiles only what's imported, so an unimported `napi.framework.gpu` would never be type-checked. That is exactly how `runtime.mojo` accumulated a latent `dlclose` bug and a dead symbol lookup. **If this is ever reversed, the module ships with a CI compile-check on CPU runners from day one** (GPU builds are AOT PTX codegen — no GPU runner needed), mirroring the `examples/` build step in `test.yml`.

## `parallelize()` runtime init — now on the official API

`parallelize()` inside a dlopen'd `.node` needs `init_async_runtime()` first (no compiler-generated `main()` runs, so the runtime is never set up). `parallelize_safe()` calls it and, on failure, runs the work **sequentially** — correct results, zero thread dispatch, no error anywhere. That silence is the standing hazard: dev2026072306 renamed the private init symbol and the regression survived a full release with the build and the whole suite green.

- **As of dev2026080905, `init_async_runtime()` delegates to `std.runtime.initialize_runtime()`** — an official, idempotent API Mojo 1.0.0 added for exactly this case (shared-lib Mojo called from a non-Mojo host). The hand-rolled resolution of `KGEN_CompilerRT_AsyncRT_GetOrCreateCPUDevice` from `libKGENCompilerRTShared` is gone from `runtime.mojo`, along with its named-library `_ = lib^` keep-alive. `parallelize` itself now comes from `max.algorithm`.
- **`asyncRuntimeInitOk()`** (`src/addon/runtime_ops.mojo`) exports the init result and `tests/runtime.test.js` asserts it is `true`, on both CI matrix OSes. A future breakage fails a test instead of halving throughput in silence. Verified `true` under the new API from inside a real Node process.
- **`spike/runtime_probe.mojo` still probes the raw KGEN entry point** (idempotence, `ParallelismLevel`, a real `parallelize()` result) — useful for diagnosing what the official API does underneath if `runtime.test.js` ever goes red. Its header preserves the hard-won KGEN lore: the exported C wrapper is **nullary** despite its three-argument C++ counterpart, and `nm -gU` cannot see the library's exports (LC_DYLD export trie — use `dyld_info -exports` on macOS, `nm -D` on Linux).

## Host mode — Node as a host for Mojo programs (`napi-mojo run`)

The framework runs in **two directions**. The usual one is an addon: JS calls
Mojo. The other is a Mojo *program* that drives Node and uses npm as its
standard library — `napi-mojo run main.mojo`, where the user writes only
`mojo_main(b, env, ctx)` and the CLI generates the registration wrapper plus a
CJS bootstrap. Design record: [`docs/plan-bidirectional.md`](docs/plan-bidirectional.md).

**The wrapper must be generated NEXT TO the user's entry file.** Mojo resolves
a plain-module import relative to the main module's directory, which is what
makes the generated `from main import mojo_main` work with no extra `-I`
(`examples/tutorial/lib.mojo` shows the same resolution for a subdirectory
package). Moving the wrapper into `.napi-mojo/` would break that import. It is
removed after the run unless `--keep`, and CI asserts the cleanup.

**An entry basename becomes a TOP-LEVEL Mojo module name, so it can be
shadowed by an installed package.** `pipeline.mojo` resolved to MAX's own
`pipeline` package and failed with `package 'pipeline' does not contain
'mojo_main'`; `-I <entryDir>` does not change that in either position. `run`
therefore exposes the entry through a `_napi_mojo_src_<name>.mojo` symlink that
nothing else can claim, and **rewrites the alias out of the compiler's
diagnostics** so errors still name the user's own file (which is why the build
is captured rather than `stdio: 'inherit'`). `examples/host/pipeline.mojo` is
named that deliberately — it is the regression test, and renaming it to
something unique would silently retire the coverage.

**Runs are cached on an input hash** (`.napi-mojo/build.key`), because the
compile is ~1.8s of a ~2s run and re-running is the whole iterate loop. The key
covers the user's tree, the framework tree, the include path, the compiler
command and the CLI version — and that set is COMPLETE precisely because `run`
accepts exactly one `-I`, so no build can pull from a directory the hash did
not see. Adding a second include path to `run` without extending the key would
turn this into a stale-binary trap. `--rebuild` forces a recompile; CI asserts
a second run is byte-identical.

**`require` is module-scoped and unreachable from Mojo.** It is not on
`globalThis`; `process.mainModule.require` resolves under a CJS entry but is
`undefined` under ESM and `node -e`. The bootstrap therefore *hands it in* on
`ctx` (`{ require, argv, cwd }`), built with `module.createRequire` rooted at
the **entry's** directory so the user's `node_modules` and relative paths
resolve. `NodeHost.from_context` validates it. Never "simplify" this to
scavenging for `require` from the global object.

**An `except:` block should throw UNCONDITIONALLY.** `napi_throw_error` is a
documented no-op while an exception is already pending, so one unconditional
`throw_js_error_dynamic(env, String(e))` is correct in both directions: a
JS-side failure keeps its own identity and code (`tests/host.test.js` pins
`MODULE_NOT_FOUND`), while a Mojo-side failure still surfaces instead of
handing JS a bogus null. Returning silently to "protect" a pending error is
the mistake — it makes Mojo-side validation failures invisible.

**Four constraints that are not bugs:**

1. **Mojo has no `await`.** A JS function returning a Promise hands Mojo a
   *pending* Promise it cannot suspend on. Supported: synchronous APIs
   (`readFileSync`), or continuation-passing — build a Mojo callback with
   `JsFunction.create` and give it to `.then()`; `mojo_main` returns and the
   event loop runs it later. **Do not add a blocking await helper**: draining
   the event loop from inside a napi callback re-enters JS on a stack that is
   already inside one. The CPS path is *tested*, not just asserted
   (`then_double_fn` / `deferred_require_fn` in `src/addon/host_ops.mojo`).
   A continuation runs on a later tick, so everything it needs must survive in
   a `napi_ref` and the bindings pointer must travel in its heap payload —
   the same designated-carrier rule as async and TSFN. The continuation frees
   its own payload when it fires.
2. **Mojo-driven loops that call JS need a per-iteration handle scope.** Every
   napi_value is pinned to the enclosing scope until it closes.
   `with_handle_scope[body](b, env)` encapsulates the open/close-on-both-paths
   discipline and preserves the body's error; `tests/host.test.js` guards it
   with a 20,000-iteration loop.
3. **A pending JS exception poisons every subsequent N-API call** with
   `napi_pending_exception`. Bail or clear — do not keep calling.
4. **Argument marshalling dominates, not the call.** Measured on
   darwin-arm64 / Node 24: a `callN(fn, [])` round trip is ~435 ns vs ~375 ns
   for a forward-only `hello()`, but `callN(fn, [1,2,3])` is ~735 ns — about
   **~100 ns per value crossing the boundary**. So host mode is right for
   I/O-bound glue and wrong for a hot numeric loop; cross with few coarse
   values, not many fine ones. `scripts/benchmark.mjs` covers this direction
   (`callN`, `callMethod`, `scopedCall`) and the ceilings gate guards it.

**`call1` is the wrong tool for a method call** — it passes `undefined` as the
receiver, which silently breaks any callee reading `this`. Use
`JsObject.call_method(b, env, name, args)`, or `JsFunction.call_with` when you
need an explicit receiver. `call_n`/`call_with` build argv from a
`List[NapiValue]` and keep it alive past the FFI call with `_ = args` — that
is the argv lifetime hazard this file flags for `call1`/`call2`, and it is
non-negotiable. An empty list passes a genuine null argv, not the data pointer
of an empty `List`.

**Positioning vs. `mojo-http`.** The sibling `mojo-http` is an HTTP/1.1 server
and web framework where **Mojo owns `main()`** and there is no Node. Host mode
is where **Node owns `main()`** and Mojo reaches npm. Complements, not
competitors, and deliberately **no build-time dependency** in either direction
(decided 2026-08-20). `mojo-http`'s `m0-wsgi` embedding CPython is also the
standing answer to "why not embed libnode": that works because CPython exposes
a stable C ABI, and Node's embedder API is C++.

## Elaboration is per-method — cover every new framework method

**Mojo type-checks an imported package's `def` body only when something in the compiled graph calls that exact method.** A body full of hard type errors compiles, packages and publishes as long as nobody calls it. This is not a nightly quirk; it is how 0.5.1 shipped four broken framework modules with `build.sh` green and 609 tests passing (`5161dfc`), and it is why `tests/compile/framework_coverage.mojo` exists.

- **The split is by module ROLE, not by decorator.** Bodies in the *main module* named on the `mojo build` command line are checked eagerly; bodies reached through `-I` as an imported package are not. `spike/elaboration_probe.mojo` demonstrates both halves — re-run it if a nightly ever makes the guarantee suspect. The consequence for design: a coverage target must be a main module that *calls into* `src/napi/framework/`.
- **Struct definitions are lazy too.** `BindingsAndThree` (4 fields) and `JsRaw` (1) were missing `@__allow_legacy_any_origin_fields` and compiled anyway, because nothing constructs them. Do not assume the dev2026062206 field rule has fired on a struct just because the file builds. `NapiNodeVersion.release` was a third instance, found in 2026-08 by the first run of the docstring gate — `mojo doc` elaborates every declaration in the file it opens, so **`node scripts/check-docstring-coverage.mjs` is also a cheap struct-definition checker**. A doc failure in that gate is a finding, not gate noise.
- **Every new public `def` in `src/napi/framework/`, `error.mojo` or `module.mojo` gets a `"""` docstring in the same commit.** `scripts/check-docstring-coverage.mjs` ratchets per-file counts against `scripts/docstring-floor.json` (351 undocumented across 38 modules at adoption); the count may fall — with the floor updated in the same change — but never rise. `raw.mojo` is out of scope: 147 thin FFI wrappers whose docstrings would restate the N-API name.
- **Every new or changed public framework method gets a cover call in the same commit — one per overload.** `scripts/check-compile-coverage.mjs` fails CI on a missing *name*, but it cannot see a missing overload of a name already present. That case is exactly what bit 0.5.1 (both `JsArrayBuffer.create` overloads were broken), so it is on the author and the reviewer.
- **The "Build examples" step is not a substitute.** It raised coverage from module level to some-methods level. The unit of elaboration is the method.
- **Re-validate the guard after changing how it roots elaboration:**

  ```bash
  git revert --no-commit 5161dfc
  pixi run mojo build --emit shared-lib -I src \
    tests/compile/framework_coverage.mojo -o /tmp/gate.so   # MUST FAIL, at exactly 6 sites
  git reset --hard HEAD
  ```

  Recorded result (2026-07-24): fails with exactly 6 errors — `args.mojo:232`, `js_arraybuffer.mojo:33` and `:49`, `js_bigint.mojo:108` and `:124`, `js_external.mojo:146` — while `build.sh` and all 612 tests stay **green**. A guard that does not fail on the known bug is worthless.

The target's first run surfaced **61** further latent errors across 18 files, all shipped in 0.5.1: 52 missing `.as_unsafe_any_origin()`, 5 missing field decorators, 2 `len(String)` calls (now a hard **error**, not the warning documented above), and 3 env-only overloads that `convert.mojo` had always called but which were never implemented — that last class had never worked in any release.

## Repository / CI contract

**`main` is protected.** Required status checks: `test (macos-latest)` and `test (ubuntu-latest)`. No review requirement (solo repo — you cannot approve your own PR). `strict` is off, so a PR need not be up to date with `main` before merging; turn it on if concurrent PRs become common.

**Auto-merge is enabled** — `gh pr merge <N> --merge --auto` arms a PR to merge itself when the required checks pass. Before branch protection existed this was actively unsafe: with no *required* checks, GitHub auto-merge fires as soon as a PR is mergeable, i.e. immediately, without waiting for CI. The two settings only make sense together.

**`enforce_admins` is off, deliberately.** `ubuntu-latest` only runs on `pull_request` events (see the matrix in `test.yml`), so a direct push to `main` can never satisfy that required check. Without the admin bypass you would be locked out of pushing to your own default branch.

**Never add `paths-ignore` to the `pull_request` trigger in `test.yml`.** A filtered-out workflow reports *no checks at all* rather than passing ones, so a docs-only PR would never satisfy the required checks and would be permanently unmergeable except by admin bypass. `paths-ignore` on `push` is fine and is kept — nothing gates a push. The asymmetry is intentional; the comment in `test.yml` says so at the point of temptation.

**Stacked PRs need a nudge.** `test.yml` only fires on PRs targeting `main`, so a PR based on another branch gets *zero* checks and will sit there looking `CLEAN` and mergeable with nothing behind it. Retargeting it after the parent merges does **not** start a run either — a base change emits `edited`, which is not in the default `pull_request` trigger set. Close and reopen the PR to fire `reopened`.

**Per-call overhead gate** (`benchmark` job, non-required, both OSes): `scripts/check-benchmark.mjs` runs `scripts/benchmark.mjs --json` and compares median ns/call against per-platform ceilings in `scripts/benchmark-ceilings.json`. Ceilings carry **4x headroom**, so it catches an order-of-magnitude regression — specifically a per-call `OwnedDLHandle()`+dlsym sneaking back onto the hot path, which is the thing cached `NapiBindings` exists to prevent and which nothing else in CI would notice — and explicitly *not* a 10% one. Every run prints observed/ceiling as a percentage so creep is visible while still passing. Reseed with `node scripts/check-benchmark.mjs --update` **on a runner of that platform** (the two platforms are not comparable). Non-required because a timing measurement must never block a merge.

**Nightly Canary** runs Tue/Fri 22:00 UTC on `macos-latest` + `ubuntu-latest`, unpinning to `max = "*"` to catch breaking nightlies early. Dispatch it on demand with `gh workflow run nightly-canary.yml --ref main`; it accepts an optional `max_version` input for bisection probes. Green runs record the resolved version to the job summary — that, not the gitignored `.last-good-nightly`, is the portable record.
