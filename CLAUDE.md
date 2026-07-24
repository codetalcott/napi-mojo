# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**napi-mojo** — the Mojo equivalent of Rust's `napi-rs`. A framework for building Node.js native addons in Mojo via the Node-API (N-API) C interface. All planned phases complete — 140 exported functions + 3 classes covering the full N-API surface (609 tests): primitive types, integer types (Int32/UInt32/Int64), object property reading/enumeration/deletion, function calling/creation, array mapping with handle scopes, variable-length arguments, type checking, error propagation (Error/TypeError/RangeError/SyntaxError), promises (create/resolve/reject), async work (worker thread execution + cancellation), ThreadsafeFunction (call JS from worker threads), ArrayBuffer (including external/Mojo-owned memory), Buffer, TypedArray, DataView, class construction (wrap/unwrap, prototype methods, getter/setter, static methods, class inheritance via prototype chain), persistent references, escapable handle scopes, global object access, BigInt (including arbitrary-precision word arrays), Date, Symbol, strict equality, instanceof, object freeze/seal/detach, prototype access, array element has/delete, external data (opaque native pointers with GC finalizers), napi_add_finalizer on arbitrary objects, instance data (per-env singleton), environment cleanup hooks (sync + async), type coercion (Boolean/Number/String/Object), TypeScript definition generation with JSDoc, exception handling (throw/catch any value), property set/has by napi_value key (symbol keys), version info (N-API + Node.js), script execution, async context + callback scope, type tagging, and external memory tracking. Higher-level API includes `fn_ptr()`, `ModuleBuilder`/`ClassBuilder` for ergonomic registration, `unwrap_native[T]()` for class methods, `ToJsValue`/`FromJsValue` conversion traits, parametric array helpers (`to/from_js_array_f64/str`), an `AsyncWork` helper for ergonomic async work (promise + queue + resolve/reject), a TOML code generator (`scripts/generate-addon.mjs` + `src/exports.toml`) with `mojo_fn` auto-trampolines, nullable returns (`Optional[T]` → `T | null`), struct-to-object mapping (`[structs.*]` → bidirectional converters), async/class generation, and auto-generated TypeScript `.d.ts` with interfaces, `MojoFloat64Array` for zero-copy TypedArray output, `parallelize_safe()` for SIMD parallel computation with automatic runtime init, **typed handles** (`JsExternal.create_typed[T]` / `get_typed[T]`, `set_instance_data[T]` / `get_instance_data[T]` with generic finalizers), and **cached NapiBindings** — all 142 N-API function pointers resolved once at module init, passed through callback data to every entry-point callback (173-389 ns/call, zero per-call dlsym).

## Commands

```bash
pixi run bash build.sh               # compile src/lib.mojo → build/index.node
npm test                              # run all Jest tests (609 tests; gpu/ excluded)
npm run test:gc                       # run GC finalizer tests (requires --expose-gc)
npx jest tests/basic.test.js          # run a single test file
npm run generate:addon                # regenerate src/generated/ from src/exports.toml
node scripts/benchmark.mjs            # per-call overhead benchmark

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

**Callbacks that DON'T use cached bindings** (must use old `OwnedDLHandle` path):

- `except:` blocks (fallback when bindings retrieval itself fails)
- Dynamically created inner callbacks (`inner_callback_fn`, `inner_adder_fn`) — their data pointer holds captured values, not bindings
- Async complete/TSFN/finalizer callbacks — fixed signatures without `info` parameter

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
src/napi/bindings.mojo                   # NapiBindings struct (134 cached fn ptrs + registry), init_bindings(), Bindings type alias
src/napi/raw.mojo                        # OwnedDLHandle symbol resolution + bindings-accepting overloads
src/napi/error.mojo                      # napi_status_name(), check_status(), throw_js_error(), throw_js_error_dynamic(), throw_js_type_error(), throw_js_range_error()
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
src/exports.toml                         # Function/class/struct declarations for code generator
src/generated/callbacks.mojo             # AUTO-GENERATED callbacks from exports.toml
src/generated/structs.mojo               # AUTO-GENERATED struct definitions + from_js/to_js converters
spike/ffi_probe.mojo                     # throwaway FFI validation (run on new machine / Mojo upgrade)
scripts/generate-dts.js                  # auto-generate build/index.d.ts from lib.mojo
scripts/generate-addon.mjs              # auto-generate callback trampolines from src/exports.toml (bindings-aware)
scripts/benchmark.mjs                   # per-call overhead benchmark (node scripts/benchmark.mjs)
tests/                                   # Jest tests — TDD outside-in
```

### Exported addon functions

140 exported functions covering the full N-API surface. See `docs/EXPORTS.md` for the complete table.

## Critical Mojo FFI rules

