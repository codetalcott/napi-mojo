# Handoff: close the per-method compile-coverage gap in napi-mojo

> **STATUS (2026-07-24): Tasks 1 and 2 are done on `release/v0.5.2`. Task 3 is
> deferred.** The prompt below is kept as the record of why the work was done
> and what was known going in; it is no longer an instruction to follow.
>
> - **Task 1 — done.** `tests/compile/framework_coverage.mojo` calls every
>   public method of every module under `src/napi/framework/`, each
>   env-only/Bindings overload separately, from an `@export`-rooted function
>   that never runs. Wired into `test.yml` after "Build examples", plus
>   `scripts/check-compile-coverage.mjs` as a name-level drift guard.
>   **The gate passed:** with `5161dfc` reverted the target fails with exactly
>   six errors at exactly the six sites, while `build.sh` and all 612 tests
>   stay green — the counterfactual the handoff asked for.
>   Its first run surfaced **61 further latent errors across 18 files**, all
>   present in published 0.5.1. Beyond the expected missing
>   `.as_unsafe_any_origin()` (52), there were three classes nobody predicted:
>   5 struct fields missing `@__allow_legacy_any_origin_fields` (struct
>   definitions elaborate lazily too), 2 `len(String)` calls that are now a hard
>   *error* rather than the documented warning, and 3 env-only overloads that
>   `convert.mojo` had always called but which were **never implemented** — the
>   env-only arm of the conversion traits had never worked in any release.
>   One correction to the analysis below: the lazy/eager split is by module
>   *role*, not by decorator. Main-module bodies are checked eagerly; only
>   imported-package bodies are lazy. `spike/elaboration_probe.mojo` pins this
>   down.
> - **Task 2 — done, and it was a rename, not an ABI change.** The NOTE quoted
>   below conflated the C++ symbol (three arguments) with the exported C
>   wrapper, which is **nullary** — it ignores its incoming registers and
>   supplies the arguments itself. Confirmed by disassembly and at runtime by
>   `spike/runtime_probe.mojo`. One-line symbol change; the FFI signature was
>   already correct. `asyncRuntimeInitOk()` + `tests/runtime.test.js` now make a
>   future rename fail a test on both CI OSes instead of silently degrading to
>   sequential — which also answers the "does this reproduce on Linux" question
>   permanently. `nm -gU` on that library shows nothing useful; use
>   `dyld_info -exports`.
> - **Task 3 — deferred, unchanged.** 219 `@__allow_legacy_any_origin_fields`
>   across 37 files (143 in `bindings.mojo` alone). Per CLAUDE.md this cannot be
>   a rename: it needs a concrete origin parameter on the handle structs *plus*
>   per-call-site `_ = x^` keep-alives, or the load-bearing lifetime extension
>   is severed and the SIGSEGVs return. Downstream analysis:
>   `~/projects/mojo-addon-examples/docs/origin-redesign-todo.md`.
>
> Not published, not pushed — still the maintainer's call.

Paste the section below into a fresh Claude Code session started in
`~/projects/mojo-node-api`. Everything in it was verified on 2026-07-24 against
Mojo `1.0.0b3.dev2026072306`.

---

## Prompt

You are working in `~/projects/mojo-node-api` (the `napi-mojo` package). Read
`CLAUDE.md` first and follow its conventions — especially the nightly-upgrade
runbook and rule 6, *"drive mechanical fixes from compiler diagnostics, not
global sed."*

### State you are inheriting

Branch `release/v0.5.2` exists locally, **unpushed and unpublished**, with two
commits on top of `main`:

- `5161dfc` — fixes origin widening at six C-FFI call sites in `args`,
  `js_arraybuffer`, `js_bigint`, `js_external`. `dev2026072306` removed the
  implicit `UnsafePointer -> MutAnyOrigin` conversion; these six sites were
  missed during the original migration. 11 lines, driven from compiler
  diagnostics per rule 6. Its commit message contains the full analysis below.
- `b651d97` — version bump to 0.5.2 across `package.json`, both `npm/*`
  platform packages, `package-lock.json`, and `pixi.toml`.

Verified at that point: **609 tests pass** (the documented `dev2026072306`
baseline), `pixi install --locked` clean with lock unchanged, tarball 87 files
/ 112.0 kB (unchanged from 0.5.1).

Do not publish anything. Publishing is the maintainer's call.

### The actual problem to solve

0.5.1 shipped four broken modules while both the build and the 609-test suite
were green. The reason is the thing worth fixing.

**Mojo elaborates `def` bodies lazily, per method.** A module can be imported,
compiled, packaged, and published with a broken method body, as long as nothing
in the compiled graph *calls that specific method*. Type errors inside it are
never surfaced.

Concretely: `JsBigInt.to_int64` is called by `src/addon/value_types.mojo`, so it
elaborated and was fine. `JsBigInt.to_uint64` is called nowhere, so its
identical bug shipped. Same shape in `js_arraybuffer` — `create_and_fill` is
exercised by `src/addon/binary_ops.mojo`; `create` is not, and `create` was
broken.

This is why the existing mitigation was not enough. `.github/workflows/test.yml`
already has a "Build examples" step, added precisely because `examples/` reaches
framework code `src/lib.mojo` does not. That raised coverage from *module* level
to *some-methods* level. But the unit of elaboration is the **method**, and the
addon plus examples together only call the subset they happen to expose.

