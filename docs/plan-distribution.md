# Plan: distribution — runtime reach, artifact portability, publishing

**Status**: **P0–P4 implemented, plus the GCC-runtime removal** (2026-09-13) —
the cross-runtime gate (`scripts/check-runtimes.mjs`, the `runtimes` CI job),
the `addAsyncCleanupHook` handle fix, the README runtime matrix, the artifact
portability gate (`scripts/check-portable.mjs`), per-platform licence
declarations with their texts, `napi-mojo release --scaffold` for addon
authors, the positioning work, and dropping the bundled GCC runtime — which
takes the Linux packages down 91% and removes their GPL declaration.
**P5 remains a proposal.** The measurements in
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

### P1 — Artifact portability gate (port from mojo-http) — **DONE**

`scripts/check-portable.mjs`, ported from mojo-http's `binfmt.py` +
`ffi_portability_check.py`, runs in `publish.yml` against
`/tmp/selfcontained/` — the consumer's layout the step above it already
assembles — over `index.node` and every library in `build/bundled-libs.txt`.

It asserts what "Verify bundled binary is self-contained" cannot. That step
clears `DYLD_*`/`LD_LIBRARY_PATH` and loads the binary, on the one machine
where a stale absolute rpath can still resolve. This reads the load commands.

Three carried-over decisions, each of which mojo-http paid for:

- **Parse the bytes; do not shell out.** `otool` exists only on macOS, so a
  Linux job cannot inspect a macOS artifact at all — and `llvm-objdump` *does*
  exist on macOS but prints ELF dynamic entries in another format, so the
  regexes matched nothing, the function returned empty lists, and a Linux
  artifact was reported portable. A guard that answers "fine" when it cannot
  read the file is worse than no guard.
- **Three states, not one bit.** broken / satisfiable / self-contained. A
  build can be moved to `satisfiable` unilaterally; `self-contained` depends
  on the runtime-redistribution question that is P2's subject, so collapsing
  them would make the gate either toothless or a release blocker.
- **An executable has no `LC_ID_DYLIB`.** Treating the first dependency as the
  install name is the bug the parser was extracted for, and it is invisible to
  any test that only ever looks at one kind of file — hence the synthesised
  fixtures for both.

**Verified on real artifacts**, all three states, plus the parser self-test in
`test.yml` on both platforms:

| control | verdict | exit |
|---|---|---|
| published `@napi-mojo/linux-x64@0.13.0` bundle, all four files | self-contained | 0 |
| the same `index.node` with its libraries absent | satisfiable | 0 |
| …the same, with `--require-self-contained` | satisfiable, refused | 1 |
| a `gcc -shared` ELF with an absolute rpath and an absent dependency | **broken** | 1 |

The last row is the one that matters: a gate never seen to fail is not
evidence. Its message names the recorded build path verbatim.

**Still not covered**: bundling is verified only at release time, because
`test.yml` builds without `bundle-runtime.sh`. Running the bundler per PR
would catch a bundling regression earlier and is worth considering; it needs
`patchelf` on Linux and codesigning on macOS, so it was not folded in here.

### P2 — Licensing and contents of the platform packages — **DONE**

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

**Attribution — done.** `licenses/` carries the Apache 2.0 + LLVM Exception
text, GPLv3, the GCC Runtime Library Exception 3.1, and a `NOTICE.bundle.txt`
naming what each platform ships. `scripts/platforms.mjs` gained per-platform
`license` and `licenseFiles`, `publish.yml` stages them from that one
declaration, and `check-platforms.mjs` asserts the manifests and the texts
agree (sabotage-tested both ways: a reverted `license` field and a deleted
text each fail it).

Per-platform, because the packages genuinely differ:

| | contents beside `index.node` | declared |
|---|---|---|
| darwin-arm64 | 4 Mojo runtime dylibs, ~3.3 MB | `MIT AND Apache-2.0 WITH LLVM-exception` |
| linux-x64 / linux-arm64 | 3 Mojo runtime `.so` + `libgcc_s.so.1` + `libstdc++.so.6`, ~27 MB | the same, `AND GPL-3.0-or-later WITH GCC-exception-3.1` |

