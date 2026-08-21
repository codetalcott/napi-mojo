# Toolchain migrations and the upgrade runbook

**This is the history and the procedure, not the rules.** The rules you must
follow when writing code today live in `CLAUDE.md` under "Mojo dialect and FFI
rules", stated in the present tense with no dates. This file exists so that
section does not have to carry nine nightlies' worth of adoption narrative in
every agent's context window — but nothing here was deleted, and several of
these entries are the only written record of why a rule exists.

**Read this file when you are:**

- bumping the Mojo pin (stable release or nightly probe) — start at the
  runbook, then the changelog-diffing recipe above it;
- trying to work out *why* a rule in CLAUDE.md is phrased the way it is,
  especially the origin/keep-alive rules, which are the ones that have
  actually caused SIGSEGVs here;
- diagnosing GC-time heap corruption — the Guard Malloc recipe is in the
  AnyOrigin section;
- reading a diagnostic that mentions an API this codebase has already
  migrated off (`get_function`, `@value`, `InlineArray`, `UnsafePointer`,
  `init_pointee_move`, …) and wanting the replacement plus the reason.

**Dating caveat, which is easy to get backwards.** Entries are dated to the
nightly at which *this project adopted* the change, not to the release that
ships it. Most of the "dev2026080905 era" rules are in fact Mojo 1.0.0
content. See the changelog-rotation note below.

---

> **Current pin: Mojo 1.0.0 (stable), `max = "==26.5.0"` from the stable `https://conda.modular.com/max/` channel.** Adopted 2026-08-12, moving off the `26.6.0.dev2026080905` nightly.
>
> **The framework tracks STABLE Mojo releases, not nightlies.** napi-mojo ships source that downstream packages compile against (`@qkstat/retrieve` and `@qkstat/embed` build with `-I node_modules/napi-mojo/src`), so the pin is part of the public contract: a nightly pin forces every consumer onto that exact nightly. The Nightly Canary keeps its job — early warning for the *next* release — and is now the only thing in the repo that touches the nightly channel.
>
> **The canary must repoint the CHANNEL, not just the version.** pixi uses strict channel priority, so with only the stable channel listed, `max = "*"` resolves to the newest *stable* build: the canary would keep reporting green while testing nothing new. `nightly-canary.yml` swaps the channel first and then hard-fails if `max-nightly` is not present in `pixi.toml`.
>
> **Rules below are dated to the nightly that introduced them.** That dating is a history of *when we adopted the change*, not a claim about which release ships it — most of the "dev2026080905 era" rules (the `unsafe_` rename, `get_symbol` borrowing the handle, `as_unsafe_any_origin()`, `Deinitable`/`__deinit__`, `InlineArray`→`Array`, `initialize_runtime()`) are in fact **Mojo 1.0.0 content**. See the changelog-rotation note below for why that is easy to get backwards.
>
> **Mojo nightly changelog:** <https://mojolang.org/releases/nightly/> — consult this when a build breaks after a nightly bump, before reverse-engineering the diagnostic. Cross-reference there for the upstream rationale.
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
>
> **Diff BOTH changelogs — content ROTATES OUT of the nightly file at release close.** `nightly-changelog.md` only holds the *current, unreleased* cycle; when a release ships, its entries move to `mojo/docs/releases/vX.Y.Z.md` and the nightly file is truncated to near-empty. So a `nightly-changelog.md` that does not mention a change is **not** evidence the change is unreleased — it is usually evidence the change *shipped*. Grep the release file too:
>
> ```bash
> gh api 'repos/modular/modular/contents/mojo/docs/releases?ref=main' --jq '.[].name' | tail
> gh api "repos/modular/modular/contents/mojo/docs/releases/v1.0.0.md?ref=main" --jq .content | base64 -d > v1.0.0.md
> ```
>
> This is exactly what settled the 1.0.0 adoption: every API this codebase had migrated for under "dev2026080905" turned out to live in `releases/v1.0.0.md`, while the 26.6 nightly file held only a handful of *later* changes (`@parameter`→`@__parameter` on parametric closures, `memcmp`→`unsafe_memcmp`, removal of the temporary `InlineArray` alias — **none of which this codebase uses**). That is what made moving from a 26.6 nightly *back* to 1.0.0 stable a zero-source-change operation instead of a 1,500-site revert.