> **Mojo nightly changelog:** <https://mojolang.org/releases/nightly/> — consult this when a build breaks after a nightly bump, before reverse-engineering the diagnostic. Each rule below is dated to the nightly that introduced it; cross-reference there for the upstream rationale.
>
> **Diff the changelog, don't read it.** The web page is a single cumulative section for the whole release cycle, so it can't tell you what changed *since your pin*. The same file lives in the modular monorepo at `modular/modular:mojo/docs/nightly-changelog.md` and is diffable — this is the single highest-value step in a nightly upgrade:
>
> ```bash
> # find the changelog commit at/just-before your current pin's date
> gh api 'repos/modular/modular/commits?path=mojo/docs/nightly-changelog.md&until=<PIN_DATE>&per_page=3' \
>   --jq '.[] | "\(.sha) \(.commit.author.date)"'
> # then diff that revision against main
> diff <(gh api "repos/modular/modular/contents/mojo/docs/nightly-changelog.md?ref=<SHA>" --jq .content | base64 -d) \
>      <(gh api "repos/modular/modular/contents/mojo/docs/nightly-changelog.md?ref=main"   --jq .content | base64 -d)
> ```
>
> The stdlib source is in the same repo (`mojo/stdlib/std/…`), so you can read the *actual* new signature of anything the changelog mentions — and check whether the replacement API already exists on your current pin. That last check is what let the dev2026072306 upgrade land its 274-site FFI rewrite before bumping.

**Nightly upgrade runbook** (learned from the dev2026062306 → dev2026072306 jump, which spanned a month and landed with 618 tests green):

1. **Land the previous good state first.** Never start an upgrade on top of an unmerged/unverified pin. Merge the last known-good nightly to `main` so you have a clean base and a rollback point.
2. **Diff the changelog** (above) to get the actual breaking-change list. You are not flying blind after this, which is what makes a single big jump safer than stepping through every intermediate nightly (intermediates carry transient breakage a later one repairs).
3. **Check whether the new API already exists on your current pin.** If it does, do the risky migration on the compiler you already trust and prove it green *before* bumping. This decouples "my refactor broke it" from "the compiler broke it" — the single most valuable scheduling decision available.
4. **Validate any new idiom in `spike/ffi_probe.mojo` before mass-editing.** Minutes of work; it de-risked a 274-site edit.
5. **Bump, then fix hard errors before deprecation warnings.** Doing renames first floods the build log while you still need to read it.
6. **Drive mechanical fixes from compiler diagnostics, not global sed.** Build → patch exactly the flagged locations → rebuild → repeat. The origin migration converged 351 → 187 → 65 → 35 → 30, then ~19 needed hand placement. A blind rewrite in this area is how the earlier SIGSEGVs happened.
7. **Smoke before jest**: `node -e "require('./build/index.node').hello()"`. Module registration uses only the env-only N-API path, so `require()` alone loads fine even with a corrupt bindings cache — the first *call* is the first cached-slot dereference.
8. **Guard Malloc after any pointer-lifetime change** (recipe below).
9. `pixi.toml` and `pixi.lock` **always move together** (see the rule at the end of this section).

**`bump-nightly.sh --rollback` is a no-op** — its Python block only prints, then `exit 0` before the sed logic it claims to delegate to. Roll back manually: `git checkout pixi.toml pixi.lock && pixi install --locked`. `.last-good-nightly` is gitignored, so it is a local-machine note only, not a portable anchor; the committed `pixi.toml` pin is the real record.

**`def` replaces `fn`** (dev2026032105+): `fn` keyword is no longer supported. All function/method declarations must use `def`. Example: `def my_func(arg: Int) -> Int:`. The code generator (`generate-addon.mjs`) and DTS generator (`generate-dts.js`) have been updated accordingly.

**`@value` removed** (dev2026032105+): The `@value` decorator is no longer recognized. Structs must provide explicit `__init__`, `__moveinit__`, and copy constructors. Simple single-field wrapper structs (like `JsI32`, `JsBool`, `JsRaw`) now have explicit `__init__` methods.

**Trait `...` body works** (dev2026032105+): Trait method bodies can now use `...` (ellipsis) instead of `raise Error("abstract")`. The `-> Self` return type issue with `...` is fixed. `Self(...)` also works reliably in static trait methods.

**Imports** (2026 nightly, 0.26.3+): All stdlib imports require `std.` prefix: `from std.ffi import OwnedDLHandle`, `from std.memory import alloc`, `from std.collections import Optional`, `from std.algorithm import parallelize`. The old bare paths (`from ffi import`, `from memory import`, etc.) are deprecated.

