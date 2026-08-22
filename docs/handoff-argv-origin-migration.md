# Handoff: the population-B FFI signature flip

> **Read `docs/plan-origin-migration.md` first.** It is the record of the field
> migration (population A, 0.10.0) and of the keep-alive work (population B
> step 1), and it defines the two populations this document depends on. Do not
> start here.

## State: step 1 done, step 3 PART done — 19 of 147 wrappers

> **Update 2026-08-21.** Phase 1 of step 3 has landed: the **19 handle-only
> wrappers** are flipped off `AnyOrigin`. They were chosen precisely because
> they carry zero population-B exposure — every argument is a V8 handle already
> aliased `MutUntrackedOrigin`, and nothing forms a pointer to a Mojo local, so
> the widening calls were ceremony rather than load-bearing. Verified with the
> whole stack below, Guard Malloc banner confirmed.
>
> **The 128 pointer-taking wrappers remain deferred**, and they are the real
> work: they are the argv / in-out `argc` / output-slot path. Sizing note that
> cost time to establish — the remainder is **~775 `MutAnyOrigin` occurrences
> and ~493 `as_unsafe_any_origin()` sites across 40+ files**, not "143 type
> expressions". The FFI type, the wrapper parameter and the caller's widening
> are one chain; flipping the type alone relocates the cast and removes no
> dependency on the implicit extension. Budget for batches of ~10 wrappers with
> the full stack between each.

## Step 1 is done, and step 3 is what remains

The staged plan was: (1) add keep-alives with the FFI signatures unchanged,
(2) prove the recipe in a spike, (3) flip the signatures off `AnyOrigin`.

**Steps 1 and 2 have landed.** Every population-B site that needed an explicit
keep-alive has one, the mechanism is proved at the IR level, and
`scripts/check-keepalive-barrier.mjs` guards it in CI. See the plan doc's
"Population B, step 1" section for the full record — including the correction
that matters most to whoever does step 3:

> **`_ = x^` does not work.** It is a no-op for trivially register-passable
> types — `UInt`, `Bool`, `Int32`, and every `OpaquePointer` alias including
> `NapiValue` — which is nearly this entire population. Use
> `pin_across_ffi` from `src/napi/keepalive.mojo`.

**Nothing is broken today**, and step 3 remains elective. Population B is
correct because `AnyOrigin` in the FFI signatures silently extends each local's
lifetime. The work is to remove the dependency on that implicit guarantee now
that an explicit one is in place.

## Is it still elective?

**Yes — and the evidence has moved AWAY from the forcing function, not toward
it.** Re-checked 2026-08-21 against `modular/modular@main`.

An origin **removal** did land in the 26.6 nightly since our 1.0.0 pin. It is
not ours:

> Removed the origin aliases left over from the `Immut` to `Imm` and `External`
> to `Untracked` renames. Use the surviving spelling in each case: `ImmOrigin`
> for `ImmutOrigin`, `ImmUnsafeAnyOrigin` for `ImmutUnsafeAnyOrigin`,
> `ImmStaticOrigin` for `StaticConstantOrigin`, `UntrackedOrigin` for
> `ExternalOrigin`, `MutUntrackedOrigin` for `MutExternalOrigin`, and
> `ImmUntrackedOrigin` for both `ImmutUntrackedOrigin` and `ImmutExternalOrigin`.

This codebase uses **zero** of the removed spellings (verified: each count is
0). It uses `MutAnyOrigin` (~990), `ImmutAnyOrigin` (~142), and the already-
modern `MutUntrackedOrigin` (~63) / `ImmUntrackedOrigin` (~21).

**The premise worth correcting.** CLAUDE.md reasons that upstream documents
`UnsafeAnyOrigin` as slated for deprecation and removal, "so expect a future
forced migration of the whole `MutAnyOrigin` surface". Reading the authoritative
module — `mojo/stdlib/std/origin/__init__.mojo` — that inference is weaker than
it looks, in two specific ways:

- **`AnyOrigin` and `UnsafeAnyOrigin` are two separate aliases** that expand to
  the byte-identical MLIR attribute (`#lit.any.origin : !lit.origin<mut>`).
  Only `UnsafeAnyOrigin` carries the removal notice and the safety essay;
  `AnyOrigin` has a bare two-line docstring with no deprecation language at
  all. We are on the `AnyOrigin` family.
