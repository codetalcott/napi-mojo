# Plan: typed `JsExternal` + `instance_data` helpers

**Status**: planned, not yet implemented
**Created**: 2026-04-12
**Driver**: `mojo-addon-examples` now has 4 cached GPU addons (simd-search, image, stats, matmul) that duplicate ~150 lines of N-API handle plumbing each. Extracting the common typed-wrapper pattern into napi-mojo would eliminate ~280 lines of duplication across those addons and provide a general-purpose ergonomic improvement for any napi-mojo consumer wanting to attach Mojo structs to JS handles or addon-instance state.

## Context

napi-mojo currently exposes [`JsExternal`](../src/napi/framework/js_external.mojo) with `create()` / `create_no_release()` / `get_data()` — all operating on **opaque pointers**. Consumers who want a typed Mojo struct behind the handle do the heap-alloc / `init_pointee_move` / finalizer-bitcast / `get_data`-bitcast dance themselves, per handle, per addon. Same shape for `napi_set_instance_data` / `napi_get_instance_data` (exposed only at the raw layer in [`src/napi/raw.mojo`](../src/napi/raw.mojo) lines 3894–3947).

Cross-referenced evidence from `mojo-addon-examples` Phase 3 (2026-04-11 to 2026-04-12):

- `simd-search/addon_cached.mojo` — ~150 lines of plumbing around `CachedBuffer`
- `image/addon_cached.mojo` — ~150 lines around `CachedImage`
- `stats/addon_cached.mojo` — ~200 lines around `CachedStats`
- `matmul/addon_cached.mojo` — ~250 lines around `CachedMatrix`

~40 lines per addon are **byte-for-byte identical** (`GpuState` + finalize + `_get_gpu_state` + register_module GPU init). ~30 lines per addon are **structurally identical, only the type parameter differs** (`_cached_*_finalize` callbacks, External handle creation, handle retrieval + tombstone check). The other lines are kernel-specific and wouldn't be extracted.

## Goal

Add **GPU-agnostic typed wrappers** to napi-mojo. Two concrete additions:

### 1. `JsExternal.create_typed[T]` / `get_typed[T]`

```mojo
# Extend src/napi/framework/js_external.mojo
struct JsExternal:
    # ... existing methods ...

    @staticmethod
    def create_typed[T: Movable, //](
        b: Bindings, env: NapiEnv, var value: T
    ) raises -> JsExternal:
        """Heap-allocate `value`, wrap in an External handle with a finalizer
        that runs `destroy_pointee` + `free` on GC. Caller doesn't need to
        write the `alloc[T](1)` / `init_pointee_move` / `fin_ptr` bitcast
        dance."""

    @staticmethod
    def get_typed[T: AnyType, //](
        b: Bindings, env: NapiEnv, val: NapiValue
    ) raises -> UnsafePointer[T, MutAnyOrigin]:
        """js_typeof → NAPI_TYPE_EXTERNAL check + get_data + bitcast[T]() in
        one call. Raises if `val` is not an External."""
```

Consumer code becomes:

```mojo
# Before (current):
var cb_ptr = alloc[CachedBuffer](1)
cb_ptr.init_pointee_move(cb_val^)
var fin_ref = _cached_buffer_finalize
var fin_ptr = UnsafePointer(to=fin_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
return JsExternal.create(b, env, cb_ptr.bitcast[NoneType](), fin_ptr).value
# + define _cached_buffer_finalize separately (8 lines)

# After:
return JsExternal.create_typed(b, env, cb_val^).value

# Before (retrieve):
var t = js_typeof(b, env, r.arg0)
if t != NAPI_TYPE_EXTERNAL:
    raise Error("expected External handle")
var data = JsExternal.get_data(b, env, r.arg0)
var cb = data.bitcast[CachedBuffer]()

# After:
var cb = JsExternal.get_typed[CachedBuffer](b, env, r.arg0)
```

### 2. `napi.framework.instance_data` module (new)

```mojo
# New file: src/napi/framework/instance_data.mojo
def set_instance_data[T: Movable, //](
    bindings_ptr: UnsafePointer[NapiBindings, ...],
    env: NapiEnv,
    var value: T,
) raises:
    """Heap-allocate `value`, register as the env's instance data with an
    auto-finalizer that runs `destroy_pointee` + `free` on env teardown."""

def get_instance_data[T: AnyType, //](
    b: Bindings, env: NapiEnv
) raises -> UnsafePointer[T, MutAnyOrigin]:
    """Retrieve the typed instance data pointer. Raises if unset."""
```

