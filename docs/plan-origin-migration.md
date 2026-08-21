# Plan: removing `@__allow_legacy_any_origin_fields`

**Status: DONE.** Recipe proven in CI 2026-08-20, migration completed the same
day and shipped in 0.10.0 — **243 decorated fields to zero.** The document
stays as the record of *why* it was safe and of the rule that must not be
broken; the "costed inventory" and "suggested order" below are now a history of
how it was executed, not a plan.

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

## How it actually went

Five steps, each independently green, in the order suggested below — with one
addition discovered on contact: **`raw.mojo`'s 143 FFI type expressions were
spelled with the handle aliases**, so flipping the aliases would have moved the
FFI signatures underneath them, which is precisely the rule that must not be
broken. A verified no-op commit pinning those 143 expressions to a literal
`MutAnyOrigin` went first; only then was the flip safe.

Step 7's unknown resolved at **265 widenings** across the whole migration, all
placed from compiler diagnostics. The flip converged over seven build rounds
(3 → 1 → 41 → 19 → 1 → 1 → 0 errors). Two of those rounds found real latent
defects rather than spelling gaps:

- `NapiNodeVersion`'s explicit constructor, which had never been elaborated.
- **`raw_create_promise`'s `deferred` parameter**, which the migration exposed
  as an *output slot* being handled as if it were a handle. Its caller passes
  `Pointer(to=<local>)…as_unsafe_any_origin()` — population B. Under the old
  aliases that confusion compiled silently; making the handle aliases a
  distinct type is what turned it into a diagnostic. That is the clearest
  single argument for having done the flip rather than only the fields.

## Population B, step 1 — landed, and the recipe it corrected

The keep-alive half of population B is **done**; only the FFI signature flip
remains. Derived fresh rather than quoted: 247 population-B sites exist today,
of which **19 had no tracked use after the FFI call** and therefore nothing
keeping their slot alive but `AnyOrigin`'s implicit extension. Those 19 — the
`argc` in/out slots in `CbArgs.get_this`/`get_data`/`get_bindings_and_this`,
the ignored output slots (`data` in `JsArrayBuffer.create` and
`JsBuffer.create`, `copy_data`, `sign`, `copied`, `removed`), the argv slots in
`call1`/`call2`/`make_callback1`/`make_callback2`/`Counter.fromValue`/
`newCounterFromRegistry`, and the tag inputs — now carry an explicit barrier.
The other 228 are pinned by a real use after the call (usually `return`), which
is a keep-alive already and needs nothing.

**The recipe above was wrong about the mechanism, and the compiler says so.**
`_ = x^` is a genuine use only for a type with something to move. For a
trivially register-passable one it is rejected outright:

```
warning: transfer from a value of trivial register type 'UInt' has no effect
and can be removed
```

That covers `UInt`, `Bool`, `Int32` and every `OpaquePointer` alias including
`NapiValue` — i.e. **12 of the 19**, and the entire argv/argc/ignored-output
population this document warns about. Emitted IR for the two forms, from
`spike/keepalive_probe.mojo`:

```llvm
define i64 @without_pin(i64 %0) {          ; _ = slot^
  ret i64 %0                               ; the alloca is GONE
}
define i64 @with_pin(i64 %0) {             ; pin_across_ffi(slot)
  %2 = alloca i64, i64 1, align 8
  call void @llvm.lifetime.start.p0(ptr %2)
  store i64 0, ptr %2, align 8
  call void asm sideeffect "", "r,~{memory}"(ptr %2)
  call void @llvm.lifetime.end.p0(ptr %2)
  ret i64 %0
}
```

Had the flip landed with `_ = x^` in place, every one of those sites would have
looked migrated while N-API wrote into a slot the compiler had already
reclaimed — the silent class, at scale.

`src/napi/keepalive.mojo`'s **`pin_across_ffi`** is the replacement: it wraps
`std.benchmark.keep`, which takes `ref [origin]` (a tracked use, so the
lifetime cannot end before it) and passes the address into empty inline
assembly with `~{memory}` and `has_side_effect=True`. It emits no instructions,
and measured cost is zero — it sits immediately after an opaque external call
that already clobbers memory. All 18 benchmarks stayed in the same 23–26%-of-
ceiling band.

Taking `ref [origin]` also **retires recipe point 2**: pinning works on a
borrowed register-passable parameter directly, and the IR confirms it is the
same `alloca` that `Pointer(to=param)` materialised. No copy-into-an-owned-
local step is needed. Two pre-existing borrow-form discards meant as
keep-alives — `JsFunction.call_with`'s `_ = args` and `create_named`'s
`_ = name` — were upgraded for the same reason.

`scripts/check-keepalive-barrier.mjs` asserts both halves of the IR
counterfactual in CI, including that `without_pin` still loses its alloca —
without that half the gate would pass on a compiler where both forms work and
would stop being evidence of anything.

## Revisit when

**Step 3, the FFI signature flip, is the only part left** — moving `raw.mojo`'s
143 literal `OpaquePointer[MutAnyOrigin]` FFI type expressions off `AnyOrigin`.
That is still elective: as of 2026-08-20 the upstream 26.6 changelog lists
origin *renames*, not removals, and this codebase uses zero of the renamed
spellings. Re-run those counts before starting; if removal has landed, the
schedule is no longer yours to choose.

The SIGSEGV warning above applies to that flip in full, with one thing now
different: the keep-alives it depends on are in place and are real, and
`spike/keepalive_probe.mojo` proves the mechanism rather than assuming it. Do
it in small batches driven by compiler diagnostics, never a global sed, and
re-run the whole verification stack (including the Guard Malloc run, with the
banner confirmed) after each batch.
