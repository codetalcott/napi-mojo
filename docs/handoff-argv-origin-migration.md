# Handoff: the population-B FFI signature flip

> **Read `docs/plan-origin-migration.md` first.** It is the record of the field
> migration (population A, 0.10.0) and of the keep-alive work (population B
> step 1), and it defines the two populations this document depends on. Do not
> start here.

## State: step 1 is done, step 3 is what remains

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

CLAUDE.md notes upstream documents `UnsafeAnyOrigin` as slated for deprecation
and removal, which is the eventual forcing function. As of 2026-08-20 that had
not landed:

- The 26.6 nightly changelog lists origin **renames**, not removals —
  `ImmutUnsafeAnyOrigin`→`ImmUnsafeAnyOrigin`, `ExternalOrigin`→`UntrackedOrigin`,
  `MutExternalOrigin`→`MutUntrackedOrigin`, and so on.
- **This codebase uses zero of the renamed spellings.** Verified counts:
  `ImmutUnsafeAnyOrigin` 0, `MutUnsafeAnyOrigin` 0, `ImmutUntrackedOrigin` 0,
  `StaticConstantOrigin` 0, `ExternalOrigin` 0. It uses `MutAnyOrigin` (~946),
  `ImmutAnyOrigin` (~138), and the already-modern `MutUntrackedOrigin` (~55) /
  `ImmUntrackedOrigin` (~18).

Re-run those counts against the current changelog before starting. If removal
has landed, this stops being elective and the schedule is no longer yours —
which is exactly the situation `docs/plan-origin-migration.md` warns about:
*"the alternative is doing it against a broken build on a deadline, in the one
area of this codebase that has already produced SIGSEGVs."*

## Deriving the population fresh

Do not trust a number in a document, including this one. The counts above came
from a script that joins line-wrapped statements before matching, because most
sites are wrapped:

```mojo
var recv_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
    to=recv
).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
```

A same-line grep finds ~153 of the ~247 that exist. **Two false-positive
classes** a naive pattern sweeps in and that are NOT population B:

- **Function-pointer reinterprets** — `Pointer(to=x).unsafe_bitcast[SomeFn]()[]`.
  The trailing `[]` dereferences immediately, before any call, so no lifetime
  spans the FFI boundary. `raw.mojo`'s ~150 slot casts and every
  `var fn_ref = my_callback` are this. Filter on
  `.unsafe_bitcast[NoneType]()` *not* followed by `[]`.
- **`StringLiteral` / `StaticString` parameters** — `name.unsafe_ptr()` in
  `define_class`, `JsFunction.create`, `JsSymbol.create_for`, ... static
  `.rodata`, never freed.

And one class that reads dangerous but is not: a **borrowed non-register-
passable struct**, e.g. `define_property`'s `desc: NapiPropertyDescriptor`. It
is memory-passed, so the pointer is to the *caller's* storage and the caller's
borrow guarantees liveness through the nested FFI call. The risk for those, if
any, lives at the call site.

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
- The at-risk set re-derived after the flip, with zero unpinned sites.
- Full stack above green on macOS and Linux, Guard Malloc banner confirmed.
- Benchmark ceilings unchanged or reseeded deliberately.
- This document and `docs/plan-origin-migration.md` closed out.