Consumer code replaces the GpuState register_module try/except (currently ~18 lines per addon) with a single call:

```mojo
# Before:
try:
    var ctx = DeviceContext()
    var state_ptr = alloc[GpuState](1)
    state_ptr.init_pointee_move(GpuState(ctx^))
    var fin_ref = _gpu_state_finalize
    var fin_ptr = UnsafePointer(to=fin_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
    _ = raw_set_instance_data(bindings_ptr, env, state_ptr.bitcast[NoneType](), fin_ptr, OpaquePointer[MutAnyOrigin]())
except:
    pass
# + _gpu_state_finalize callback (8 lines)

# After:
try:
    set_instance_data(bindings_ptr, env, GpuState(DeviceContext()^))
except:
    pass  # no GPU, statsGpu etc. will throw on call
```

## Non-goals

These are explicitly **deferred** to avoid scope creep:

1. **`napi.framework.cached_gpu` module** — would wrap the `GpuState(DeviceContext)` pattern specifically. Crosses an architectural boundary (napi-mojo would depend on `std.gpu.host`). Revisit if we accumulate 6+ cached GPU addons; currently 4.
2. **Full `CachedHandle[T]` trait** — would try to abstract the released-tombstone + validation + multi-buffer handle patterns. Likely under-parameterized for real use. Skip.
3. **Migrating existing untyped `JsExternal.create` / `get_data` callers** — the new typed variants are additive. Old APIs stay. No churn forced on non-cached addons.
4. **FP16 or explicit-precision variants of anything** — out of scope for typed helpers; belongs in per-addon code if needed.

## Design notes / open questions

### Finalizer bitcast and Mojo generics

The tricky part is writing a **generic** finalizer that works for any `T: Movable`. In current cached-addon code, each addon has its own `_cached_<T>_finalize` function that bitcasts to the specific type. For `create_typed[T]` we need a single generic finalizer:

```mojo
fn _typed_external_finalize[T: Movable](
    env: NapiEnv,
    data: OpaquePointer[MutAnyOrigin],
    hint: OpaquePointer[MutAnyOrigin],
):
    var ptr = data.bitcast[T]()
    ptr.destroy_pointee()
    ptr.free()
```

**Open question**: can Mojo monomorphize this finalizer per T and pass its address through the N-API C ABI cleanly? The `fn_ptr` bitcast dance relies on the exact function signature matching what N-API expects. Parametric `fn` types and the `UnsafePointer(to=fn_ref).bitcast[OpaquePointer]()[]` pattern need spike validation first.

**Spike prompt**: write `spike/typed_helpers_probe.mojo` that constructs a `create_typed[SomeMovableStruct]` call and verifies (a) it compiles, (b) the finalizer runs when the JS External is GC'd, (c) the struct's destructor runs during finalization. If this works, the rest of the plan is mechanical.

### Ownership and move semantics

`create_typed` takes `var value: T` and moves it into heap-allocated memory via `init_pointee_move(value^)`. The caller must transfer ownership with `^`. This matches current per-addon patterns.

`get_typed` returns `UnsafePointer[T, MutAnyOrigin]` — a non-owning pointer into the heap-allocated struct. Caller dereferences with `ptr[].field` to read, `ptr[].field = x` to write. Same semantics as current `data.bitcast[T]()` usage.

### Error message ergonomics

Current per-addon code has specific error messages like `"countByteHandle: expected External handle"`. Generic `get_typed[T]` can't know the caller's function name. Options:
- (a) Accept a `context: StringSlice` parameter: `get_typed[T](b, env, val, "countByteHandle")`. Explicit but verbose.
- (b) Always raise with generic message `"expected External handle"`; caller catches and re-raises with specific context. Slightly more code but cleaner API.
- (c) Accept an `Optional[StringSlice]` context; default generic message.

**Lean toward (a)** — makes error messages exactly as informative as today with one extra string argument. Easy to pass a `__function__` equivalent if Mojo adds one later.

### Instance data — single or multi-slot?