macOS ships no GCC runtime — Mojo's runtime links the system libc++ there —
so shipping GPLv3 in that tarball alongside a declaration that does not
mention it would be misleading rather than thorough. `bundle-runtime.sh`
rewrites the rpath / install name of every bundled library, so the Apache
§4(b) modification notice applies and is recorded.

The GPL declaration on the Linux packages is accurate and will be read by
licence scanners. That is a real cost, and it is an argument for the next
item rather than for understating what is in the tarball.

### The bundled GCC runtime — measured, and probably redundant

**`libstdc++.so.6` is 23.9 MB of the 27 MB Linux package. The evidence says
it is not needed.** Measured on `@napi-mojo/linux-x64@0.13.0`:

- The three Mojo runtime libraries require at most **`GLIBCXX_3.4.30`** and
  **`CXXABI_1.3.11`**.
- They also require **`GLIBC_2.35`**, which cannot be bundled — glibc is the
  loader. So the package already refuses any host below Ubuntu 22.04.
- Ubuntu 22.04 *is* glibc 2.35, and ships GCC 12's libstdc++, which provides
  `GLIBCXX_3.4.30`. **The two floors coincide**: every host that can satisfy
  the un-bundlable requirement already satisfies the bundled one.
- Node itself is a C++ program linked against `libstdc++.so.6` and
  `libgcc_s.so.1`, so both are present wherever a Node process runs. **That
  argument does not extend to Bun or Deno** — see *Bun and Deno images* below.
- Direct test: deleting both files from the extracted package and loading it
  with `LD_LIBRARY_PATH` cleared works — `hello()`, `asyncRuntimeInitOk()`,
  `globalCacheActive()` and an async round trip all pass against the host's
  own libstdc++.

#### Bun and Deno images — where the host argument stops

Measured 2026-09-13 from the official release binaries (DT_NEEDED) and every
layer of the official images, amd64 and arm64, at the versions pinned in
`test.yml`:

| | links libstdc++ | links libgcc_s |
|---|---|---|
| bun 1.3.11 (glibc build) | no — C++ runtime is static | no |
| deno 2.9.6 | no | yes |

So under Bun and Deno the **image** has to supply libstdc++, and a minimal
image has no reason to:

| image | libstdc++ | glibc | loads the 0.14.0 bundle |
|---|---|---|---|
| `oven/bun:1.3.11`, `-slim` (Debian 13) | 3.4.33 | 2.41 | yes |
| `oven/bun:1.3.11-distroless` | **none** | 2.41 | **no** — `libstdc++.so.6` not found |
| `oven/bun:1.3.11-alpine` | musl build only | none | **no** — musl; never could |
| `denoland/deno:2.9.6`, `debian-`, `distroless-` | 3.4.33 | 2.41 | yes |
| `denoland/deno:ubuntu-2.9.6` (22.04) | 3.4.30 | 2.35 | yes, exactly at the floor |
| `denoland/deno:alpine-2.9.6` | **none** in its glibc layer | 2.36 | **no** — `libstdc++.so.6` not found |

0.13.0, which bundled libstdc++, loads on Bun distroless and Deno alpine; 0.14.0
does not. That is the one real cost of the removal, and it is a trade rather
than a defect: re-bundling would restore those two images at 10x the package
size for every user. `consume-oldest-linux` holds both sides — the bundle
loads on `oven/bun:*-slim` and `denoland/deno:distroless`, and is refused on
Bun distroless with the loader's `libstdc++.so.6` error rather than a crash.

#### Done: both guards, then the removal.

The two things this asked for before anyone deleted a library:

1. **`scripts/check-glibc-floor.mjs`** — reads ELF `.gnu.version_r` and asserts
   that the `GLIBCXX` the shipped set requires is provided by *every*
   distribution whose glibc is new enough to load us. It takes the **worst**
   host, not a convenient one: a build needing only `GLIBC_2.34` is held to
   RHEL 9's `GLIBCXX_3.4.29`, not Ubuntu 22.04's `3.4.30`. Runs pre-bundle in
   `test.yml` on every PR (the closure resolves through whatever search paths
   the artifact records, which before bundling point at the pixi environment)
   and again on the staged set in `publish.yml`. Reports and exits 0 on macOS.