**C-ABI function types require `thin abi("C")`** (dev2026043006 / Mojo 1.0.0b1): `std.ffi.OwnedDLHandle.get_function[...]` and typed `bitcast[def(...) -> X]` constrain their type parameter to `TrivialRegisterPassable`. As of Mojo 1.0.0b1, a bare `def(args...) -> X` resolves to `AnyTrait[def(...) -> X]` (a callable trait, not a thin function pointer) and fails the constraint. The fix is to add the `thin` effect alongside `abi("C")`: `def(args...) thin abi("C") -> ReturnType`. Applies to all 416 sites across `src/napi/raw.mojo` (272), `src/napi/bindings.mojo` (143), and `src/napi/framework/runtime.mojo` (1). Parametric generics like `parallelize_safe[func: def(Int) capturing -> None]` are not C-ABI and stay unannotated. (Older `dev2026040905+` rule that introduced `abi("C")` is superseded — the `thin` effect is now also required.)

**`def` no longer auto-raises** (Mojo 1.0.0b1): `def` and `fn` now have identical semantics — non-raising by default. Functions that raise must be annotated `def name(...) raises:` explicitly. Existing `def f() raises:` declarations are unaffected.

**`UnsafePointer()` non-null** (Mojo 1.0.0b1 → 1.0.0b3.dev2026061206): The bare default constructor `UnsafePointer[T, O]()` and aliases (`OpaquePointer[MutAnyOrigin]()`, `OpaquePointer[ImmutAnyOrigin]()`, `NapiValue()`, `NapiAsyncWork()`, `NapiDeferred()`, `NapiHandleScope()`, `NapiEscapableHandleScope()`, `NapiThreadsafeFunction()`, `NapiAsyncContext()`, `NapiCallbackScope()`, `NapiRef()`) **no longer compile at all** on `dev2026051501+` — error: `no matching function in initialization`. On 1.0.0b1 they warned but still returned address 0 at runtime. Migration patterns:

- **Uniform migration target for napi-mojo: `(unsafe_from_address=Int(0))`** (was `(unsafe_from_address=0)` before the 26.5 / `1.0.0b3.dev2026061206` nightly). The codebase used the bare ctor indiscriminately for both write-target output slots AND null-sentinel inputs to N-API (null `code` for `napi_create_error`, null `async_resource` for `napi_create_async_work`, etc.). An address-0 pointer preserves the runtime semantics for both: write-target slots get overwritten through the slot's address regardless of the slot's value, and null-sentinel inputs need exactly address 0. Example: `var result = NapiValue(unsafe_from_address=Int(0))`.
- **`unsafe_from_address=0` with a comptime *literal* `0` is rejected as of `1.0.0b3.dev2026061206`** — error: `UnsafePointer is non-nullable. To construct a null pointer, use Optional[UnsafePointer]`. The constraint only fires for the comptime-foldable literal; passing a *runtime* `Int` 0 binds the non-constrained runtime overload and still yields a genuine address-0 pointer (verified `Int(ptr) == 0`). The fix is therefore the surgical `=0)` → `=Int(0))` across all ~790 sites — type-preserving at every call site, bit-identical behavior, no slot-vs-sentinel reclassification needed (the whole point of the uniform target). All 618 tests pass on the new nightly. Prefer `Int(0)` over the heavier `Optional[NapiValue]` niche-layout migration unless a site genuinely needs to *detect* a written null.
- **DO NOT use `.unsafe_dangling()`** — it compiles but produces a real garbage non-null pointer. SIGBUS-crashed 78/80 test suites during the initial migration attempt when N-API dereferenced it as a null sentinel. The upstream-recommended pattern is wrong for this codebase's call-site mix. See [[mojo_dev2026051501_migration]] memory.
- For slots where N-API may write null and you need to detect it: use `Optional[UnsafePointer[...]]` and check with `is None` / `value()`. The Optional uses niche layout so it's bit-compatible with raw `void*` for N-API write-through.
- Long-term refactor (not blocking): change wrapper signatures for genuinely null-sentinel inputs (`null_code`, `null_resource`, etc.) to take `Optional[NapiValue]` so the intent is type-encoded. Tracked but deferred — `(unsafe_from_address=Int(0))` remains sufficient. (The earlier note that a future nightly might remove `(unsafe_from_address=0)` came true in `1.0.0b3.dev2026061206`; the runtime-`Int(0)` form above resolves it without the Optional refactor.)
- `Bool(ptr)` / `if not ptr:` no longer detects null since pointers are non-null by design (compiler may elide the check). Use `Int(ptr) == 0` for parameters whose type is fixed by C-ABI callback signatures, or `Optional[...] + is None` for locals.

**`unsafe_ptr().value()` removed** (Mojo 1.0.0b1): `DeviceBuffer.unsafe_ptr()` (and similar from MAX `gpu` package) now returns the typed `UnsafePointer` directly, no `.value()` wrapper. Drop the call: `buf.unsafe_ptr().bitcast[Byte]()` instead of `buf.unsafe_ptr().value().bitcast[Byte]()`.

**`String.__len__()` is discouraged** (dev2026040905+): Use `s.byte_length()` to get the UTF-8 byte count for N-API calls (`napi_create_string_utf8` expects bytes), or `s.count_codepoints()` for logical character count. The old `len(s)` still compiles but emits a warning.