Measured on 2026-07-24: **~34 of ~127 framework methods (~27%) are never called
anywhere CI compiles.** Reproduce and refine the count before acting on it — the
measurement below is a heuristic and will over- and under-match:

```bash
grep -rhoE "^\s+def [a-z_0-9]+" src/napi/framework/*.mojo \
  | sed 's/.*def //' | sort -u \
  | grep -vE "^(__init__|__del__|__copyinit__|__moveinit__|write_to)$" > /tmp/defined.txt
grep -rhoE "\.[a-z_0-9]+\(|\b[A-Z][A-Za-z]*\.[a-z_0-9]+\(" \
  src/lib.mojo src/addon/ src/generated/ examples/ --include="*.mojo" \
  | sed 's/.*\.//; s/(//' | sort -u > /tmp/called.txt
comm -23 /tmp/defined.txt /tmp/called.txt
```

The uncovered set is not obscure. It includes the entire threadsafe-function
surface (`call_blocking`, `call_nonblocking`, `acquire`, `release`, `abort`),
plus `get_four`, `create_typed`, `create_no_release`, `data_ptr_float32/int32/uint8`,
`get_property`, `is_date`, and the `create_bigint64`/`create_biguint64` pair.
Any of these may be broken in published 0.5.1 right now. Nobody would know.

### Task 1 (primary) — force elaboration of every public framework method

Add a compile-only target that calls every public method of every module under
`src/napi/framework/`, and wire it into `.github/workflows/test.yml` next to the
existing "Build examples" step. It never has to run — compiling it is the whole
point.

Design notes:

- **Per-method, not per-module.** A target that touches one function per module
  would not have caught `to_uint64`, because `js_bigint` was already covered.
- Cover **each overload** where a method has both an `env`-only and a
  `Bindings` form. Both `JsArrayBuffer.create` overloads were broken; only
  checking one would have left the other latent.
- It must compile without a live `napi_env`. Reaching for real N-API handles
  will not work at build time. Prefer a function that is compiled but never
  called, with values obtained from parameters, so no runtime N-API call
  happens. Confirm the approach forces elaboration before mass-writing it —
  `spike/ffi_probe.mojo` is the repo's established place for validating an idiom
  cheaply, and CLAUDE.md runbook step 4 says to use it before any large edit.
- Verify it actually works by reverting `5161dfc` locally, confirming the new
  target **fails** on all six sites, then restoring. A coverage guard that does
  not fail on the known bug is worthless. This is the single most important
  step.

### Task 2 — `parallelize()` is silently dead

`src/napi/framework/runtime.mojo` carries a `NOTE (dev2026072306)`:
`KGEN_CompilerRT_AsyncRT_GetOrCreateRuntime` no longer exists. The library now
exports `KGEN_CompilerRT_AsyncRT_GetOrCreateCPUDevice`, whose C++ counterpart is
`getOrCreateCPUDevice(CPUDeviceSource, const CPUDeviceOptions&, bool)` — it
takes arguments, unlike the old zero-arg entry point.

So `init_async_runtime()` always fails, and `parallelize_safe()` falls back to
running **sequentially**. Results stay correct; all thread parallelism is gone.

This is a real regression for every consumer. Downstream in
`~/projects/mojo-addon-examples`, whose entire premise is SIMD + `parallelize()`
speedups, the parallel benchmark numbers in the READMEs no longer measure
threading. Resolve the real signature and wire the fast path back up, or
establish that it cannot be done safely and say so loudly in the README. Do not
guess at the ABI — the existing NOTE explicitly declines to, and calling it
blind corrupts the call.

Worth checking whether this reproduces on Linux, since that is where the
downstream GPU work actually deploys. It may be a Darwin-only symbol change.

### Task 3 — retire the AnyOrigin escape hatch

`dev2026072306` made it an error for a struct field to expose `AnyOrigin`.
`ModuleBuilder` in `src/napi/framework/register.mojo` carries
`@__allow_legacy_any_origin_fields`, which restores the old unchecked behavior.

Downstream did the same thing to unblock, and wrote up the redesign at
`~/projects/mojo-addon-examples/docs/origin-redesign-todo.md`. Read it — its
step 3 concludes the redesign has to *start here*, because `NapiRef`,
`NapiDeferred` and `NapiAsyncWork` are all aliases for
`OpaquePointer[MutAnyOrigin]` in this repo.

Lowest priority of the three. It is latent-correctness work, not a live break.

### Conventions

- Verify with `pixi run npm test`. Baseline is **609 passing**; anything less is
  a regression you caused.
- For any GC-time or intermittent crash, use the Guard Malloc recipe in
  `CLAUDE.md` rather than adding retries. CI deliberately has no retry wrapper,
  and the comment above the test step explains why — do not re-add one.
- Releases: branch `release/vX.Y.Z`, bump via `node scripts/sync-versions.mjs
  <version>`, then bump `pixi.toml` **by hand** — the script does not know about
  it. `publish.yml` fires on `release: [published]` and resolves its workflow
  file *from the tag's commit*, which is how v0.5.0 never reached npm. Tag from
  merged `main`.
- Do not publish, and do not push without being asked.