2. **`consume-oldest-linux`** in `publish.yml` — no checkout, no toolchain,
   three docker cases on each Linux platform: the bundle loads on Debian 12
   (glibc 2.36, the closest official Node image to the floor); **the same
   bundle with the GCC runtime deleted also loads**; and the bundle is
   *refused* below the floor on Debian 11, with a loader version error rather
   than a crash. `publish` now needs it, so a release cannot outrun it.

Case 2 is the point: the evidence for dropping the libraries is re-measured on
every release, so the day it stops holding is the day the job goes red —
before anyone removes them, not after.

Writing the first guard found a bug in the first guard, worth recording
because it is the failure shape this whole document is about: run against an
`index.node` whose siblings were absent, it reported `GLIBCXX: (none)` and
**passed** — while the library it could not open was the one carrying the
`3.4.30` requirement. An unresolved dependency is now a failure, not a note.

#### The removal

`bundle-runtime.sh` now skips `libstdc++.so*` and `libgcc_s.so*` via an
explicit `HOST_PROVIDED` list rather than dropping them from the closure walk
silently, and prints what it left behind. Measured on the published linux-x64
0.13.0 package, the result is **26.1 MB → 2.4 MB unpacked, a 9.4 MB → 0.9 MB
tarball: 91% either way** — more than the 88% estimated from libstdc++ alone,
because libgcc_s goes too.

The GPL declaration went with them. All three platform packages are now
`MIT AND Apache-2.0 WITH LLVM-exception`, `licenses/` no longer carries GPLv3
or the GCC Runtime Library Exception, and `NOTICE.bundle.txt` records what
0.13.0-and-earlier tarballs do contain for anyone auditing one.

`consume-oldest-linux`'s second case changed with it. "The same bundle with
the GCC runtime deleted also loads" is now a no-op — there is nothing to
delete — so it asserts the inverse: the bundle contains **no** GCC runtime and
the manifest names none. `bundle-runtime.sh` discovers its closure at build
time, so a toolchain change could put them back and the package would silently
regain an order of magnitude and a GPL declaration.

**Verified before pushing**, on the real published artifact with both
libraries removed: it loads with `LD_LIBRARY_PATH` cleared —`hello()`,
`asyncRuntimeInitOk()`, `globalCacheActive()` and an async round trip all pass
against the host's libstdc++ — `check-portable.mjs --require-self-contained`
still reads self-contained across all four files, and `check-glibc-floor.mjs`
passes. What is **not** verified locally is `bundle-runtime.sh` itself: there
is no Mojo toolchain or patchelf in the session that wrote this, so the skip
logic was simulated against the real library names and the first real run is
CI's.

**The residual risk is unchanged and now bounded**: a host with glibc ≥ 2.35
and an older libstdc++ is constructible and no table or container represents
it. Such a host gets a loader version error at `require()`, not corruption.

### P3 — Publishing scaffolding for addon authors — **DONE**

`napi-mojo init` emits `exports.toml`, `fns.mojo`, `lib.mojo`, `.gitignore`,
`README.md` — no `package.json`. `docs/TUTORIAL.md` §9 is four lines and
`build --bundle`, which is one platform on one machine. Everything past that —
the CI matrix, the `optionalDependencies` fan-out, the npm trusted-publisher
setup — an author reinvents, and will hit the same `E404 ... PUT`
first-publish trap that cost this repo a release.

**Shipped as `napi-mojo release --scaffold [dir]`.** It patches (never
overwrites) the project's `package.json` — merging `optionalDependencies` on one
prebuilt package per platform, leaving an existing `main` and an absent `files`
alone — and each `npm/<platform>/package.json`, so re-running it resyncs
versions without losing author fields. The loader (which prefers a local build
over the registry) and the release workflow are written only when absent;
`--force` overwrites them. Platform manifests declare a licence covering what
they carry (the author's, napi-mojo's MIT, and the Mojo runtime's terms from
`platforms.mjs`) with the texts beside them, and inherit `repository` — taken
from the git remote when absent — because provenance publishing rejects a
package without a matching one. `release --sync` sets every manifest to the
root version (wired to `npm version`, and checked by the workflow before it
publishes), and `release --bootstrap` does the first publish as a
`0.0.0-bootstrap.0` placeholder so trusted publishing can be configured
without burning the real version on an empty package. The platform list comes from `scripts/platforms.mjs` — the same
single declaration `check-platforms.mjs` gates — rather than a second list in
the CLI.