**Struct fields cannot expose `AnyOrigin`** (dev2026062206 / max 26.5): A struct field may no longer hide `Mut/ImmutAnyOrigin` (a.k.a. `UnsafeAnyOrigin`) in its type — error: `struct fields cannot expose AnyOrigin in their type`. This hits every napi-mojo handle field: `NapiBindings`' 143 `OpaquePointer[MutAnyOrigin]` fn-ptrs, `NapiPropertyDescriptor`, every `Js*` wrapper's `value: NapiValue`, the async/class data structs — 217 fields / 36 files. **Current fix (stopgap):** annotate each field with `@__allow_legacy_any_origin_fields` (field-level decorator, directly above the `var`). It keeps the existing `AnyOrigin` semantics and is the changelog-sanctioned escape hatch, but is unstable and slated for removal. The implicit `UnsafePointer → Mut/ImmutUnsafeAnyOrigin` conversion at the slot-cast sites is now *deprecated* too (warnings, still compiles).

  **DO NOT do a naive global `MutAnyOrigin → MutUntrackedOrigin` rename.** `AnyOrigin` "silently extends unrelated lifetimes" — that extension is **load-bearing** here. A `UnsafePointer(to=local).bitcast[NoneType]()` slot cast assigned to an `AnyOrigin` var keeps `local`'s (often *register-passable, transient-spill*) stack slot alive across the FFI call. Reconstructing the pointer via `unsafe_from_address=Int(UnsafePointer(to=local))` (the obvious `UntrackedOrigin` migration) **severs that** → the slot is freed/reused before/during the N-API read or write. Confirmed deterministic failures: `JsFunction.call1/2` & `make_callback` argv (SIGSEGV reading garbage napi_value), `CbArgs.get_argv`'s in/out `argc` capacity (buffer overflow → heap corruption), `Counter.fromValue` argv (constructs wrong value), and *ignored output slots* like `create_buffer`'s `data` / `create_buffer_copy`'s `copy_data` (napi writes a pointer into a reused slot). The proper migration is therefore: give the handle structs a concrete/`UntrackedOrigin` parameter **and** keep every transient input/argv/argc/ignored-output local alive across the FFI call with a non-elidable `_ = x^` move-discard (copy register-passable borrowed params into an owned local first). Deferred behind the decorator stopgap.

  **Pre-existing finalizer UAF (FIXED — was misfiled as an "unrelated flake"):** the nondeterministic `SIGABRT`/`SIGTRAP` in `node::PerIsolatePlatformData::RunForegroundTask` / libmalloc (GC-time, no addon frame in the *original* crash, ~1/8 serial / ~1/4 under Guard Malloc) was a real use-after-free in `addon/typed_helpers_ops.mojo`, NOT a migration artifact (hence it reproduced on `dev2026061206` too). `TypedPayload` stored a raw `Int64*` into a JS `ArrayBuffer`'s backing store and incremented it in `__del__`, which runs from the external's GC finalizer — but the external held no reference to the ArrayBuffer, so V8 could free the backing store first, and the finalizer's `counter[] += 1` then scribbled on freed heap (silent corruption under normal malloc; the malloc freelist checker tripped later during an unrelated GC `operator new`, which is why the faulting frame was always in node/V8, never the addon). Fix: `createTypedPayload` now takes a strong `napi_ref` on the ArrayBuffer and a bespoke finalizer releases it *after* the increment (generic `create_typed` finalizer can't release a ref). **Diagnostic recipe that localized it** (reuse for any GC-time heap corruption): run the suite via *direct* `node ./node_modules/jest/bin/jest.js --runInBand` (NOT `npx` — it drops `DYLD_INSERT_LIBRARIES`) under `DYLD_INSERT_LIBRARIES=/usr/lib/libgmalloc.dylib` (add `MALLOC_STRICT_SIZE=1` to catch <16-byte overruns), looped inside `lldb -b -o run -k "thread backtrace all" -k quit` until it faults — Guard Malloc turns the deferred freelist trap into an immediate `EXC_BAD_ACCESS` at the actual bad access, putting the offending `index.node` finalizer frame at the top of the backtrace.

  **Running this recipe (notes from the dev2026072306 upgrade).** Two things will waste your time if you don't know them:

  - **`lldb` can't attach to the Homebrew `node`** (`attach failed … could not pause execution`) — SIP/hardened runtime. Run the suite under Guard Malloc directly and read the exit code instead: `139` = SIGSEGV. Bisect *which* suite faults with `--shard=1/4 … 4/4`, then run that shard's files one at a time (`jest --listTests --shard=4/4` gives the list).
  - **`gpu/` is excluded from the root jest run** (`jest.testPathIgnorePatterns` in `package.json`). It loads `gpu/build/gpu.node`, a stale binary last built 2026-05-01 against a 26.4-era nightly that faults under `MALLOC_STRICT_SIZE=1` — a red herring that cost real time to chase, since no `src/` change can affect it. `gpu/` keeps its own `npm test`; rebuild it before trusting any result from there.

    Baseline as of dev2026072306: **609 tests pass clean** under the full recipe, no manual exclusion needed:

    ```bash
    DYLD_INSERT_LIBRARIES=/usr/lib/libgmalloc.dylib MALLOC_STRICT_SIZE=1 \
      node ./node_modules/jest/bin/jest.js --runInBand
    ```