N-API's `napi_set_instance_data` supports exactly one slot per env. That's fine for cached GPU addons (one `DeviceContext`) but could conflict if two unrelated consumers both want to stash instance data. **Not solving this now** — if conflict arises later, design a registry on top of the single slot. Document the single-slot limitation in the module docstring.

## Implementation plan

Follow the project's strict TDD workflow ([docs/METHODOLOGY.md](METHODOLOGY.md)):

### Phase 0 — Spike (~2 hours)

New file: `spike/typed_helpers_probe.mojo`

Minimum viable proof:
- Define a trivial `Movable` struct `TestPayload { var value: Int }`
- Write `create_typed[T: Movable]` that heap-allocates + creates External with a generic finalizer
- Write `get_typed[T]` that retrieves and bitcasts
- A tiny Jest test: create handle, call a second fn that reads via `get_typed`, verify value roundtrips. Release handle, verify finalizer ran (visible via a global counter).

**Decision gate**: does the generic finalizer ABI work cleanly? If yes → proceed. If no → narrow scope (e.g. typed `get_data` only, caller keeps writing their own finalizer), or abandon this plan and revisit after Mojo generics for function pointers stabilize.

### Phase 1 — RED (write failing tests)

New test file: `tests/typed-external.test.js`

Tests cover:
1. `create_typed` + `get_typed` roundtrip: create External with payload `{value: 42}`, retrieve, assert value === 42.
2. Finalizer runs on GC: create, release all references, force GC via `--expose-gc`, verify a native-side counter shows the finalizer fired.
3. `get_typed` on a non-External value throws a TypeError with the supplied context string.
4. Typed instance data roundtrip: two separate callbacks, one sets instance data via `set_instance_data`, the other reads via `get_instance_data`, values match.
5. Instance data finalizer runs on env cleanup (requires env teardown hook test pattern that already exists in `tests/`).

Expected state after Phase 1: all 5 new tests fail. Existing 605 tests still pass.

### Phase 2 — GREEN (minimum implementation)

Edit `src/napi/framework/js_external.mojo`:
- Add `create_typed[T: Movable, //]` static method
- Add `get_typed[T: AnyType, //]` static method
- Both have overloads for the `(b, env, ...)` cached-bindings path; skip the legacy non-bindings path since typed helpers are a new API

New file: `src/napi/framework/instance_data.mojo`:
- `set_instance_data[T: Movable, //]`
- `get_instance_data[T: AnyType, //]`
- Generic `_typed_instance_data_finalize[T]` callback

Both files follow the project's existing N-API wrapper style (`raw_*` call + `check_status` + result wrapping).

Add test addon exports for the 5 new tests in `src/exports.toml` + regen via `npm run generate:addon`.

Expected state after Phase 2: all 610 tests pass.

### Phase 3 — REFACTOR

