# Mojo dialect and FFI rules for napi-mojo

<!-- GENERATED from CLAUDE.md by scripts/generate-rules-extract.mjs. Do not edit;
     edit CLAUDE.md and run `npm run generate:rules`. CI fails if this file is stale. -->

> This is the "Mojo dialect and FFI rules" section of the napi-mojo repository's
> `CLAUDE.md`, extracted verbatim so it ships with the package: it is the same text
> the framework's own maintainers and agents work from. It is written for
> someone changing napi-mojo itself, so some rules cite files that are not in
> the npm tarball; the links point at the repository.

## Mojo dialect and FFI rules

> **Current pin: Mojo 1.1.0 (stable), `max = "==26.6.0"`, stable channel
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
> **Upgrading the pin? Read [`docs/toolchain-migrations.md`](https://github.com/codetalcott/napi-mojo/blob/main/docs/toolchain-migrations.md) first.**
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
  **`parallelize` is in MAX, not stdlib**: `from max.algorithm import parallelize`,
  and as of MAX 26.6 it takes its work function as a **unified closure
  argument** — `parallelize(func, n)`, not `parallelize[func](n)`.
- **C-ABI function types need `thin abi("C")`**: `def(args…) thin abi("C") -> R`.
  A bare `def(…) -> X` resolves to a callable trait, not a thin function
  pointer, and fails the `TrivialRegisterPassable` constraint. Parametric
  generics like `parallelize_safe[func: def(Int) capturing[_] -> None]` are not
  C-ABI and stay unannotated. Module entry: `@export("name")` + the `abi("C")`
  effect on the def.
- **A legacy closure parameter is `capturing[_]`, never bare `capturing`, and
  its closure needs `@__parameter`.** Both halves are load-bearing and neither
  is optional:
  - **Bare `capturing` silently reads a DEAD STACK SLOT** on 1.1.0 — no warning,
    no error. A closure declared in a loop over a loop-local read `4460971520`
    then `0`, `0` where `capturing[_]` reads `0`, `1`, `2`. In real code this
    surfaced as `napi_invalid_arg`, because the captured `JsFunction` was
    garbage. `capturing[_]` binds the captured values' origins so their slots
    stay alive; the bare form tracks nothing. This is the same class of hazard
    as `_ = x^` being a no-op — a spelling that looks right and keeps nothing
    alive. Ordering is fixed: `def () raises capturing[_] -> None`
    (`capturing[_] raises` does not parse).
  - **`@__parameter`** (renamed from `@parameter` in 1.1.0) is required on a
    closure passed as a parameter, unless it declares the `capturing` effect
    itself (`def worker(i: Int) capturing:`). Without either, the call fails to
    convert. `@parameter` still works but is deprecated.
  - **New code should prefer a UNIFIED closure** — passed as an argument with an
    explicit capture list (`def w(i: Int) {imm a, mut b}:`, `{imm}` for all) and
    no decorator. That is where the stdlib and MAX are going; `with_handle_scope`
    and `parallelize_safe` keep legacy signatures only because downstream
    packages compile against them.
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
def _sym[F: TrivialRegisterPassable](
    ref h: OwnedDLHandle, name: StaticString
) raises -> F:
    var opt = h.get_symbol[NoneType](name)
    if opt is None:
        raise Error("napi-mojo: symbol not found: ", name)
    var addr = opt.value()
    return Pointer(to=addr).unsafe_bitcast[F]()[]

# bindings.mojo — when you need a CACHE SLOT. No bitcast at all: get_symbol
# returns the address as a value, and the slot IS that address (_slot is
# get_symbol plus the mut/origin cast to MutAnyOrigin).
bindings.create_object = _slot(h, "napi_create_object")
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
other 228 are pinned by a real post-call use, usually `return`.

**The signature flip is PART DONE and the rest is still deferred, deliberately.**
Of `raw.mojo`'s 147 wrappers, the **19 handle-only ones are flipped** — every
argument a V8 handle already aliased `MutUntrackedOrigin`, nothing anywhere
forming a `Pointer(to=<local>)`, so there was no lifetime for `AnyOrigin` to
extend and the widening calls were pure ceremony. The remaining **128 take a
raw pointer parameter**, which is precisely the argv / in-out `argc` / output-slot
path population B lives on; every warning above applies to those in full and
they are NOT to be swept.

**Do not size the rest from "143 type expressions."** That is the count of FFI
type declarations, and they are not independent: the FFI type, the wrapper
parameter and the caller's widening are one chain, so flipping the type without
the callers only relocates the cast and removes no dependency on the implicit
extension. Measured 2026-08-21, the remainder is ~775 `MutAnyOrigin`
occurrences and ~493 `as_unsafe_any_origin()` sites across 40+ files in `src/`,
plus `examples/`, `spike/`, `tests/compile/` and the code generator. It is
elective — there is no upstream forcing function (see below) — and it wants
batches of ~10 wrappers with the full verification stack between each, not
momentum. Background:
[`docs/plan-origin-migration.md`](https://github.com/codetalcott/napi-mojo/blob/main/docs/plan-origin-migration.md) and
[`docs/handoff-argv-origin-migration.md`](https://github.com/codetalcott/napi-mojo/blob/main/docs/handoff-argv-origin-migration.md).

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

**Warnings are errors at every CI compile of our own Mojo.** `build.sh` and `tests/codegen/build.sh` default to `--Werror`, and the inline builds in `test.yml` (examples, FFI probe, coverage target) pass it. Twenty-seven deprecations sat in the 1.1.0 bump's build output until someone read the log, because a warning had never failed anything. `NAPI_MOJO_WERROR=0` opts out for a toolchain bump — the runbook fixes hard errors before deprecations, and the flag would make them the same thing; the Nightly Canary sets it and counts warnings into its job summary instead, since a deprecation on a nightly is the early signal it exists for. Two compiles are deliberately outside the flag: `spike/keepalive_probe.mojo`, whose `_ = slot^` warning IS the counterfactual `check-keepalive-barrier.mjs` asserts, and consumer builds through the CLI (`napi-mojo build` / `run`), which compile a user's code. `scripts/check-werror.mjs` proves both halves in CI — a deprecated spelling inside an imported package warns without the flag and fails with it — so the flag cannot go decorative without a red step. This also settles "which build is authoritative for a warning inventory": all of them, and none is allowed to differ from zero.

**Doc code samples are verbatim from compiled source.** `scripts/check-doc-samples.mjs` splits every Mojo fence in README, TUTORIAL, CONTRIBUTING and this file into blank-line stanzas (a leading comment is a caption) and requires each to appear verbatim in a file `test.yml` compiles; a snippet with no compilable home is fenced `mojo fragment` and is counted in the output. Quote real code rather than typing an illustration — a fabricated `process_config_pure` lived in the README with no source anywhere. Verbatim is not elaborated: a framework body nobody calls still compiles unchecked, and the coverage target below is the answer to that, not this gate. `docs/MOJO-RULES.md` is the "Mojo dialect and FFI rules" section of this file, generated by `scripts/generate-rules-extract.mjs` so it ships in the npm package (`CLAUDE.md` itself does not); `npm run generate:rules` after editing that section, and `--check` gates the copy.

**Build flag**: `mojo build --emit shared-lib` — not `-shared`.

### N-API craft rules

These are properties of N-API and of this framework's design, not of any Mojo
version — they have outlived every toolchain bump in
[`docs/toolchain-migrations.md`](https://github.com/codetalcott/napi-mojo/blob/main/docs/toolchain-migrations.md).

**ASAP destruction + string lifetimes**: Mojo's ASAP (eager) destruction frees a value at its last tracked use. Raw pointer derivations (`unsafe_ptr()`) are NOT tracked uses. For FFI string arguments:

- **String literals** for static names: `"propname".ptr().unsafe_bitcast[NoneType]()` — static `.rodata` lifetime, never freed. Use `JsString.create_literal` and `JsObject.set_property`. **`StringLiteral.unsafe_ptr()` is deprecated in favour of `ptr()`** (1.1.0: these types always hold a live value, so the pointer is never unsafe); the same rename applies to `CStringSpan`, `ArcPointer` and `OwnedPointer`. `String.unsafe_ptr()` and `StaticString.unsafe_ptr()` are NOT renamed — 38 of the 54 `unsafe_ptr()` sites in `src/` moved, the rest are `String`/`StaticString` and must stay, so drive this from compiler diagnostics rather than a global sed.
- **Heap Strings** for dynamic content: bind to a named `var`, derive pointer after binding, keep the var alive past the FFI call. Use `throw_js_error_dynamic` for computed error messages.
- **A Mojo `String` is NOT NUL-terminated.** Any N-API parameter typed `const char*` with no length beside it — the `msg` and `code` of every `napi_throw_*`, the `utf8name` of `napi_*_named_property` — reads to the first zero byte, so a `String`'s `unsafe_ptr()` hands it whatever the heap holds next. Every generated type-mismatch error carried trailing garbage (`got numberuffer`) through 0.15.1, invisible because the tests asserted with `toContain`. Call `as_c_string_span()` on a `var` copy (it appends the terminator in place) and pass `.ptr()` of that; the eight `throw_js_*_dynamic` helpers in `error.mojo` do. Length-taking calls (`napi_create_string_utf8`, `napi_create_function`, `node_api_symbol_for`) are unaffected. Tests for a computed message assert the whole string with `toBe`, never `toContain` — and note that even an exact assertion catches this only probabilistically (reverting all eight terminations fails 2 of 6), because the tail is whatever the allocator left adjacent.
- **`StringLiteral` parameter type** on `throw_js_error` enforces compile-time that only literals are passed.

**Function pointers** (confirmed in spike):
```mojo fragment
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

**Function creation with closure data**: `JsFunction.create_with_data(b, env, name, cb_ptr, data)` passes an arbitrary data pointer to the callback; retrieve it with `CbArgs.get_data(env, info)`. That form frees nothing, so it is only for data that outlives every function (the bindings pointer). **Heap data goes through the `finalize_cb` overload**, `create_with_data(b, env, name, cb_ptr, data, finalize_cb)`, which adopts `data` on every path — the collector runs `finalize_cb` once the function is gone, or it runs before the call raises. Never free closure data when the callback fires: a function may be called many times or never. `createAdder` leaked its capture on every call through 0.15.0 for exactly this reason; `tests/finalizer_gc.test.js` now observes the capture being freed, and that it is NOT freed while the function is reachable (an early free SIGBUSes the suite). For promise continuations use `JsPromise.on_settled`, which is built on the same overload.

**`node_api_symbol_for`**: Uses `node_api_` prefix (not `napi_`). Takes a C string + length, not a napi_value description.