**`OwnedDLHandle.get_function` is no longer usable for C FFI** (dev2026072306): its parameter is now the *return type* rather than the full function-pointer type, and it returns `_DLCallable[R, origin_of(self)]` — a callable carrying a borrow of the handle. Two independent reasons this cannot work here:

- **It can't be cached.** `_DLCallable` is origin-carrying, so it cannot be a `NapiBindings` field — that is exactly the "struct fields cannot expose AnyOrigin" rule below. Architecturally incompatible with the 142-slot cache, full stop.
- **It isn't C ABI.** Its own docstring: *"Argument forwarding uses the Mojo calling convention, not strict `abi("C")` … For any C function that takes or returns a struct by value, this path would silently corrupt the call."*

**All 274 sites migrated to `get_symbol` instead**, in two distinct forms — use the right one:

```mojo
# raw.mojo — when you need a CALLABLE. The reinterpret lives in _sym ONLY.
@always_inline
def _sym[F: TrivialRegisterPassable](ref h: OwnedDLHandle, name: StaticString) raises -> F:
    var opt = h.get_symbol[NoneType](name)
    if opt is None:
        raise Error("napi-mojo: symbol not found: ", name)
    var addr = opt.value()
    return UnsafePointer(to=addr).bitcast[F]()[]

# bindings.mojo — when you need a CACHE SLOT. No bitcast at all: get_symbol
# returns the address as a value, and the slot IS that address.
bindings.create_object = _slot(h, "napi_create_object")   # _slot = get_symbol + as_unsafe_any_origin
```

> **The trap that makes `_sym` mandatory — both of these compile:**
>
> - `UnsafePointer(to=addr).bitcast[F]()[]` — **correct.** Reinterprets the word *holding* the address.
> - `addr.bitcast[F]()[]` — **catastrophically wrong.** Loads the function's first 8 bytes of *machine code* and calls that as a pointer. Jump to garbage, no compiler signal.
>
> Never spell the bitcast inline at a call site. Keeping it in one function is what made 130 edits safe.

`get_symbol` also *raises* on a missing symbol where `get_function` aborted the process — strictly better (e.g. `parallelize_safe` now degrades to sequential instead of killing Node). Migrating `bindings.mojo` was a net safety win beyond the mechanical fix: the old code took the address of a local holding the resolved pointer and reinterpreted that word, so a future fat function reference would have stored the wrong word *and still compiled*. `assert_fn_ptr_is_one_word()` in `bindings.mojo` now guards the remaining `_sym` reinterpret at compile time. Validated end-to-end in `spike/ffi_probe.mojo` — run it before touching FFI call sites.

**Named libraries need an explicit keep-alive** (dev2026072306): a resolved symbol pointer does *not* borrow the handle, so ASAP destruction can `dlclose` the library at the handle's last tracked use — the lookup — before you call through the pointer. `framework/runtime.mojo` (the only named-library site, `libKGENCompilerRTShared`) now ends with `_ = lib^` after `create_rt()`. The other 273 sites are immune because `OwnedDLHandle()` is `dlopen(NULL)` and the host process image is never unmapped. Note `runtime.mojo` is **not reachable from `src/lib.mojo`** — only `examples/vectors-addon.mojo` imports it — so `build.sh` does not type-check it; compile a driver with `-I src` to verify changes there.

**Implicit `UnsafePointer` → `Mut/ImmutAnyOrigin` conversion removed** (dev2026072306, warning since dev2026062206): C-FFI signatures fix their origin at `MutAnyOrigin`/`ImmutAnyOrigin`, so every site handing them a concrete pointer now needs an explicit **`.as_unsafe_any_origin()`**. This was 351 errors across 23 files.

- **Semantics are unchanged.** `as_unsafe_any_origin()` is the explicit spelling of the *same* widening that used to be implicit. The load-bearing lifetime extension documented in the AnyOrigin rule below is preserved — this is **not** the `MutUntrackedOrigin` substitution that caused SIGSEGVs, and that warning still stands in full.
- **`get_symbol` returns `MutUntrackedOrigin`**, and `_slot` widens it. That is sound for a reason specific to symbols — a symbol address is a static code address with no lifetime — and is **not** precedent for using `UntrackedOrigin` at transient slot-cast sites.
- **Fix from compiler diagnostics, never a global sed.** Watch for two placement mistakes the mechanical pass makes: appending to a void statement (`CbArgs.get_argv(...).as_unsafe_any_origin()` — belongs on the `argv` argument), and appending to an enclosing call's result when the un-widened pointer is an *inner* argument.

