# Plan: distribution — runtime reach, artifact portability, publishing

**Status**: **P0 implemented** (2026-09-13) — the cross-runtime gate
(`scripts/check-runtimes.mjs`, the `runtimes` CI job), the
`addAsyncCleanupHook` handle fix, and the README runtime matrix. **P1–P5
remain proposals.** The measurements in
[Findings](#findings-measured-2026-09-13) are real and reproducible.

**Created**: 2026-09-13
**Driver**: the sibling [`mojo-http`](https://github.com/codetalcott/mojo-http)
shipped `m0serve` to PyPI — a Mojo binary installed by Python web developers who
never install Mojo. That is the same move napi-mojo makes toward npm, executed
independently, and comparing the two exposed work this repo has not done:
a portability gate, a licensing declaration, and author-facing publishing
tooling. Probing the published binary on other JavaScript runtimes while
sizing that work turned up two defects.

## Context

napi-mojo's documentation addresses one audience: a JavaScript developer who
wants a fast native function. Two others exist and are unserved:

| | audience | status |
|---|---|---|
| A | JS dev calling Mojo | served — the tutorial, the code generator, `.d.ts` |
| B | Mojo dev consuming Node/npm | shipped as host mode; thin, and no demand signal |
| C | Mojo dev **shipping to** the Node ecosystem | capable, but no tooling or docs address them |

C is where the evidence points. The only known real consumers of this
framework — `@qkstat/retrieve` and `@qkstat/embed` — are audience C, and
`m0serve` is the same audience in another ecosystem, further along. The
shared problem across both repos is not N-API: it is **shipping a
redistributable Mojo binary through someone else's package manager.**

Both repos solved that independently, and both hit the same class of bug — a
test that passes on the one machine where the defect cannot manifest:

- napi-mojo: `bundle-runtime.sh` once carried a hardcoded four-library list;
  Linux also needs `libNVPTX.so`, so a published `@napi-mojo/linux-x64` failed
  at `require()` for anyone without a Mojo install. `npm test` ran against the
  pre-bundle build with the pixi environment still on the search path.
- mojo-http: `smoke-ffi` `dlopen`ed the artifact **in the build tree**. Seven
  releases shipped an asset whose `LC_RPATH` named the CI runner's home
  directory. `docs/FFI_DISTRIBUTION.md` is the write-up.

mojo-http's answer is further developed and is the thing worth borrowing:
`scripts/ffi_portability_check.py` asserts, by **static inspection**, that
every recorded search path is self-relative and every dependency is either a
system library or shipped alongside — a property no load attempt on the build
machine can establish.

## Findings (measured 2026-09-13)

Against the **published** `@napi-mojo/linux-x64@0.13.0` (`npm pack`, not a
local build), on linux-x64, with call signatures taken from `tests/`:

| | Node v22.22.2 | Deno 2.9.6 | Bun 1.3.11 |
|---|---|---|---|
| sync, strings, type-checked args | ok | ok | ok |
| errors, `throwValue`, catch-and-return | ok | ok | ok |
| callbacks, `mapArray` handle scopes | ok | ok | ok |
| promises (create/resolve/reject) | ok | ok | ok |
| async work + cancellation | ok | ok | ok |
| ThreadsafeFunction (`asyncProgress`) | ok | ok | ok |
| classes, wrap/unwrap, prototype chain, statics | ok | ok | ok |
| ArrayBuffer / Buffer / TypedArray / DataView / detach | ok | ok | ok |
| BigInt (incl. word arrays), Date, Symbol | ok | ok | ok |
| **primitive `napi_ref`** (number, string) | ok | ok | **ok** |
| external data, finalizers, instance data | ok | ok | ok |
| `parallelize_safe` init, global cache | ok | ok | ok |
| host-mode `callN` / `callMethod` / `scopedCall` / CPS | ok | ok | ok |
| `napi_get_version` | 10 | 10 | **9** |
| type-tag mismatch on a borrowed method | `TypeError`, framework message | same | **plain `Error`, generic message** |
| `napi_add_async_cleanup_hook` | ok | **double free at teardown** | ok |
| add **then remove** an async cleanup hook | ok | **double free at teardown** | **process abort** |

Three things follow.

**1. The framework is essentially runtime-portable already.** Every N-API
surface this framework exposes — including the ones most likely to be
unimplemented elsewhere: async work on libuv worker threads, ThreadsafeFunction,
escapable scopes, type tagging, external memory — behaves identically on all
three runtimes. That is a claim the README cannot currently make, and it costs
nothing to start making.

**2. Bun reports N-API v9 but implements the v10 behaviour we depend on.**
`CLAUDE.md` notes that primitives in a `napi_ref` need v10. Bun answers `9` to
`napi_get_version` and stores primitives in a reference anyway. So a version
check would refuse Bun wrongly; do not add one.

**3. Two defects, found only by leaving Node — and both are upstream.**

Attribution was settled by rebuilding each sequence as a **plain C N-API
addon** (`gcc -shared -fPIC -I <node>/include/node`) with no Mojo anywhere in
it. Both reproduce:

| C addon does | Node | Deno | Bun |
|---|---|---|---|
| register one hook; it calls `napi_remove_async_cleanup_hook` from inside itself, the documented completion signal | ok | **`free(): double free detected in tcache 2`** | ok |
| register one hook, remove it from JS before exit | ok | ok | ok |
| register two hooks with an identical `(function, data)` pair | ok | **`double free or corruption (fasttop)`** | **abort: "duplicate async NAPI environment cleanup hook"** |

So **neither is napi-mojo's bug to fix.** Deno double-frees a handle after the
hook has already surrendered it, on the documented happy path; Bun asserts that
`(function, data)` is unique, which N-API nowhere requires.

What *was* ours is that `remove_async_cleanup_hook_fn`
(`src/addon/env_ops.mojo`) walked straight into the second row. It registered a
second hook with an identical pair — same `async_cleanup_hook_noop`, same
bindings pointer — purely to obtain a handle it could remove, because
`addAsyncCleanupHook` returned `true` and dropped the real handle. The pair it
removed was therefore never the pair the caller added, and the caller's hook
stayed registered: the function's name did not describe what it did. Fixed by
returning the handle (as an External) and removing *that* — the middle row,
which is clean everywhere.

Deno's remains reachable by any addon that registers an async cleanup hook and
lets it run at exit, which is the normal use. That is documented, not fixed.

Neither defect is reachable from `npm test`, and neither would ever have been
found by a gate that only runs Node.

**Unrelated finding, same probe.** `Object.keys(addon)` returns **5** — the
classes. Every function export is non-enumerable (`napi_default`), so
`console.log(addon)`, tab-completion and any tooling that enumerates the module
see almost nothing. napi-rs marks exports enumerable. Worth a decision.

## Priorities

Ordered by evidence and by cost, not by appeal. Each item states what would
make it done.

### P0 — Cross-runtime gate, and the two defects it found — **DONE**

**Why first**: it was the only item with defects already on the table, and the
cheapest instrument that would have caught them. It also converts "works in
Node" into "works in Node, Deno and Bun", which is the positioning claim with
the widest reach per unit of work.

1. **`remove_async_cleanup_hook_fn` fixed.** `addAsyncCleanupHook` now returns
   the `napi_async_cleanup_hook_handle` as an External and
   `removeAsyncCleanupHook(handle)` removes *that* hook, so no duplicate
   `(function, data)` pair is ever registered. The old shape also meant remove
   never removed what add had registered — the name did not describe the
   behaviour. `tests/async_cleanup.test.js` pins the API; the runtimes gate
   pins the process-level consequence.
2. **The Deno double free is characterised and is Deno's.** A plain C addon
   reproduces it on the documented happy path (table in
   [Findings](#findings-measured-2026-09-13)). Not fixable here; recorded in
   the README's runtime matrix and in `KNOWN_DEFECTS`, with a two-line
   reproducer. **Still to do: report it upstream**, with the C reproducer —
   worth doing, and a decision for a human rather than something to file
   automatically.
3. **`scripts/check-runtimes.mjs` + a non-required `runtimes` CI job**
   (ubuntu-latest; Bun and Deno at pinned versions via their official actions).
   Each scenario runs as its own child process, compared against Node as the
   control, and **fails on a heap error or a non-zero exit**, not only on a
   wrong value — both defects surfaced as process-level events, not assertion
   failures, and one of them printed after the last line of user code with a
   zero exit status.
   - `KNOWN_DEFECTS` is a ratchet, not a mute: each entry must still
     reproduce, so a runtime that ships a fix turns the gate red and the
     allowance cannot outlive the bug. Same shape as `KNOWN_UNDOCUMENTABLE`
     in `check-docstring-coverage.mjs`.
   - It runs against the ordinary `build/index.node`, not a bundled one:
     this gate is about runtime semantics, and artifact portability is P1's
     subject with its own gate.
4. **README runtime matrix** — what is verified, on which versions, what is
   known-broken upstream, and the rule that a `napi_get_version` check would
   refuse Bun wrongly.

### P1 — Artifact portability gate (port from mojo-http)

Port `scripts/ffi_portability_check.py` to `scripts/check-portable.mjs`
(JS, to match this repo's tooling — the logic is `otool -l` / `readelf -d`
parsing and a set comparison, not Python-specific). Run it in `publish.yml`
**before** the upload step, over `build/index.node` plus every library named in
`build/bundled-libs.txt`.

It asserts what the current "Verify bundled binary is self-contained" step
cannot: that step clears `DYLD_*`/`LD_LIBRARY_PATH` and loads the binary, which
is a load attempt on the machine that built it. Static inspection catches a
stale absolute rpath that happens to still resolve on that runner.

**Done when**: the gate fails on a deliberately un-relocated build and passes
on a bundled one, both platforms, and the sabotage is recorded the way
mojo-http records its own.

**Cost**: moderate, mechanical, no design risk — a reference implementation
exists and is proven.

### P2 — Licensing and contents of the platform packages

`npm/<platform>/package.json` declares `"license": "MIT"` and ships
`"*.so*"` / `"*.dylib*"`. The published `@napi-mojo/linux-x64@0.13.0` tarball
contains, beside `index.node`: `libKGENCompilerRTShared.so`,
`libAsyncRTRuntimeGlobals.so`, `libMSupportGlobals.so`, **`libgcc_s.so.1`** and
**`libstdc++.so.6` (23.9 MB)**. None of that is MIT, and none of it is
attributed.

mojo-http resolved the same question for its wheel: `license = "MIT AND
Apache-2.0 WITH LLVM-exception"`, `license-files = ["licenses/*"]`, with
`LICENSE.mojo-runtime.txt` and `NOTICE.bundle.txt` carried in the artifact, and
`docs/FFI_DISTRIBUTION.md` recording the unresolved question about
redistributing Modular's prebuilt runtime binaries (Apache-licensed sources,
proprietary `LicenseRef-MAX-Platform-Software-License` wheel metadata).

Two separate actions:

1. **Attribution.** Carry equivalent license/NOTICE files in each platform
   package and correct the `license` field. Cheap, and it is the same
   determination mojo-http already made — reuse its reasoning rather than
   redoing it.
2. **Question `libstdc++`.** 23.9 MB of the ~27 MB package, shipped under the
   GCC Runtime Library Exception, and it is worth establishing whether the
   Mojo runtime genuinely needs a bundled copy or whether the host's is
   adequate. If it is adequate, the package shrinks by ~88%.

**Done when**: each platform package declares what it actually contains, and
the `libstdc++` question has a recorded answer either way.

### P3 — Publishing scaffolding for addon authors

`napi-mojo init` emits `exports.toml`, `fns.mojo`, `lib.mojo`, `.gitignore`,
`README.md` — no `package.json`. `docs/TUTORIAL.md` §9 is four lines and
`build --bundle`, which is one platform on one machine. Everything past that —
the CI matrix, the `optionalDependencies` fan-out, the npm trusted-publisher
setup — an author reinvents, and will hit the same `E404 ... PUT`
first-publish trap that cost this repo a release.

Proposed: `napi-mojo init --publish` (or a `release --scaffold` verb) emitting
a root `package.json` with `optionalDependencies`, the platform stubs, and a
matrix release workflow. Two details worth copying from `m0serve` rather than
inventing:

- **Measure the platform declaration, do not infer it.** `hatch_build.py`
  refuses to build without a tag derived from the staged binaries. napi-mojo's
  platform packages declare `os`/`cpu` by hand.
- **The consume job has no checkout and no toolchain**, and asserts its own
  cleanliness before it asserts anything about the artifact — otherwise
  someone adds a checkout "to get a test app" and the proof silently reverts
  with a green tick.

**Done when**: a scaffolded project publishes prebuilds for the three
supported platforms with no hand-written CI, and an e2e CI step exercises the
scaffold the way the host-mode scaffold step already does.

**Cost**: the largest item here, but JS tooling only — no FFI, no framework
surface, no new elaboration coverage.

### P4 — Positioning

- A page for audience C: the Mojo author shipping to npm. Currently nothing
  addresses them, and they are the only demonstrated consumers.
- README "Two directions" table: mojo-http's row reads "reaches npm: no",
  which implies it reaches no foreign ecosystem. It reaches PyPI. One line.
- The export enumerability decision from Findings.

### P5 — Host-mode marshalling codegen

Unchanged from its previous assessment and still last: the generator's
`[structs.*]` converters are direction-agnostic but wired only into the addon
callback path, and the real lever would be the inverse generator (a `.d.ts` or
TOML declaration of an npm module's shape → typed Mojo wrappers). Above it
sits a structural ceiling — Mojo has no `await`, which is correctly decided
and not going to change — and below it, no demand: nothing outside
`examples/host/` is a host-mode program.

**Gate**: a host-mode program written by someone, anywhere, that is not in this
repo.

## Non-goals

- **A shared distribution package across the two repos.** Two consumers,
  tooling in different languages, and `docs/plan-bidirectional.md` already
  rules out a build-time dependency in either direction. Copy the check; do
  not couple the repos.
- **Claiming Bun/Deno support in the published package metadata** before the
  P0 gate exists. A support claim without a gate is the thing this repo's
  own methodology is against.
- **Vendoring `m0serve`'s Python tooling.** Port the logic, not the files.
- **A version check that refuses runtimes below N-API v10.** Bun reports 9 and
  works; see Findings.

## Risks

- **The Deno double free may not be ours**, and chasing it could absorb the
  P0 budget. Timebox it; the fix for the Bun abort and the gate itself are
  the deliverables that stand regardless.
- **A non-required CI job that nobody reads is theatre.** The `benchmark` job
  works because it prints observed/ceiling on every run. The runtimes job
  needs an equivalent always-visible summary.
- **Third-party runtime versions move fast.** Pin the versions the matrix
  tests and bump them deliberately, so a red job means a regression rather
  than a new release.
- **P2's attribution work touches published artifacts.** It changes package
  metadata, not code, but it should ride a release rather than a hotfix.

## Reproducing the findings

```bash
npm pack @napi-mojo/linux-x64          # the published artifact, not a local build
tar xzf napi-mojo-linux-x64-*.tgz
# then load package/index.node under node, deno and bun and exercise
# tests/-derived call signatures; compare against Node as the control.
```

The attribution recipe — a plain C addon, no Mojo, no build system:

```bash
gcc -shared -fPIC -I "$(dirname "$(command -v node)")/../include/node" \
    -o cprobe.node addon.c
```

`addon.c` needs `#include <node_api.h>`, a `NAPI_MODULE_INIT()` exporting three
functions, and a hook body of `napi_remove_async_cleanup_hook(handle);`. The
three rows of the table above are: register once; register once and
`napi_remove_async_cleanup_hook` from JS before exit; register twice with the
same `(hook, NULL)` pair. Deliberately not checked in — an unbuilt file in this
tree rots, and this one is minutes to rewrite from the table.

The minimal reproducers against the addon itself are two lines each:

```js
const a = require('./build/index.node');
a.addAsyncCleanupHook();          // Deno: double free at teardown
```

```js
const a = require('./build/index.node');
a.addAsyncCleanupHook();
a.addAsyncCleanupHook();          // Bun: process abort on the duplicate pair
```

Both are `KNOWN_DEFECTS` entries in `scripts/check-runtimes.mjs`, where the
gate asserts they *still* reproduce. On the published 0.13.0 binary the second
one was reachable as `a.removeAsyncCleanupHook(a.addAsyncCleanupHook())`,
because remove registered the duplicate itself; that is the part this change
fixed.

## Reference

- [`docs/plan-bidirectional.md`](plan-bidirectional.md) — host mode, and why
  libnode embedding is rejected
- [`docs/plan-typed-helpers.md`](plan-typed-helpers.md) — the deferral
  convention used by P5
- mojo-http `docs/FFI_DISTRIBUTION.md` — the portability failure and its fix
- mojo-http `scripts/ffi_portability_check.py`, `scripts/bundle_artifact.py`,
  `packaging/m0serve/hatch_build.py` — the implementations P1 and P3 borrow from