What the generated workflow carries, and why:

- **The consume job has no checkout and no toolchain**, and asserts its own
  cleanliness before it asserts anything about the artifact. Otherwise someone
  adds a checkout "to get a test app" and the proof silently reverts with a
  green tick. Copied from `m0serve`'s release pipeline.
- **`check-portable.mjs` runs on every platform's bundle** (P1), because a
  load test where the artifact was built passes even when the artifact only
  works there.
- **The `files` glob keeps its trailing `*`** — Linux sonames are versioned,
  and a bare `*.so` silently drops them. That shipped from this repo twice.
- **The first-publish bootstrap is spelled out** in the command's own output
  and in the workflow's header: npm's OIDC trusted publishing matches a
  per-package publisher, and a package that has never been published has
  nothing to match, so the `E404 ... PUT` that cost this repo the 0.13.0
  release is an authorization error wearing a disguise.

**The e2e runs the CLI from the packed tarball, not the checkout.** The CLI
now imports `scripts/platforms.mjs` and the generated workflow calls
`scripts/check-portable.mjs`; neither was in `package.json` `files`. Running
from the repo cannot see that, because the files are on disk either way — and
a missing entry breaks *every* CLI invocation for an installed user, not just
this verb. Packing first is the only thing that proves what they get.

Not done: `m0serve`'s measured-not-inferred platform tag. Its `hatch_build.py`
refuses to build without a tag derived from the staged binaries; both this
repo's platform packages and the scaffolded ones still declare `os`/`cpu` by
hand. Worth revisiting if a platform is ever mis-declared.

### P4 — Positioning — **DONE**

- **A README section for audience C**, "Shipping Mojo to npm" — the framework's
  most-used direction is not the one its name suggests, and nothing addressed
  the author who has Mojo code and wants users. It points at
  `release --scaffold`, the tutorial's section 9, the three-platform limit, and
  the licence consequence of shipping a runtime.
- **The mojo-http comparison row is honest now.** "reaches npm: no" implied
  mojo-http reaches no foreign ecosystem; it reaches PyPI, from the other
  direction, which is the whole reason this plan exists.
- **Module exports are enumerable**, and writable and configurable — ordinary
  `exports.foo = fn` semantics rather than `napi_default`. They were none of
  the three, so `Object.keys(addon)` returned five names (the classes, which
  are registered by another path and *were* enumerable), `{...addon}` lost
  every function, and assigning over an export silently did nothing: two
  behaviours in one module for no reason. Class prototype members deliberately
  keep the old attributes — a JS class method is non-enumerable.

  A side effect worth noting: `tests/typescript.test.js` asserts that every
  enumerable function on the addon is declared in the `.d.ts`, and that loop
  was **vacuous** — `Object.keys` handed it only the five classes, each of
  which it skips. It now checks all 153. Verified statically before the
  change: every exported name has an `export function` or `export class`
  declaration, so the newly-live assertion passes.

### P5 — Host-mode marshalling codegen

Unchanged from its previous assessment and still last: the generator's
`[structs.*]` converters are direction-agnostic but wired only into the addon
callback path, and the real lever would be the inverse generator (a `.d.ts` or
TOML declaration of an npm module's shape → typed Mojo wrappers). Above it
sits a ceiling — host-mode code runs on the JS thread, so it can continue
after a promise (`JsPromise.on_settled`) but never wait for one — and below it,
no demand: nothing outside `examples/host/` is a host-mode program. The ceiling
is a threading constraint, not a language one: Mojo has `await`, and napi-rs
shows the worker-thread bridge that would let Mojo code suspend on a JS
promise. That bridge is costed and gated separately in
[`plan-promise-bridge.md`](plan-promise-bridge.md).

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