**`Span(ptr=…)` → `Span(unsafe_ptr=…)`** (dev2026072306): hard rename, 10 sites (`framework/js_string.mojo` ×6 — four of them line-wrapped so `ptr=` sits on its own line and a single-line regex misses them — `addon/class_animal.mojo` ×3, `addon/user_fns.mojo` ×1).

**`ImplicitlyDestructible` → `ImplicitlyDeletable`** (dev2026062206, migrated dev2026072306): trait renamed; old name warned. Also migrated at the same time: `init_pointee_move` → **`unsafe_write`** (25 sites) and `destroy_pointee` → **`unsafe_deinit_pointee`** (22 sites). The build is now warning-clean.

**Explicit `__moveinit__` fails in a main-module file** (dev2026072306): `def __moveinit__(out self, deinit take: Self)` errors with `'None' has no attributes` on `self` when the struct is declared in a file compiled as the entry module, while the identical spelling compiles inside the `napi` package (`bindings.mojo` still declares its own). `Movable` is auto-derived, so dropping the explicit move ctor is the workaround — `spike/ffi_probe.mojo` does. Don't "fix" one context to match the other without re-checking both.

**Codegen moves in lockstep with the code.** `src/generated/` is checked in but `npm run build` never regenerates it, so `scripts/generate-addon.mjs` can silently drift from its own output — it did, twice, and regenerating would have regressed the build (11 templates still emitting the `unsafe_from_address=0` literal form that stopped compiling at dev2026061206, and an async data struct missing `@__allow_legacy_any_origin_fields`). Both had been hand-patched in the *output* and never fed back. Any FFI or idiom migration must patch the templates too. The gate, now in `test.yml`, is:

```bash
npm run generate:addon && git diff --exit-code src/generated/
```