- **The rename sweep treated the two families differently on purpose.**
  `ImmUnsafeAnyOrigin` was renamed and its `Immut` spelling deleted, while
  `ImmutAnyOrigin` was left untouched under its `Immut` spelling. If both
  families were headed for the same removal, that asymmetry would be pointless.

The honest read is that `AnyOrigin` is presently the sanctioned spelling and
`UnsafeAnyOrigin` is the legacy one being retired. That is not a guarantee —
the attributes are identical, so upstream could still retire the escape hatch
wholesale — but there is no deadline visible today, and the schedule is still
ours.

What has NOT changed: the *behaviour* population B depends on is documented
upstream, under `UnsafeAnyOrigin`, as a defect to migrate away from —

> It extends unrelated lifetimes. Every other value in scope is kept alive for
> as long as the reference is live, even values it never points to, effectively
> halting ASAP destruction.

That is precisely the implicit guarantee this migration exists to stop relying
on. Elective, not pointless.

**Re-check before starting** — the two commands are in CLAUDE.md's changelog
section; diff BOTH `nightly-changelog.md` and `docs/releases/`, since content
rotates out of the former at release close. As of 2026-08-21 the newest release
file is `v1.0.0.md`, i.e. nothing has rotated since our pin.

## Deriving the population fresh

Do not trust a number in a document, including this one. **`node
scripts/derive-population-b.mjs` derives it from source** — that is what makes
the answer re-runnable instead of transcribed. `--all` lists every site,
`--json` is machine-readable, `--check` exits non-zero if anything is at risk.

Current output (2026-08-21, tree green at 753 tests):

```
population B sites      223
  pinned                 24   (explicit pin_across_ffi)
  post-use              199   (tracked use after the call)
  AT-RISK                 0
```

All 23 `pin_across_ffi` call sites in the tree reconcile against detected
sites, which is the check that the matcher is not simply missing the
population.

**The unit is one FORMATION of a pointer-to-a-local**, not one
`.as_unsafe_any_origin()` occurrence — a `var argv_ptr = Pointer(to=arg0)...`
later passed to a call counts once, at the formation. An earlier hand-count
using a different unit reported ~247; the numbers are not comparable, which is
the whole reason the definition now lives in code.

Two formation shapes reach an `AnyOrigin` parameter:

- **address-of** — `Pointer(to=local)...`: output slots, argv, in/out `argc`.
- **buffer-pointer** — `local.unsafe_ptr()...`: a `String`'s or `List`'s heap
  buffer, whose *owner* is the local being tracked. `JsFunction.create_named`
  pins its `name: String` for exactly this reason.

**False-positive classes the script filters** (counts as of the same run):

| class | n | why it is not population B |
|---|---|---|
| fn-ptr reinterpret | 175 | `Pointer(to=x).unsafe_bitcast[F]()[]` derefs inside the statement — `raw.mojo`'s slot casts |
| static string | 33 | `StringLiteral` / `StaticString` / a bare `"literal".unsafe_ptr()` — `.rodata` |
| no FFI in scope | 3 | the file crosses no boundary (`src/addon/user_fns.mojo` is pure Mojo by construction) |
| borrowed struct param | 1 | memory-passed, so the pointer is to the *caller's* storage — `define_property`'s `desc` |
| struct field | 1 | `b[].slot` is the cached `NapiBindings` allocation, never freed |

**Four bugs this script had before it was believable**, all of which made it
*under*-report and any of which would have made "0 at-risk" a lie:

1. `includes('Pointer(to=')` on a joined statement. Joining inserts a space, so
   the wrapped form becomes `Pointer( to=recv )` and never matched —
   `JsFunction.call1`/`call2`, the top two rows of the regression table below,
   were invisible. That is the same-line-grep failure in a new costume.
2. A body scan that stopped at the first line whose indent was `<=` the def's.
   A wrapped signature puts `) raises -> X:` back at the def's own indent, so
   every such def reported an empty body and its sites fell through to at-risk.
3. A `[^\]]+` class in the fn-ptr filter, which cannot span a bitcast type
   parameter containing nested brackets — so all 142 of `raw.mojo`'s slot casts
   failed the filter open and were admitted as population B.