**Toolchain upgrade runbook** — applies to a stable-release bump and a nightly probe alike (learned from the dev2026062306 → dev2026072306 jump, which spanned a month and landed with 618 tests green; re-validated on the 1.0.0 stable adoption, which landed with 641 tests green and **zero source changes**):

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

**Struct fields cannot expose `AnyOrigin`** (dev2026062206 / max 26.5): A struct field may no longer hide `Mut/ImmutAnyOrigin` (a.k.a. `UnsafeAnyOrigin`) in its type — error: `struct fields cannot expose AnyOrigin in their type`. This hits every napi-mojo handle field: `NapiBindings`' 143 `OpaquePointer[MutAnyOrigin]` fn-ptrs, `NapiPropertyDescriptor`, every `Js*` wrapper's `value: NapiValue`, the async/class data structs — 217 fields / 36 files. **MIGRATED IN 0.10.0 — the decorator is gone from the tree (243 → 0) and must not come back.** The stopgap was `@__allow_legacy_any_origin_fields` on each field; the fix is that **struct fields carry a storage type, not `AnyOrigin`**. `src/napi/types.mojo` defines `NapiStore = OpaquePointer[MutUntrackedOrigin]` / `NapiConstStore = OpaquePointer[ImmUntrackedOrigin]`, and the ten handle aliases (`NapiEnv`, `NapiValue`, `NapiRef`, `NapiDeferred`, `NapiAsyncWork`, `NapiHandleScope`, `NapiEscapableHandleScope`, `NapiThreadsafeFunction`, `NapiAsyncContext`, `NapiCallbackScope`) are all `MutUntrackedOrigin` now. A new field gets one of those; it never gets a literal `MutAnyOrigin` and never gets the decorator. The implicit `UnsafePointer → Mut/ImmutUnsafeAnyOrigin` conversion at the slot-cast sites is *deprecated* too (warnings, still compiles), which is why the widening is spelled explicitly everywhere.

  **The rule, in one line: storage-type the FIELD; leave every parameter and return type alone. Narrow at the write into the field (`.unsafe_origin_cast[MutUntrackedOrigin]()`), widen at the read out of it (`.as_unsafe_any_origin()`).** Over-applying it to pass-through parameters broke 14 sites once; `ModuleBuilder`/`ClassBuilder` constructors deliberately keep `data: OpaquePointer[MutAnyOrigin]` so every addon's `register_module` boilerplate still compiles.

  **Why this was safe — see `docs/plan-origin-migration.md` for the full record.** The decorator population and the population the SIGSEGV warning below is about are **disjoint**: all 243 decorated *fields* point at V8-owned handles, static code addresses or `unsafe_alloc` blocks (no field anywhere is assigned from `Pointer(to=<local>)` — `grep -rn "self\.[a-z_]* = Pointer(to=" src/ examples/` is empty), while the 159 dangerous sites are inline `Pointer(to=<local>)…as_unsafe_any_origin()` *arguments*. So fields can move to `MutUntrackedOrigin` **provided the `comptime *Fn = def(...) thin abi("C")` types keep `MutAnyOrigin`**; a field feeding such a signature just gains `.as_unsafe_any_origin()`. `spike/ffi_probe.mojo` carries that recipe decorator-free and CI builds and runs it (`originProbe PASS 4/4` — a create→read-back→byte-compare through four separate output slots, plus a comptime assert that the change is layout-neutral and `NapiPropertyDescriptor` is still 64 bytes). **The rule that must not be broken: do not also move the FFI parameter origins to Untracked** — that is exactly the rename below. `raw.mojo`'s 143 FFI type expressions are therefore spelled with a **literal** `OpaquePointer[MutAnyOrigin]`, never the aliases, so that a future alias change cannot move them; a no-op commit pinned them that way before the flip. The flip earned its keep immediately: making the handle aliases a distinct type turned `raw_create_promise`'s `deferred` — an *output slot* being passed as if it were a handle — from silent into a compile error.

  **DO NOT do a naive global `MutAnyOrigin → MutUntrackedOrigin` rename.** `AnyOrigin` "silently extends unrelated lifetimes" — that extension is **load-bearing** here. A `UnsafePointer(to=local).bitcast[NoneType]()` slot cast assigned to an `AnyOrigin` var keeps `local`'s (often *register-passable, transient-spill*) stack slot alive across the FFI call. Reconstructing the pointer via `unsafe_from_address=Int(UnsafePointer(to=local))` (the obvious `UntrackedOrigin` migration) **severs that** → the slot is freed/reused before/during the N-API read or write. Confirmed deterministic failures: `JsFunction.call1/2` & `make_callback` argv (SIGSEGV reading garbage napi_value), `CbArgs.get_argv`'s in/out `argc` capacity (buffer overflow → heap corruption), `Counter.fromValue` argv (constructs wrong value), and *ignored output slots* like `create_buffer`'s `data` / `create_buffer_copy`'s `copy_data` (napi writes a pointer into a reused slot). The proper migration is therefore: give the handle structs a concrete/`UntrackedOrigin` parameter **and** keep every transient input/argv/argc/ignored-output local alive across the FFI call with a non-elidable keep-alive.

  **The keep-alives are DONE; only the signature flip is left.** Population B is 247 sites today (derive it fresh — most are line-wrapped, so a same-line grep finds ~153; see `docs/handoff-argv-origin-migration.md` for the false-positive classes). Of those, **19 had no tracked use after the FFI call** and now carry an explicit barrier; the other 228 are pinned by a real post-call use, usually `return`.

  **`_ = x^` is NOT the mechanism — it is a no-op for trivially register-passable types**, which is `UInt`, `Bool`, `Int32` and every `OpaquePointer` alias including `NapiValue`, i.e. nearly this whole population. The compiler says so (`warning: transfer from a value of trivial register type 'UInt' has no effect and can be removed`), and the IR is unambiguous: the `_ = slot^` form loses its `alloca` entirely while the pinned form keeps it behind `call void asm sideeffect "", "r,~{memory}"`. Had the flip landed on the move-discard, every site would have *looked* migrated while N-API wrote into a reclaimed slot — the silent class, at scale. Use **`pin_across_ffi`** (`src/napi/keepalive.mojo`), which wraps `std.benchmark.keep`: `ref [origin]` (a tracked use) plus an empty `~{memory}` `has_side_effect` asm barrier. It emits no instructions and measured zero cost — it sits right after an opaque external call that already clobbers memory. `spike/keepalive_probe.mojo` + `scripts/check-keepalive-barrier.mjs` assert both halves of that counterfactual in CI, including that the unpinned form still gets optimized away; without that half the gate would stop being evidence.

  Because `keep` takes `ref [origin]`, **the "copy register-passable borrowed params into an owned local first" step is retired** — pinning a borrowed param pins the same `alloca` that `Pointer(to=param)` materialised (verified in IR). Note also that a borrowed *non*-register-passable struct (e.g. `define_property`'s `desc`) is memory-passed, so its storage is the caller's and the borrow already spans the nested FFI call.

  **Still deferred, and now the only part left**: the FFI signature flip itself — `raw.mojo`'s 143 literal `OpaquePointer[MutAnyOrigin]` type expressions. This warning applies to it in full.

  **Pre-existing finalizer UAF (FIXED — was misfiled as an "unrelated flake"):** the nondeterministic `SIGABRT`/`SIGTRAP` in `node::PerIsolatePlatformData::RunForegroundTask` / libmalloc (GC-time, no addon frame in the *original* crash, ~1/8 serial / ~1/4 under Guard Malloc) was a real use-after-free in `addon/typed_helpers_ops.mojo`, NOT a migration artifact (hence it reproduced on `dev2026061206` too). `TypedPayload` stored a raw `Int64*` into a JS `ArrayBuffer`'s backing store and incremented it in `__del__`, which runs from the external's GC finalizer — but the external held no reference to the ArrayBuffer, so V8 could free the backing store first, and the finalizer's `counter[] += 1` then scribbled on freed heap (silent corruption under normal malloc; the malloc freelist checker tripped later during an unrelated GC `operator new`, which is why the faulting frame was always in node/V8, never the addon). Fix: `createTypedPayload` now takes a strong `napi_ref` on the ArrayBuffer and a bespoke finalizer releases it *after* the increment (generic `create_typed` finalizer can't release a ref). **Diagnostic recipe that localized it** (reuse for any GC-time heap corruption): run the suite via *direct* `node ./node_modules/jest/bin/jest.js --runInBand` (NOT `npx` — it drops `DYLD_INSERT_LIBRARIES`) under `DYLD_INSERT_LIBRARIES=/usr/lib/libgmalloc.dylib` (add `MALLOC_STRICT_SIZE=1` to catch <16-byte overruns), looped inside `lldb -b -o run -k "thread backtrace all" -k quit` until it faults — Guard Malloc turns the deferred freelist trap into an immediate `EXC_BAD_ACCESS` at the actual bad access, putting the offending `index.node` finalizer frame at the top of the backtrace.

  **Running this recipe (notes from the dev2026072306 upgrade).** Two things will waste your time if you don't know them:

  - **`lldb` can't attach to the Homebrew `node`** (`attach failed … could not pause execution`) — SIP/hardened runtime. Run the suite under Guard Malloc directly and read the exit code instead: `139` = SIGSEGV. Bisect *which* suite faults with `--shard=1/4 … 4/4`, then run that shard's files one at a time (`jest --listTests --shard=4/4` gives the list).
  - **A stale sibling addon can masquerade as an `index.node` regression.** The `gpu/` subpackage used to live here and shipped a `gpu.node` built months earlier against an old nightly; it faulted under `MALLOC_STRICT_SIZE=1` and read as an addon regression that no `src/` change could possibly cause. `gpu/` has since moved out (see below), but if any sibling addon is ever vendored back in, exclude it from the root jest run before trusting this recipe.

    Baseline as of dev2026072306: **612 tests pass clean** under the full recipe:

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

