# Lazily checked artifacts

**Status: problem statement only. No design, no proposal.** Written 2026-09-17,
immediately after the Mojo 1.1.0 bump, while the evidence was fresh. Design and
implementation are deliberately deferred to a separate session.

---

## The class

> **A lazily checked artifact is one that is verified only when something
> happens to reach it.** Nothing reaches it → it rots silently, and every
> signal in the repo stays green.

This is not a category invented for this document — the repo already counts
instances by hand, in comments rather than in one place.
`.github/workflows/test.yml` numbers them as it goes ("A third lazily-checked
thing, alongside method bodies and generator templates"; "A fourth
lazily-checked thing: the exported-function table and the counts embedded in
prose"), and `docs/plan-api-reference.md` independently numbers a third
("`mojo doc` reaches a third lazily-checked surface"). That the numbering
disagrees across two files is itself the point: each instance was found the
same way — something broke, someone read source, the gate was written
afterwards — and no document holds the class. The open question is whether the
*class* can be addressed instead of enumerating instances one incident at a
time.

## Why this repo keeps hitting it

Four structural reasons, none of them accidental:

1. **Mojo elaborates an imported package's `def` body only when something in
   the compiled graph calls that exact method.** A body full of hard type
   errors compiles, packages and publishes as long as nobody calls it. Struct
   definitions are lazy too. This is a language property, not a nightly quirk.
2. **`src/generated/` is checked in and `npm run build` never regenerates it**,
   so the generator can drift from its own output.
3. **The package ships source that downstream compiles against**
   (`-I node_modules/napi-mojo/src`), so the published `src/` *and* the docs
   that explain how to write against it are part of the public contract.
4. **The gates are themselves artifacts.** `check-portable.mjs` and
   `check-glibc-floor.mjs` are binary-format parsers whose failure mode is an
   empty result that reads as "fine"; both needed `--self-test`. A gate that
   silently stops checking is the purest form of this bug.

## Inventory

| Artifact | How it rots | Gate | Known limit of the gate |
|---|---|---|---|
| Imported-package `def` bodies | Never called → never type-checked | `tests/compile/framework_coverage.mojo` + `check-compile-coverage.mjs` | Checks **names, not overloads**. Also: the coverage target and `build.sh` elaborate *different sets* (see below) |
| Struct definitions | Never constructed | Partly the docstring gate (`mojo doc` elaborates every declaration it opens) | Incidental, not designed for this |
| Generator templates | Branch nothing instantiates | Drift gate + `tests/codegen/kitchen-sink.toml` | Drift gate alone only proves what `exports.toml` instantiates |
| Docstrings | New public `def` with none | `check-docstring-coverage.mjs` (floor ratchet) | `raw.mojo` deliberately out of scope |
| Export table + prose counts | New export, stale number | `check-exports-doc.mjs` | Counts the **built addon**, so it passes on a branch and fails on the merge (hit this on #115) |
| API reference | Docstring edited | `generate-api-reference.mjs --check` | — |
| Platform declaration sites (7) | One site missed | `check-platforms.mjs` | — |
| Binary-format parsers | Offset slips → empty result | `--self-test` on both | — |
| Keep-alive barrier | Optimizer elides it | `check-keepalive-barrier.mjs` (IR counterfactual, **both halves**) | — |
| `parallelize_safe` init | Silent sequential fallback | `asyncRuntimeInitOk()` + `tests/runtime.test.js` | — |
| `parallelize_safe` results | Broken captures compute garbage | `parallelSquares()` + `tests/runtime.test.js` (added 2026-09-17) | — |
| Global symbol cache | Silent dlsym fallback | `globalCacheActive()` + `tests/global_cache.test.js` | — |
| Per-call overhead | dlsym creeps back onto hot path | `check-benchmark.mjs` | 4x headroom: catches an order of magnitude, not 10% |
| Runtime defect allowances | Bug fixed upstream, allowance outlives it | `KNOWN_DEFECTS` / `KNOWN_UNDOCUMENTABLE` ratchets | — |
| **Mojo warnings** | Deprecations accumulate | **NONE** | — |
| **Prose describing mechanism** | Mechanism changes | **NONE** | — |
| **Doc code samples (16 blocks)** | Idiom retired | **NONE** | — |
| **`plan-*` / `handoff-*` records** | API they cite changes | **NONE** | — |
| **Downstream/agent onboarding** | Does not exist yet | **N/A** | — |
| CHANGELOG entries | Feature merges without one | **NONE — deliberate** | "Does this deserve an entry" is judgment, not mechanism |

## What the Mojo 1.1.0 bump proved (2026-09-17)

Concrete, dated evidence. Every item below is a thing that was actually wrong.

- **A hard compile error was invisible to `build.sh` and to all 805 tests.**
  MAX 26.6 moved `parallelize` to a unified closure argument, so
  `parallelize_safe`'s body no longer compiled. Nothing instantiated it in the
  addon graph, so Mojo never elaborated it. Only
  `tests/compile/framework_coverage.mojo` surfaced it — the gate doing exactly
  its job, on a real regression rather than a synthetic one.
- **The same run raised the deprecation count from 26 to 38.** `build.sh` and
  the coverage target elaborate different sets, and **nothing says which is
  authoritative**. A warning inventory taken from the primary build is
  incomplete by roughly a third.
- **Five pieces of prose were stale or wrong**, all fixed in that change:
  `runtime_ops.mojo`'s header and `tests/runtime.test.js`'s header both still
  described `init_async_runtime` hand-resolving a symbol out of
  `libKGENCompilerRTShared` (replaced by `std.runtime.initialize_runtime()` in
  Mojo 1.0.0); `parallelize_safe`'s docstring still said "Equivalent to
  `parallelize[func](n)`"; and the changelog-diffing recipe in
  `toolchain-migrations.md` — *the single highest-value step in a bump, by its
  own description* — pointed at `mojo/docs/...` paths that now return a bare
  404 after the monorepo restructured to `Mojo/docs/site/...`. A 404 reads as
  "no such changelog", not "wrong path".
- **One note was an actively wrong diagnosis, not merely stale.** The
  dev2026080905 entry recorded `"assignment to 'X' was never used"` as a
  *compiler false positive on `capturing` closures* and instructed the reader
  not to delete the "dead" var. It was really a symptom of the capture not
  being tracked at all; spelling the parameter `capturing[_]` removed all five
  warnings. Stale prose is a nuisance; **prose that asserts a wrong mechanism
  actively misleads the next reader**, and nothing distinguishes the two.
- **#113 shipped a public framework method and a new export with no CHANGELOG
  entry**, against a convention the history plainly shows (`9238631`, a feature
  commit, created `## Unreleased` itself).

## The gap with the clearest shape: there is no warning gate

`docs/toolchain-migrations.md` states "The build is now warning-clean" as an
achieved property, and the 1.1.0 entry reports both builds warning-clean. **No
gate enforces it.** `grep -niE "warning|Werror" .github/workflows/test.yml
build.sh` finds no assertion on Mojo diagnostics anywhere; warnings have never
failed CI. That is why 27 new deprecations sat in the build output this session
until someone read the log, and it is why the count could differ between two
builds without anyone noticing.

This one has an obvious precedent in-repo: `check-docstring-coverage.mjs`
ratchets a per-file count against `scripts/docstring-floor.json`, may fall,
never rise. Whether that shape fits here — and across which builds — is a
design question, not settled here.

## Open design questions

Deliberately unanswered. These are the decisions the next session has to make.

1. **Scope.** Is the goal one gate for the sharpest instance (warnings), or a
   general mechanism? A general mechanism for *prose* may not exist.
2. **Which build is authoritative** for a warning inventory, given `build.sh`
   and the coverage target disagree by a third? Both? Is the coverage target
   supposed to be a superset, and should *that* be asserted?
3. **Prose.** Can staleness be made mechanical at all? Candidate shapes: mark
   claims that name a mechanism and assert the symbol still exists; or accept
   prose as unverifiable and instead reduce duplication so there is one place
   to fix. Note `tests/load_error.test.js` already extracts from
   `TROUBLESHOOTING.md` by heading, so renaming a heading breaks CI on purpose
   — a working precedent for making a doc load-bearing.
4. **Doc code samples.** 16 Mojo blocks across README / TUTORIAL / CLAUDE /
   CONTRIBUTING, none compiled. They are **currently clean** — a scan for 13
   retired idioms found zero hits on 2026-09-17 — so this is latent risk, not a
   present defect. Compile them, or extract them from files that already
   compile (`examples/tutorial/` is built in CI)?
5. **Downstream/agent onboarding, and its recursion.** `CLAUDE.md` is *not* in
   `package.json` `files`, so a consumer gets `src/`, `docs/api/`,
   `docs/EXPORTS.md`, `docs/TUTORIAL.md` and `examples/` with no map and none
   of the FFI rules — an agent there will write bare `capturing`, spell the
   bitcast inline, or use `_ = x^` as a keep-alive. **But a shipped rules
   extract is itself a new lazily checked artifact**: hand-maintained, it
   drifts from `CLAUDE.md` silently. Generated from a marked section, or
   accepted with a staleness risk? This is why the two topics belong in one
   document.
6. **What stays ungated on purpose**, and is that written down where someone
   will look before proposing a gate for it?

## Constraints any solution must respect

Drawn from this repo's own doctrine, not invented here:

- **Mechanical, not judgment.** `check-exports-doc.mjs` works because "is this
  export in the table" has one answer. A gate over a judgment call gets
  routinely bypassed, and a bypassed gate is worse than none because it reads
  as green.
- **A gate must fail on the known bug.** The recorded way to validate the
  elaboration gate is to revert `5161dfc` and confirm it fails *at exactly 6
  sites*. Anything added here needs the equivalent counterfactual, and the
  keep-alive gate's standard is higher still: it asserts **both halves**, so it
  cannot stop being evidence.
- **Ratchet, not mute.** An allowance must re-verify that its defect still
  reproduces, so it cannot outlive the bug.
- **Do not add a new required check.** Renaming the required set strands open
  PRs; the docstring gate is a *step inside* the required job for that reason.
- **Never add `paths-ignore` to the `pull_request` trigger.** A filtered-out
  workflow reports no checks at all, making a docs-only PR permanently
  unmergeable.
- **Non-required for anything timing- or third-party-dependent.**

## What this document is not

It is not a proposal, and the table above is not a backlog. Several rows are
correctly ungated. The question for the next session is which of the five
ungated rows deserve mechanism, which deserve deduplication instead, and which
should be recorded as deliberately ungated. For that last kind,
`docs/plan-typed-helpers.md` is the model worth copying: it defers
`napi.framework.cached_gpu` against a **named numeric trigger** ("revisit if we
accumulate 6+ cached GPU addons; currently 4") rather than an open-ended
"later", so the decision can be revisited without being re-argued.
