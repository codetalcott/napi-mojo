# Plan: removing `@__allow_legacy_any_origin_fields`

**Status:** recipe **proven in CI** (2026-08-20), migration **not started.**

`@__allow_legacy_any_origin_fields` is the changelog-sanctioned escape hatch for
the dev2026062206 rule "struct fields cannot expose AnyOrigin in their type".
Upstream documents it as unstable and slated for removal, and separately
documents `UnsafeAnyOrigin` itself as slated for deprecation. **This migration
is not optional — only unscheduled.** The point of doing the work now is that
the alternative is doing it against a broken build on a deadline, in the one
area of this codebase that has already produced SIGSEGVs.

## The finding: two populations, not one

CLAUDE.md warns that a naive global `MutAnyOrigin` → `MutUntrackedOrigin`
rename caused confirmed crashes. That warning is correct **and it is about a
different population than the decorator's.** Keeping them apart is the whole
recipe.

| | what it is | count | risk |
|---|---|---|---|
| **A** | struct fields carrying the decorator | **243** across 40 files | none |
| **B** | inline `Pointer(to=<local>)…as_unsafe_any_origin()` arguments | **159** | this is the one that crashed |

**Population A is safe**, and the reason is checkable rather than a judgement
call: every decorated field points at a V8-owned opaque handle, a static code
address, or an `unsafe_alloc` heap block. Not one is ever assigned from
`Pointer(to=<local>)`:

```bash
# empty output — no struct field anywhere holds a pointer to a Mojo local
grep -rn "self\.[a-z_]* = Pointer(to=" src/ examples/
```

So there is no Mojo stack slot whose lifetime `AnyOrigin` is silently
extending, and `MutUntrackedOrigin` is not merely tolerable there — it is the
more honest type, because the lifetime really is managed explicitly, by V8 or
by `unsafe_alloc`.

**Population B is where the widening is load-bearing.** It keeps a
register-passable local's spill slot alive while N-API reads or writes through
it. Severing it is what produced garbage `napi_value`s in `JsFunction.call1/2`
argv, buffer overflow in `CbArgs.get_argv`'s in/out `argc`, and silent writes
into reused ignored-output slots.

Because the two are independent, **the decorator can be removed without
touching population B** — provided the FFI function-pointer types keep
`MutAnyOrigin`.

## The recipe

1. **Struct fields** move to `MutUntrackedOrigin` / `ImmutUntrackedOrigin` and
   drop the decorator.
2. **`comptime *Fn = def(...) thin abi("C")` types keep `MutAnyOrigin`.**
3. **A field handed to such a signature gains `.as_unsafe_any_origin()`** — the
   same concrete→Any widening already spelled at 159 sites today.
4. **Population B is not touched at all.**

> **The rule that must not be broken.** Do not "simplify" step 2 by also moving
> the FFI parameter origins to Untracked. That *is* the global rename that
> severs population B, it looks tidier, and nothing in the type system will
> stop you.

### It is proven, not asserted

`spike/ffi_probe.mojo` carries the recipe rather than describing it, and CI
builds and runs it on both platforms every PR:

- `ProbeBindings` (the 143-slot cache in miniature) and
  `NapiPropertyDescriptor` have **no decorator** and use `MutUntrackedOrigin`
  storage, while the FFI types still say `MutAnyOrigin`.
- `assert_layout_is_c_compatible()` asserts at compile time that
  `OpaquePointer[MutUntrackedOrigin]` is the same size as the `AnyOrigin`
  spelling **and** that `NapiPropertyDescriptor` is still 64 bytes. If the
  origin parameter ever changed the machine representation, every
  `napi_define_properties` call would corrupt silently.
- `originProbe()` creates a JS string through a local output slot, reads it
  back through a second, and **compares the bytes** — four payloads of
  different lengths, so a slot clobbered by its neighbour fails on content. A
  null check would pass on garbage.

First CI run, both platforms:

```
ffi probe: FFI probe OK: get_symbol + thin abi(C) + cache
ffi probe: originProbe PASS 4/4
```

## Costed inventory

The 243 sites are not 243 edits. 20 are generated, and 143 are one struct.

| where | sites | how |
|---|---:|---|
| `src/napi/bindings.mojo` | 143 | one struct, one repeated field type — mechanical |
| `src/napi/framework/args.mojo` | 14 | the `BindingsAnd*` payload structs |
| `tests/codegen/generated/callbacks.mojo` | 12 | **template**, not by hand |
| `src/napi/framework/register.mojo` | 10 | `ClassRegistry`, `ModuleBuilder` |
| `src/addon/async_ops.mojo` | 9 | async data structs |
| `spike/ffi_probe.mojo` | 9 | **done** — this is the proof |
| `src/napi/types.mojo` | 8 | `NapiPropertyDescriptor` + `NapiNodeVersion` |
| `src/generated/callbacks.mojo` | 4 | **template** |
| `examples/tutorial/generated/callbacks.mojo` | 4 | **template** |
| 31 further files | 1–3 each | the `Js*` wrappers, mostly a single `value` field |

**`scripts/generate-addon.mjs` emits the decorator in 2 places.** Per the
codegen-drift rule, the templates get patched in the same commit and
`npm run generate:addon && git diff --exit-code src/generated/` is the gate.

### Suggested order

Each step is independently compilable, which matters — this is a
diagnostics-driven migration, not a sed.

1. `types.mojo`: add the storage spellings (`NapiValueStore`,
   `NapiConstStore`), keeping `NapiEnv`/`NapiValue` at `MutAnyOrigin` for
   signatures.
2. `bindings.mojo` — 143 sites, one shape, biggest single win.
3. The `Js*` wrappers — one field each, ~31 files.
4. `args.mojo`, `register.mojo`, `async_work.mojo`.
5. `src/addon/*`.
6. Generator templates, then regenerate.
7. Fix the resulting field→FFI diagnostics with `.as_unsafe_any_origin()`.
   **Drive this from compiler output, never a global sed** — the same rule the
   dev2026072306 origin migration converged under (351 → 187 → 65 → 35 → 30).

### What is not yet costed

Step 7's site count. The spike needed 2 widenings in ~50 lines of call sites,
but that is too small a sample to extrapolate from honestly; the real number
falls out of the first `bindings.mojo` build. Budget it as the unknown.

## Revisit when

A nightly changelog mentions removing `@__allow_legacy_any_origin_fields` or
`UnsafeAnyOrigin`, or the Nightly Canary goes red with the AnyOrigin field
error. Both are now recipes to execute rather than problems to solve.