`get_symbol` also *raises* on a missing symbol where `get_function` aborted the process — strictly better (e.g. `parallelize_safe` now degrades to sequential instead of killing Node). Migrating `bindings.mojo` was a net safety win beyond the mechanical fix: the old code took the address of a local holding the resolved pointer and reinterpreted that word, so a future fat function reference would have stored the wrong word *and still compiled*. `assert_fn_ptr_is_one_word()` in `bindings.mojo` now guards the remaining `_sym` reinterpret at compile time. Validated end-to-end in `spike/ffi_probe.mojo` — run it before touching FFI call sites.

**Named libraries need an explicit keep-alive** (dev2026072306): a resolved symbol pointer does *not* borrow the handle, so ASAP destruction can `dlclose` the library at the handle's last tracked use — the lookup — before you call through the pointer. `framework/runtime.mojo` (the only named-library site, `libKGENCompilerRTShared`) now ends with `_ = lib^` after `create_rt()`. The other 273 sites are immune because `OwnedDLHandle()` is `dlopen(NULL)` and the host process image is never unmapped. `runtime.mojo` used to be unreachable from `src/lib.mojo` (only `examples/vectors-addon.mojo` imported it), which is how it accumulated both this `dlclose` bug and a dead symbol lookup. `src/addon/runtime_ops.mojo` now pulls it into the addon build, and `tests/runtime.test.js` asserts the init actually succeeds — see the parallelize() note below.