**`pixi.toml` and `pixi.lock` always move together.** Commit `92bc2d4` bumped the toml alone; `pixi install --locked` then hard-failed on `main`, which took the Nightly Canary down for two weeks (`setup-pixi` runs `--locked` *before* the workflow's own unpin step) and made two open nightly PRs conflict. A lock-less bump is never "just a version string".

**Build flag**: `mojo build --emit shared-lib` — not `-shared`.

**ASAP destruction + string lifetimes**: Mojo's ASAP (eager) destruction frees a value at its last tracked use. Raw pointer derivations (`unsafe_ptr()`) are NOT tracked uses. For FFI string arguments:

- **String literals** for static names: `"propname".unsafe_ptr().bitcast[NoneType]()` — static `.rodata` lifetime, never freed. Use `JsString.create_literal` and `JsObject.set_property`.
- **Heap Strings** for dynamic content: bind to a named `var`, derive pointer after binding, keep the var alive past the FFI call. Use `throw_js_error_dynamic` for computed error messages.
- **`StringLiteral` parameter type** on `throw_js_error` enforces compile-time that only literals are passed.

**Function pointers** (confirmed in spike):
```mojo
var fn_ref = my_callback
desc.method = UnsafePointer(to=fn_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
```

**`NapiPropertyDescriptor` struct layout**: Must exactly match the C definition (8 fields in order: `utf8name`, `name`, `method`, `getter`, `setter`, `value`, `attributes`, `data`). Wrong layout causes silent corruption in `napi_define_properties`.

**Status checking**: Every N-API call returning `NapiStatus` must be immediately passed to `check_status()`. Errors now surface as readable names (e.g., `napi_string_expected`) via `napi_status_name()`.

**String construction from bytes** (Mojo 0.26.3+): Use `String(from_utf8: Span[Byte])` to build a Mojo String from a raw byte buffer — validates UTF-8 and handles all Unicode correctly. The old `chr()` byte-by-byte approach is ASCII-only and broken for multi-byte sequences.

**`StringLiteral` cannot be returned from runtime-branch functions** — it is parameterized on its compile-time value. Use `String` as the return type for any function that picks from multiple string literals at runtime (see `js_type_name`, `napi_status_name`).

**Type checking before reading**: Use `js_typeof(env, val)` to inspect a value's type before attempting to read it. Compare against `NAPI_TYPE_STRING`, `NAPI_TYPE_NUMBER`, etc. from `napi.types`. This enables descriptive type-mismatch errors. Use `js_is_array(env, val)` to distinguish arrays from plain objects (`napi_typeof` returns `object` for both).

**Property reading with napi_value keys**: Use `napi_get_property(env, obj, key_napi_value, result)` (via `JsObject.get()`) instead of `napi_get_named_property(env, obj, c_string, result)` when the key comes from JavaScript. The named variant requires a null-terminated C string; round-tripping a JS string through `JsString.from_napi_value` → `String.unsafe_ptr()` loses the null terminator, causing property lookup failures. Pass the JS string napi_value directly as the key.

**Handle scopes for loops**: When a loop creates many temporary `napi_value` handles (e.g., `mapArray`), wrap each iteration in `HandleScope.open(env)` / `hs.close(env)`. Values set on objects/arrays outside the scope survive closure. The result container (array/object) MUST be created outside the loop's handle scope. Mojo has no RAII — `close()` must be called explicitly.

**Heap allocation** (Mojo 0.26.3+): Use `alloc[T](count)` from `memory` module (NOT `UnsafePointer[T].alloc(count)` — that syntax was removed). The struct must implement `Movable` with `fn __moveinit__(out self, deinit take: Self)`. Free with `ptr.destroy_pointee()` then `ptr.free()`. For destructors use `fn __del__(deinit self)` — the `owned` keyword has been removed.

**Async work callbacks**: The execute callback (`fn(NapiEnv, OpaquePointer[MutAnyOrigin])`) runs on a **worker thread** and MUST NOT call any N-API functions — only pure computation on the heap-allocated data struct. The complete callback (`fn(NapiEnv, NapiStatus, OpaquePointer[MutAnyOrigin])`) runs on the **main thread** and can safely call N-API functions. Both return `None` (not `NapiValue`). The same bitcast pattern works for extracting function pointers.

**Async data struct lifetime**: Heap-allocate with `alloc[T](1)` + `init_pointee_move()`. The data struct must contain only simple types (no Mojo `String` or objects with destructors) since the execute callback runs on a worker thread. Pass `data_ptr.bitcast[NoneType]()` as the `void*` data argument. Clean up in the complete callback with `ptr.destroy_pointee()` + `ptr.free()`. The `NapiAsyncWork` handle has a chicken-and-egg: initialize as `NapiAsyncWork()`, create async work, then write the handle back into the data struct before queuing.

**Promise creation**: `napi_create_promise` returns both a deferred handle and a promise napi_value. Use `JsPromise.create(env)` which pairs them. Each deferred can only be resolved OR rejected once. For rejection, create an Error object with `raw_create_error` (not `throw_js_error`) to get a value without setting a pending exception.

**Class construction (napi_define_class + napi_wrap)**: Use `define_class(env, "Name", constructor_ptr)` to register a class with a bare constructor (property_count=0). Instance methods/getters go on the **prototype** — retrieve via `napi_get_named_property(env, constructor, "prototype", &proto)`, then call `napi_define_properties` on the prototype (NOT the constructor). In the constructor callback, use `CbArgs.get_this()` to get the `this` object, heap-allocate a native data struct with `alloc[T](1)`, and `napi_wrap` it onto `this` with a finalizer. In method callbacks, use `napi_unwrap` to retrieve the native pointer. The finalizer (`fn(NapiEnv, OpaquePointer, OpaquePointer)`) calls `ptr.destroy_pointee()` + `ptr.free()`.

**UnsafePointer origin requirement**: In Mojo v26.2, `UnsafePointer[Byte]` cannot infer the mutability parameter in return type position. Use `UnsafePointer[Byte, MutAnyOrigin]` explicitly for data pointer return types (e.g., in Buffer/ArrayBuffer/TypedArray wrappers).

**Jest cross-realm instanceof**: `instanceof TypeError` / `instanceof RangeError` / `instanceof Date` fails in Jest's sandboxed VM (separate realms). Use `try/catch` with `expect(e.name).toBe('TypeError')` instead of `.toThrow(TypeError)`. For Date, use `Object.prototype.toString.call(d) === '[object Date]'` or check for `typeof d.getTime === 'function'`.

**`ref` is a keyword in Mojo**: Cannot use `ref` as a variable/field name. Use `handle`, `napi_ref`, or `js_ref` instead.

**ThreadsafeFunction (TSFN) race condition**: `napi_call_threadsafe_function` queues calls — the `call_js_cb` may not have fired by the time the async work `complete` callback runs. Use `thread_finalize_cb` (not `complete`) to resolve promises, since `thread_finalize_cb` fires only after ALL pending `call_js_cb` invocations complete. The `complete` callback should only store status and call `napi_release_threadsafe_function`.

**`napi_call_threadsafe_function` has no `env` parameter**: Unlike every other N-API function, it takes `(tsfn, data, mode)` only — designed to be called from any thread. `OwnedDLHandle()` works from worker threads since `dlopen(NULL)` is POSIX thread-safe.

**TSFN `call_js_cb` teardown safety**: During Node.js shutdown, `call_js_cb` may receive `env=NULL` and `js_callback=NULL`. Must check before calling N-API functions — only free the data pointer and return.

**napi_create_reference supports all value types at N-API v10+**: At N-API v9 and earlier, only objects, functions, and symbols could be stored in napi_ref. At N-API v10+ (Node.js 22.12+ / 24+), primitives (numbers, strings, booleans) also work — but they do not support weak reference semantics (count reaching 0 releases the value). No wrapping in an object is needed on modern Node.js.

**Variable-length arguments**: Use `CbArgs.argc(env, info)` to query count, `alloc[NapiValue](count)` for the buffer, `CbArgs.get_argv(env, info, count, argv_ptr)` to fill it. The argv_ptr parameter requires `UnsafePointer[NapiValue, MutAnyOrigin]` (explicit origin).

**Function creation with closure data**: `JsFunction.create_with_data(env, name, cb_ptr, data_ptr)` passes an arbitrary data pointer to the callback. Retrieve in the callback via `CbArgs.get_data(env, info)`. Heap-allocated data leaks unless manually freed (no destructor hook on plain functions).

**`node_api_symbol_for`**: Uses `node_api_` prefix (not `napi_`). Takes a C string + length, not a napi_value description.

## Code generator (`exports.toml` → `generate-addon.mjs`)

The TOML code generator reduces N-API boilerplate to near-zero for common patterns. Three main features:

**`mojo_fn` auto-trampolines**: Declare a pure Mojo function in TOML with typed args/returns, and the generator creates a full N-API callback with type checking, arg extraction, return wrapping, and error handling. The pure function lives in `src/addon/user_fns.mojo` (no N-API imports). Supported type tokens: `number`, `string`, `boolean`/`bool`, `int32`, `uint32`, `int64`, `object`, `array`, `number[]`, `string[]`, `any`, `any?`, and any declared struct name. All `mojo_fn` functions must be listed in `extra_imports` in `exports.toml`.

**Nullable returns** (`returns = "number?"`): When a `mojo_fn` function returns `Optional[T]`, the generated callback checks for `None` and returns `JsNull`. TypeScript emits `T | null`. Works with all type tokens.

**Struct-to-object mapping** (`[structs.*]`): Define a named JS object shape with typed fields. The generator produces a Mojo struct (`ConfigData`) + `config_from_js()`/`config_to_js()` converters in `src/generated/structs.mojo`. Struct names become valid type tokens for function args/returns. TypeScript emits `interface` declarations. Pure functions that use struct types go in `src/addon/struct_fns.mojo` (imports from `generated.structs`, avoids circular imports with `generated.callbacks`).

**Circular import note**: `callbacks.mojo` imports `user_fns.mojo` and `struct_fns.mojo`. Functions using generated struct types MUST go in `struct_fns.mojo` (not `user_fns.mojo`) because `struct_fns.mojo` imports from `generated.structs` while `callbacks.mojo` imports from `struct_fns.mojo` — no circular dependency. Functions that don't need struct types go in `user_fns.mojo`.

## Development workflow

Follow the RED → GREEN → REFACTOR TDD cycle (see `docs/METHODOLOGY.md`). Every feature starts with a failing Jest test. The spike (`spike/ffi_probe.mojo`) is the exception — it is validated experimentally, not by tests.

## Repository / CI contract

**`main` is protected.** Required status checks: `test (macos-latest)` and `test (ubuntu-latest)`. No review requirement (solo repo — you cannot approve your own PR). `strict` is off, so a PR need not be up to date with `main` before merging; turn it on if concurrent PRs become common.

**Auto-merge is enabled** — `gh pr merge <N> --merge --auto` arms a PR to merge itself when the required checks pass. Before branch protection existed this was actively unsafe: with no *required* checks, GitHub auto-merge fires as soon as a PR is mergeable, i.e. immediately, without waiting for CI. The two settings only make sense together.

**`enforce_admins` is off, deliberately.** `ubuntu-latest` only runs on `pull_request` events (see the matrix in `test.yml`), so a direct push to `main` can never satisfy that required check. Without the admin bypass you would be locked out of pushing to your own default branch.

**Never add `paths-ignore` to the `pull_request` trigger in `test.yml`.** A filtered-out workflow reports *no checks at all* rather than passing ones, so a docs-only PR would never satisfy the required checks and would be permanently unmergeable except by admin bypass. `paths-ignore` on `push` is fine and is kept — nothing gates a push. The asymmetry is intentional; the comment in `test.yml` says so at the point of temptation.

**Stacked PRs need a nudge.** `test.yml` only fires on PRs targeting `main`, so a PR based on another branch gets *zero* checks and will sit there looking `CLEAN` and mergeable with nothing behind it. Retargeting it after the parent merges does **not** start a run either — a base change emits `edited`, which is not in the default `pull_request` trigger set. Close and reopen the PR to fire `reopened`.

**Nightly Canary** runs Tue/Fri 22:00 UTC on `macos-latest` + `ubuntu-latest`, unpinning to `max = "*"` to catch breaking nightlies early. Dispatch it on demand with `gh workflow run nightly-canary.yml --ref main`; it accepts an optional `max_version` input for bisection probes. Green runs record the resolved version to the job summary — that, not the gitignored `.last-good-nightly`, is the portable record.
