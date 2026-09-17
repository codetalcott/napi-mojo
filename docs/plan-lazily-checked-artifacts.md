# Lazily checked artifacts

**Status: problem statement written 2026-09-17, immediately after the Mojo
1.1.0 bump, while the evidence was fresh; decided and implemented the same day
in a separate session — see [Decisions](#decisions-2026-09-17) at the end.**
The problem statement below is left as written, so the decisions can be read
against the evidence that produced them.

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
| Mojo warnings | Deprecations accumulate | `--Werror` at every CI compile of our own Mojo + `check-werror.mjs` (both halves) — *added 2026-09-17* | `keepalive_probe.mojo` and CLI consumer builds are deliberately outside it (see Decisions) |
| Doc code samples (16 blocks) | Idiom retired | `check-doc-samples.mjs` (stanza-verbatim against CI-compiled files, `--self-test`) — *added 2026-09-17* | Verbatim ≠ elaborated; `fragment` fences are exempt and counted |
| Shipped `examples/codegen/` | Never compiled by CI | "Build and run codegen example" step — *added 2026-09-17* | Found while listing what CI compiles for the gate above |
| Downstream/agent onboarding | Hand-copied rules drift | `docs/MOJO-RULES.md` generated from `CLAUDE.md` + `generate-rules-extract.mjs --check` — *added 2026-09-17* | Rules cite files that do not ship; links point at the repo |
| **Prose describing mechanism** | Mechanism changes | **NONE — deliberate** | Not mechanical; see Decisions for the dedup rule and the trigger |
| **`plan-*` / `handoff-*` records** | API they cite changes | **NONE — deliberate** | Dated records; see Decisions |
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

*(Written before the decision; closed the same day — see Decisions, Q1–Q2.)*

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

## What this document was, before the decisions

It was not a proposal, and the table above was not a backlog. Several rows are
correctly ungated. The question for the next session was which of the five
ungated rows deserve mechanism, which deserve deduplication instead, and which
should be recorded as deliberately ungated. For that last kind,
`docs/plan-typed-helpers.md` is the model worth copying: it defers
`napi.framework.cached_gpu` against a **named numeric trigger** ("revisit if we
accumulate 6+ cached GPU addons; currently 4") rather than an open-ended
"later", so the decision can be revisited without being re-argued.

## Decisions (2026-09-17)

Taken in the follow-up session, each against the constraints above. Every gate
added was proven on a counterfactual before it was wired in.

### Q1 + Q2 — Scope, and which build is authoritative: `--Werror` everywhere, so the question dissolves

**Measured first.** Both `build.sh` and the coverage target were warning-clean
on the day (0 and 0), so the "ratchet a floor" shape from the docstring gate
was unnecessary: the floor is zero, and the compiler already has the gate —
`mojo build --Werror`, with `--Wno-error` and `--ignore-deprecated <NAME>` as
escape hatches. Proven on a scratch package before adoption: a deprecated
spelling (`@parameter` on a closure) **inside a `-I` package** warns without
the flag (exit 0) and fails with it (exit 1), which is the case that matters
because `build.sh` compiles `src/lib.mojo` as the main module and reaches the
whole framework by import.

**Adopted at every CI compile of the repo's own Mojo**: `build.sh` and
`tests/codegen/build.sh` default to the flag; the examples loop, the FFI probe
and the coverage target pass it inline. That answers Q2 by making the
disagreement impossible: no build is allowed to differ from zero, so none is
"the" inventory. Two sites needed a change to get there — the FFI probe's
`except` branch, which 1.1.0 had flagged as unreachable and the bump notes had
"left as-is", was flattened; the keep-alive probe was found to be
**un-flaggable on purpose** (its `_ = slot^` warning *is* the counterfactual
`check-keepalive-barrier.mjs` asserts) and stays outside. So do consumer builds
through the CLI (`napi-mojo build` / `run` compile a user's code) and the
Nightly Canary, which sets `NAPI_MOJO_WERROR=0` and counts warnings into its
summary — on a nightly a deprecation is the early signal it exists for, not a
failure to hide a real break behind.

**The counterfactual is standing, not one-off**: `scripts/check-werror.mjs`
runs in the required job and asserts both halves on every run. Its first half
(the idiom *still warns* without the flag) is what keeps it evidence — when a
toolchain retires that deprecation, the step goes red and the probe idiom has
to be replaced, so the gate cannot quietly stop proving anything. Same standing
as the keep-alive gate's "without_pin loses its alloca" half.

**Bump ergonomics**: the runbook's "fix hard errors before deprecations" would
be meaningless under the flag, so step 5 now says to run the bump with
`NAPI_MOJO_WERROR=0` and drop the override before opening the PR.

### Q4 — Doc code samples: verbatim from compiled source, mechanically

**Measured first.** Of the 16 blocks, 7 were already verbatim copies of
`examples/tutorial/fns.mojo` (the tutorial's CI step comment says "quotes
examples/tutorial/ line for line" — that sentence is now a check), and one
README block quoted a `process_config_pure` that **existed in no file at all**.
Nothing was stale yet; the fabricated function is the shape of the risk.

**The rule** (`scripts/check-doc-samples.mjs`): every ```` ```mojo ```` block
in README, TUTORIAL, CONTRIBUTING and CLAUDE.md is split into stanzas on blank
lines; a leading comment is a caption and is dropped; each stanza must appear
verbatim, indentation included, in a file `test.yml` compiles (the script lists
them by CI step). Stanza-level rather than block-level so a doc can quote an
import and a def that are not adjacent — the failure being guarded is a
spelling that changed, which any stanza catches. A snippet with no compilable
home is fenced ```` ```mojo fragment ```` and is **counted and printed**, so
exemptions stay visible (two today: CLAUDE.md's two-line function-pointer
idiom and CONTRIBUTING's `...` entry-point skeleton). A doc that yields zero
blocks fails the parser check, because an empty parse would otherwise read as
a clean pass — the docstring gate's first-run lesson. `--self-test` proves the
matcher on a synthetic doc: verbatim passes, one character of drift fails,
indentation drift fails, and the stanza split is shown to be what makes the
non-adjacent case pass.

**Known limit, stated in the script**: verbatim is not elaborated. A framework
body nobody calls still compiles unchecked; the compile-coverage target answers
that, not this gate.

**Fallout**: the README's host-mode sample now quotes `examples/host/main.mojo`
and its struct sample quotes the tutorial; CONTRIBUTING's docstring example is
`JsObject.has_own` verbatim rather than a paraphrase; CLAUDE.md's `_sym` block
had drifted from `raw.mojo` in line-wrapping only — harmless, and exactly the
kind of drift the gate exists for. Listing what CI compiles also found that
`examples/codegen/` ships in the npm tarball and was compiled by nothing; it is
now built and run in CI.

### Q5 — Onboarding: generated from CLAUDE.md, gated like `docs/api/`

The recursion resolves the way the doc suspected it would: the extract is
**generated**, so it cannot drift. `scripts/generate-rules-extract.mjs` copies
the "Mojo dialect and FFI rules" section of CLAUDE.md verbatim into
`docs/MOJO-RULES.md` (relative links rewritten to the repository, since the
files they cite do not ship), `--check` fails CI when the copy is stale, and
`package.json` `files` ships it. A consumer — or an agent in a consumer's
checkout — now gets the rules that keep the shipped source from crashing,
which is the framing the section already had. The doc-samples gate excludes
the extract, since it is checked through its source.

### Q3 + Q6 — What stays ungated, and the trigger for each

Recorded here so the next person finds it before proposing a gate:

- **Prose describing a mechanism** — no gate. Staleness is a judgment, and the
  one shape that is mechanical (a claim that names a symbol, asserted to still
  exist) would catch renames but not the actively-wrong diagnosis the 1.1.0
  bump found, which named nothing that had moved. The rule instead is
  **deduplication**: a mechanism is described in one place (the module header,
  or the CLAUDE.md section that owns it) and everywhere else links to it, so
  there is one thing to fix. `tests/load_error.test.js`'s extract-by-heading
  is the precedent for the rare doc that must be load-bearing, and stays the
  exception. **Trigger to revisit**: a toolchain bump that finds ≥ 5 stale or
  wrong prose claims again (the 1.1.0 bump found exactly 5); at that point the
  dedup rule has failed and a mechanism is worth its cost.
- **`plan-*` / `handoff-*` records** — no gate. They are dated, and a record
  that quotes a retired API is doing its job (this document's own "gap"
  section is now one). They are excluded from the doc-samples gate for that
  reason. **Trigger**: none; a record is not read as current, and the
  `Status:` line at the top of each is the mechanism.
- **CHANGELOG entries** — no gate, as before. "Does this deserve an entry" is
  judgment. The mechanical approximation (a PR touching a public framework
  `def` or `src/exports.toml` must touch CHANGELOG.md) would be bypassed
  routinely, and a bypassed gate reads as green. **Trigger**: a second release
  that ships a public method without an entry (#113 was the first).
- **The Nightly Canary's warnings** — deliberately allowed, counted, not
  failed. **Trigger**: if a stable bump ever lands with deprecations the
  canary had been reporting for weeks, the count was not being read and the
  canary should fail on it instead.

### What the new gates found on their first run

Not a rehearsal — the same shape as the compile-coverage target's first run
(61 latent errors) and the docstring gate's (a struct that never elaborated).

- **Every computed error message in the framework trailed heap garbage.**
  `examples/codegen/` was added to CI because listing "what CI compiles" for
  the doc-samples gate showed it compiled nowhere; running it printed
  `greet: expected string, got numberuffer`. The eight `throw_js_*_dynamic`
  helpers passed a Mojo `String`'s buffer to `napi_throw_*`, which reads a
  NUL-terminated `const char*`. Every generated type-mismatch error was
  affected, in every release. The tests asserted with `toContain`, which
  cannot see a suffix; they now assert whole messages. Note the gate did not
  *detect* this — it put a never-executed artifact in front of a person.
- **`spike/ffi_probe.mojo` had a dead `except` branch** that 1.1.0 had flagged
  and the bump notes had explicitly "left as-is". `--Werror` made leaving it
  a decision rather than a default.
- **The README quoted a function that existed in no file** —
  `process_config_pure`, in the struct-mapping example a reader copies first.
- **`CLAUDE.md`'s `_sym` block had drifted from `raw.mojo`** in line-wrapping
  only. Harmless in itself, and exactly the signal the gate exists to give
  before the drift is semantic.

### What was not done, and why

- **No new required check.** Every step lives inside the required `test` job.
- **No `-Werror` on the CLI's builds.** `napi-mojo build` and `run` compile a
  consumer's code; a framework must not fail a user's build on their own
  warnings. Their scaffolds and e2e runs still exercise `src/` under the
  flag through the other steps.
- **No gate on `docs/toolchain-migrations.md`'s code blocks.** They show the
  old spelling on purpose.