**Implicit `UnsafePointer` → `Mut/ImmutAnyOrigin` conversion removed** (dev2026072306, warning since dev2026062206): C-FFI signatures fix their origin at `MutAnyOrigin`/`ImmutAnyOrigin`, so every site handing them a concrete pointer now needs an explicit **`.as_unsafe_any_origin()`**. This was 351 errors across 23 files.

- **Semantics are unchanged.** `as_unsafe_any_origin()` is the explicit spelling of the *same* widening that used to be implicit. The load-bearing lifetime extension documented in the AnyOrigin rule below is preserved — this is **not** the `MutUntrackedOrigin` substitution that caused SIGSEGVs, and that warning still stands in full.
- **`get_symbol` returns `MutUntrackedOrigin`**, and `_slot` widens it. That is sound for a reason specific to symbols — a symbol address is a static code address with no lifetime — and is **not** precedent for using `UntrackedOrigin` at transient slot-cast sites.
- **Fix from compiler diagnostics, never a global sed.** Watch for two placement mistakes the mechanical pass makes: appending to a void statement (`CbArgs.get_argv(...).as_unsafe_any_origin()` — belongs on the `argv` argument), and appending to an enclosing call's result when the un-widened pointer is an *inner* argument.

**`Span(ptr=…)` → `Span(unsafe_ptr=…)`** (dev2026072306): hard rename, 10 sites (`framework/js_string.mojo` ×6 — four of them line-wrapped so `ptr=` sits on its own line and a single-line regex misses them — `addon/class_animal.mojo` ×3, `addon/user_fns.mojo` ×1).