4. A +/-60-line window for the static-string test, which let a neighbouring
   def's `name: StringLiteral` mask `create_named`'s real `name: String`.

**`post-use` is a heuristic** — it asks whether the identifier appears again
inside the enclosing def. It cannot prove the use is a *tracked* one. Treat a
`post-use` classification as "not obviously at risk", never as a clearance;
`--emit llvm` and Guard Malloc remain the authorities, as below.

## What broke last time

CLAUDE.md records these as confirmed, deterministic failures from a naive
`MutAnyOrigin`→`MutUntrackedOrigin` rename. Treat them as the regression suite:

| site | failure |
|---|---|
| `JsFunction.call1` / `call2` argv | SIGSEGV reading garbage `napi_value` |
| `CbArgs.get_argv`'s in/out `argc` | buffer overflow → heap corruption |
| `Counter.fromValue` argv | constructs the wrong value |
| `create_buffer`'s `data`, `create_buffer_copy`'s `copy_data` | napi writes into a reused slot — **ignored** output slots, so silent |

That last row is the dangerous class: an ignored output slot produces no
symptom at the call site. Do not assume "tests pass" means a site is fine. All
four now carry a `pin_across_ffi`.

## Doing step 3

`raw.mojo`'s 143 FFI type expressions are spelled with a **literal**
`OpaquePointer[MutAnyOrigin]`, never the aliases, precisely so a future alias
change cannot move them silently — a no-op commit pinned them that way.
Respect that: change them deliberately, in small batches, driven by compiler
diagnostics.

Do **not** do a global sed. The field migration converged 351 → 187 → 65 → 35
→ 30 from diagnostics, with ~19 needing hand placement. A blind rewrite in this
area is how the SIGSEGVs happened.

After each batch, re-derive the at-risk set (a site that gains a new local, or
loses its post-call use, becomes at-risk) and re-run the whole stack below.

## Verification stack

Everything here already exists; use all of it, not just `npm test`.

```bash
pixi run bash build.sh && npm test                       # 753 tests
npm run test:gc                                          # 7 finalizer tests
node -e "require('./build/index.node').hello()"           # smoke: module load
                                                          # uses only the env-only
                                                          # path, so require()
                                                          # alone proves nothing —
                                                          # the first CALL is the
                                                          # first deref
node scripts/check-keepalive-barrier.mjs                  # the barrier still binds
node scripts/derive-population-b.mjs --check              # zero at-risk sites
pixi run mojo build --emit shared-lib -I src \
  tests/compile/framework_coverage.mojo -o /tmp/gate.so   # per-method elaboration
node scripts/check-compile-coverage.mjs
node scripts/check-benchmark.mjs                          # ceilings, both platforms
node bin/napi-mojo.mjs run examples/host/main.mojo        # host mode shares the
node bin/napi-mojo.mjs run examples/host/pipeline.mojo    # bootstrap + argv paths

# The one that finds ignored-output-slot corruption. NOT npx — it drops
# DYLD_INSERT_LIBRARIES.
DYLD_INSERT_LIBRARIES=/usr/lib/libgmalloc.dylib MALLOC_STRICT_SIZE=1 \
  node ./node_modules/jest/bin/jest.js --runInBand
```

Guard Malloc is **not optional** for this migration — it is the only tool in
the stack that catches the silent ignored-output-slot class. Confirm the
`GuardMalloc[node-…]` banner appears; macOS strips the insertion for hardened
binaries and a stripped run is green while testing nothing.

`--emit llvm` is also a first-class tool here and was what settled the `_ = x^`
question in minutes. When you are unsure whether a keep-alive binds, compile
the pair and read the IR — do not wait for a crash that may never come.

## Definition of done

- Every FFI signature off `AnyOrigin`, or a written reason why a given one
  stays.
- The at-risk set re-derived after the flip, with zero unpinned sites
  (`node scripts/derive-population-b.mjs --check`). Re-run it after EVERY
  batch, not once at the end: a site that gains a new local, or loses its
  post-call use, becomes at-risk without anything else changing.
- Full stack above green on macOS and Linux, Guard Malloc banner confirmed.
- Benchmark ceilings unchanged or reseeded deliberately.
- This document and `docs/plan-origin-migration.md` closed out.