- Run `npm run test:gc` to verify finalizer tests pass with `--expose-gc`
- Run `node scripts/benchmark.mjs` to verify no per-call overhead regression on existing functions
- Add Writable docstrings to both new methods (single-line each — see existing style)
- Update `docs/EXPORTS.md` if any new addon test functions are visible to JS tests (probably not, they're internal-only)
- Update `CLAUDE.md` architecture section to describe the typed helpers

### Phase 4 — Integration test via `npm link`

In `projects/mojo-node-api`:

```bash
npm link
```

In `projects/mojo-addon-examples`:

```bash
npm link napi-mojo
```

Rewrite one addon (simd-search/addon_cached.mojo — smallest cached addon) using the new typed helpers. Build + run the existing regression test (`node simd-search/test_cached.js`). Verify:
- 220 correctness cases still pass
- Leak-smoke delta unchanged (or improved)
- Per-call benchmark not regressed (run `node simd-search/search_cached.js`, compare to pre-extraction baseline)

This is the "does the abstraction actually work in a real consumer" gate. If it does, proceed. If it feels awkward to use, iterate on the API.

### Phase 5 — Release napi-mojo

Minor version bump (likely `0.2.12` → `0.3.0` since this is meaningful API expansion). Update `package.json`. Tag + publish. Note in CHANGELOG (if one exists — add it if not).

### Phase 6 — Separate mojo-addon-examples PR

In a new session targeting `mojo-addon-examples`:
- Bump napi-mojo dep to `^0.3.0`
- Rewrite all 4 cached addons (simd-search, image, stats, matmul) to use typed helpers
- Run M4 regression tests + benchmarks, verify:
  - Zero correctness regressions (byte-exact output)
  - No measurable perf regression (±5% per-call)
  - Line count reduction: expect each cached addon to shrink by ~70 lines
- Commit as one PR with commit message summarizing "refactor cached addons to use napi-mojo 0.3.0 typed helpers"

Nice-to-have: run the H100 bench script once more to re-validate the Phase 3a/3b/3c numbers didn't drift. Same pod configuration; the bench runbook already exists.

## File list

**New files (napi-mojo)**:
- `spike/typed_helpers_probe.mojo`
- `src/napi/framework/instance_data.mojo`
- `tests/typed-external.test.js`

**Modified files (napi-mojo)**:
- `src/napi/framework/js_external.mojo` — add `create_typed` + `get_typed` overloads
- `src/napi/framework/__init__.mojo` — export the new module if needed
- `src/exports.toml` — add test addon entries for the 5 new tests
- `src/generated/*.mojo` — auto-regenerated from `exports.toml`
- `CLAUDE.md` — architecture section update
- `package.json` — version bump, final step
- `README.md` — mention typed helpers in the feature list, if that list exists

**No changes** to `docs/METHODOLOGY.md` or `docs/EXPORTS.md` expected.

**Modified files (mojo-addon-examples, separate session)**:
- `package.json` — bump napi-mojo dep
- `simd-search/addon_cached.mojo`
- `image/addon_cached.mojo`
- `stats/addon_cached.mojo`
- `matmul/addon_cached.mojo`

## Risks

| Risk | Probability | Mitigation |
|---|---|---|
| Mojo generics on function pointers hit an ABI issue | Medium | Phase 0 spike catches this in ~2 hrs; narrow scope or abandon if so |
| Parametric finalizer can't be monomorphized across multiple T in one addon | Low | Each addon uses a handful of Ts; even if monomorphization is per-callsite, the compiler handles it. Verify in spike. |
| Per-call overhead regression (extra function call + generic dispatch) | Low | benchmark.mjs catches it. Generic dispatch should inline; if not, add `@always_inline`. |
| Coordination friction: napi-mojo release must land before mojo-addon-examples update | Low | `npm link` workflow eliminates this during development. Only matters for published release. |
| Two Levels-1-through-3 end up being a slippery slope — after Level 1 ships, pressure to also add Level 2 | Low | This plan explicitly lists Level 2/3 as non-goals. Add a GitHub issue for "Level 2 revisit" that future work can reference without re-opening this plan. |

## Success criteria

- [ ] Phase 0 spike proves generic finalizer works
- [ ] 5 new Jest tests pass; existing 605 still pass
- [ ] `npm run test:gc` clean
- [ ] Benchmark shows no regression >5% per call
- [ ] Phase 4 integration test: simd-search/addon_cached.mojo migrated, all 220 correctness cases pass, leak smoke unchanged
- [ ] napi-mojo released as `0.3.0`
- [ ] mojo-addon-examples PR merged with 4 addons rewritten, ~280 lines net removed, all M4 regression tests pass, no benchmark regression >5%

## Deferred / follow-up work (create as issues, not in scope here)

- Level 2: `napi.framework.cached_gpu` with `GpuState` wrapper. Revisit at 6+ cached GPU addons.
- Level 3: `CachedHandle[T]` abstraction. Probably skip permanently.
- Multi-slot instance data registry.
- Typed variants of `create_no_release` (External without finalizer). Low priority — current consumers all want finalizers.
- Documentation: a new `docs/typed-helpers.md` tutorial showing how to build a cached addon from scratch using the new API. Good onboarding material once the API is stable.

## Reference

- 4-addon evidence: `projects/mojo-addon-examples/` commits `16144cc` (3b.1 grayscale), `24af52e` (3b.2 stats), `577dbe0` (3c.3 matmul). The duplicated boilerplate is visible across all four `addon_cached.mojo` files.
- Earlier analysis discussion: see `projects/mojo-addon-examples` Phase 3c session notes — the conversation that preceded this plan evaluated three extraction levels and landed on Level 1.
- Existing napi-mojo patterns: `JsExternal` in `src/napi/framework/js_external.mojo`, raw instance_data in `src/napi/raw.mojo:3894–3947`.