**`ImplicitlyDestructible` → `ImplicitlyDeletable`** (dev2026062206, migrated dev2026072306): trait renamed; old name warned. Also migrated at the same time: `init_pointee_move` → **`unsafe_write`** (25 sites) and `destroy_pointee` → **`unsafe_deinit_pointee`** (22 sites). The build is now warning-clean.

**dev2026080905 (26.6 cycle) — the great `unsafe_` rename.** The entire raw-pointer surface was renamed; all pure renames with unchanged semantics, safe to apply as word-boundary seds (unlike the origin migration above, which needs diagnostics-driven placement). Migrated ~1,500 textual sites:

- `UnsafePointer` → **`Pointer`** (608 sites). `OpaquePointer` is unchanged. No collision: the old safe `Pointer` reference type no longer exists under that name.
- `.bitcast[T]()` → **`.unsafe_bitcast[T]()`** (763 sites); `.free()` → **`.unsafe_free()`** (62 sites).
- `alloc[T](n)` → **`unsafe_alloc[T](n)`**, imported **`from std.memory.alloc import unsafe_alloc`** — the `std.memory` package `__init__` does not re-export `unsafe_alloc` on this build, so the module path is required. Long-term API is the Layout-based `alloc(layout) -> Allocation[T]` with compiler-enforced dealloc; adopting it is a real refactor, deferred.
- Pointer indexing `ptr[i]` → **`ptr[unsafe_offset=i]`**; pointer arithmetic `ptr + n` → **`ptr.unsafe_offset(n)`**. These CANNOT be sed'd — List/Array indexing is textually identical — so they were driven from compiler diagnostics by a script parsing `file:line:col` (the caret points at the `[` / the `+`). Bare deref `ptr[]` is unaffected.
- SIMD `.load[width=w](i)` → **`.unsafe_load[width=w](i)`** (vectors example).
- `InlineArray[T, N]` → **`Array[T, N]`** — the temporary alias was removed; `Array` has the identical API (incl. `fill=`) and is in the prelude.
- `__del__` → **`__deinit__`**; `ImplicitlyDeletable` → **`Deinitable`**.
- Keyword-form move ctor must name its arg `move`: `def __init__(out self, *, deinit move: Self)`. The positional `__moveinit__(out self, deinit take: Self)` form still counts as a move ctor unchanged.
- `@export("name", ABI="C")` → `@export("name")` + `abi("C")` effect on the def. Only `examples/codegen/lib.mojo` still had the old form — it sits outside the `examples/*-addon.mojo` CI glob and had rotted (it was also still missing dev2026072306's `.as_unsafe_any_origin()`); consider widening that glob if more non-addon examples appear.
- New warning: "assignment to 'X' was never used" **false-positives on vars captured by `capturing` closures** (3 sites in `examples/vectors-addon.mojo`, `chunk_size`). Do not delete the "dead" var — it is read inside the closure. Left as warnings.

**`get_symbol` now borrows the handle** (dev2026080905): it returns `Optional[Pointer[T, origin-of-handle]]` instead of a `MutUntrackedOrigin` pointer, so inside a generic `ref h` function the mutability is symbolic and `.as_unsafe_any_origin()` no longer converts to `MutAnyOrigin` (error names `SomeUnsafeAnyOrigin`; the note says `.mut … is 'h_is_mut'`). `_slot` now spells the widening explicitly: `opt.value().unsafe_mut_cast[True]().unsafe_origin_cast[MutAnyOrigin]()` in `bindings.mojo`, and `…unsafe_origin_cast[MutUntrackedOrigin]()` in `spike/ffi_probe.mojo`, whose cache struct has already been migrated off the field decorator (see `docs/plan-origin-migration.md`) — same soundness argument as before (a symbol address is a static code address; the handle is `dlopen(NULL)`, never unmapped). Related: **`AnyOrigin[mut]` and `UnsafeAnyOrigin[mut]` are now distinct spellings** (identical MLIR attr underneath); upstream documents `UnsafeAnyOrigin` as "slated for deprecation and removal". **That notice is attached to the `Unsafe*` spelling only, and this codebase is on the other one** — re-read against `mojo/stdlib/std/origin/__init__.mojo` on 2026-08-21: `AnyOrigin`/`MutAnyOrigin`/`ImmutAnyOrigin` carry a bare docstring with no deprecation language, and the 26.6 alias-removal sweep deleted `ImmutUnsafeAnyOrigin` while deliberately leaving `ImmutAnyOrigin` alone. So a forced migration of the `MutAnyOrigin` surface is *possible* (the attrs are identical, and upstream could retire the escape hatch wholesale) but is **not** currently scheduled, and nothing in the tree uses a removed spelling. See `docs/handoff-argv-origin-migration.md` for the evidence and for `scripts/derive-population-b.mjs`, which derives the at-risk set from source rather than from a number in a document.

**`parallelize` moved to `max.algorithm`** (dev2026080905): `from std.algorithm import parallelize` no longer resolves — the function now ships in the MAX package: **`from max.algorithm import parallelize`**. Probe trap that cost real time here: an *unused* `from X import name` is NOT verified (imports resolve lazily, like body elaboration) — a probe must **call** the symbol to prove anything.

**Explicit `__moveinit__` fails in a main-module file** (dev2026072306): `def __moveinit__(out self, deinit take: Self)` errors with `'None' has no attributes` on `self` when the struct is declared in a file compiled as the entry module, while the identical spelling compiles inside the `napi` package (`bindings.mojo` still declares its own). `Movable` is auto-derived, so dropping the explicit move ctor is the workaround — `spike/ffi_probe.mojo` does. Don't "fix" one context to match the other without re-checking both. **`mojo doc` compiles its target file as a main module too**, even with `-I src`, so it cannot open the three framework files that declare an explicit move ctor (`js_string.mojo`, `js_mojo_array.mojo`, `register.mojo`). They are listed in `KNOWN_UNDOCUMENTABLE` in `scripts/check-docstring-coverage.mjs`, which fails if one ever starts working — the skip cannot outlive the compiler bug.
