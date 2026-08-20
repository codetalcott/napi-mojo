# Changelog

All notable changes to napi-mojo. The project is in alpha; minor versions may
break the source API that downstream addons compile against.

## 0.11.0 — 2026-08-20

**napi-mojo is bidirectional.** Alongside addons (JS calls Mojo) it now hosts
Mojo *programs*: `napi-mojo run main.mojo` compiles your entry, generates the
registration wrapper and a CJS bootstrap, and hands Mojo the Node ecosystem —
`require`, `fs`, `zlib`, `fetch`, npm. Node owns `main()`; Mojo is the program.

The framework could already call JavaScript — `raw_call_function`,
`raw_new_instance`, `js_run_script`, `JsRef` and `ThreadsafeFunction` have all
been here for releases. What was missing was ergonomics, an entry point, and
anyone saying so. This release is mostly surfacing, not new machinery.

### Host mode

- **`napi-mojo run <entry.mojo>`** and **`napi-mojo init --host`**. The wrapper
  is generated next to your entry, because Mojo resolves a plain-module import
  relative to the main module's directory; it is removed after the run unless
  `--keep`.
- **`NodeHost`** (`napi.framework.js_host`) — `from_context`, `require`,
  `global_object`, `argv`, `console_log`. `require` is module-scoped and *not*
  on `globalThis`, so the bootstrap hands it in on `ctx`, built with
  `module.createRequire` rooted at the entry's directory.
- **Runs are cached** on a hash of your tree, the framework tree, the include
  path and the compiler command — a warm run is ~0.07s against ~1.8s cold.
  `--rebuild` forces a recompile.

### Call ergonomics

- **`JsFunction.call_n` / `call_with`** — call with a runtime-length argument
  list, with or without an explicit receiver. `call0/1/2` remain as the
  allocation-free fast paths.
- **`JsObject.call_method`** — `obj[name](...args)` with `this` bound. `call1`
  passes `undefined` as the receiver, which silently breaks any callee reading
  `this`; this is the right tool for a method call.
- **`with_handle_scope`** — a Mojo-driven loop calling JS pins every napi_value
  until the enclosing scope closes. This encapsulates the open/close-on-both-
  paths discipline and preserves the body's error.

### Correctness and measurement

- **Continuation passing is tested.** Mojo has no `await`, and the documented
  answer — hand JS a Mojo callback and return — had shipped with zero coverage.
  It works; it had just never been checked. A continuation now provably fires
  on a later tick, is not synchronous, stays independent across several in
  flight, and can reach `require` from that later tick through a `napi_ref`.
- **The Mojo→JS direction is benchmarked** (`callN`, `callMethod`,
  `scopedCall`) and under the same ceilings gate as the forward direction. The
  numbers corrected the guidance: the *call* is not the expensive part
  (~435 ns round trip vs ~375 ns forward-only) — **argument marshalling is**,
  at roughly **~100 ns per value crossing**. Cross with few coarse values.
- **Fixed: an entry basename becomes a top-level Mojo module name**, so
  `pipeline.mojo` was shadowed by MAX's own `pipeline` package and failed with
  *"does not contain 'mojo_main'"*. `run` now exposes the entry through a
  `_napi_mojo_src_` alias and rewrites it back out of compiler diagnostics, so
  errors still name your file.
- **New gate: `scripts/check-exports-doc.mjs`.** Every export must appear in
  `docs/EXPORTS.md`, and the "N exported functions" counts in README and
  CLAUDE.md must match reality. CLAUDE.md warned that nothing updates numbers
  embedded in prose; the count went stale within a week anyway. Now something
  checks it.

### Positioning

napi-mojo and the sibling [mojo-http](https://github.com/codetalcott/mojo-http)
are complements, not competitors: **Mojo owns `main()` → mojo-http; Node owns
`main()` → `napi-mojo run`.** No build-time dependency in either direction.
Embedding libnode was considered and rejected — N-API is a guest API with no
public way to create an `env`, Node's embedder API is C++ where Mojo's FFI is
C-ABI only, and there are no official cross-platform `libnode` prebuilts.
`examples/host/pipeline.mojo` is the demo: Mojo computes statistics over
200,000 samples, Node does the JSON, gzip and file write, and the samples never
cross the boundary.

## 0.10.0 — 2026-08-20

Three gates, one code-generator feature, and the removal of
`@__allow_legacy_any_origin_fields` from the entire tree — 243 fields to zero.
The through-line is the same one 0.9.0 kept running into: this codebase's
characteristic failure is something that compiles, passes, and was never
actually executed.

**Source-API note for downstream addons.** `NapiEnv`, `NapiValue` and the eight
other handle aliases are now `OpaquePointer[MutUntrackedOrigin]` rather than
`MutAnyOrigin`. Code that only passes handles around — the overwhelming
majority — is unaffected, because every framework signature that takes a handle
takes the alias. Code that spells `OpaquePointer[MutAnyOrigin]` literally where
a handle is expected will need `.as_unsafe_any_origin()` at the boundary, or
better, the alias. `ModuleBuilder`/`ClassBuilder` constructors deliberately kept
their `data: OpaquePointer[MutAnyOrigin]` parameter so existing
`register_module` boilerplate compiles untouched.

### Added

- **`@__allow_legacy_any_origin_fields` is gone — 243 fields to zero.** Upstream
  documents the decorator as an unstable escape hatch slated for removal, and
  `UnsafeAnyOrigin` itself as slated for deprecation, so this was never
  optional — only unscheduled. The alternative was doing it against a broken
  build on a deadline, in the one area of this codebase that has already
  produced SIGSEGVs.

  What made it tractable was finding that the warning in `CLAUDE.md` about a
  naive `MutAnyOrigin` → `MutUntrackedOrigin` rename is about a **different
  population** than the decorator's. The 243 decorated *fields* all point at a
  V8-owned handle, a static code address, or an `unsafe_alloc` block — checkable
  rather than a judgement call, since
  `grep -rn "self\.[a-z_]* = Pointer(to=" src/ examples/` is empty, so no field
  anywhere holds a pointer to a Mojo local. The 159 dangerous sites are inline
  `Pointer(to=<local>)…as_unsafe_any_origin()` *arguments*, where the widening
  is load-bearing: it keeps a register-passable local's spill slot alive across
  the FFI call. The two are disjoint, so the fields could move without touching
  the arguments at all.

  The recipe, now recorded in `docs/plan-origin-migration.md`: storage-type the
  **field**; leave every parameter and return type alone; narrow at the write
  into the field and widen at the read out of it; keep the
  `comptime *Fn = def(...) thin abi("C")` types at `MutAnyOrigin`. That last
  clause is the rule that must not be broken — "simplifying" it is exactly the
  global rename that severs the load-bearing population, it looks tidier, and
  nothing in the type system stops you.

  It is proven rather than asserted. `spike/ffi_probe.mojo` carries the recipe
  decorator-free and CI builds *and runs* it on both platforms: `originProbe`
  creates a JS string through a local output slot, reads it back through a
  second, and byte-compares — four payloads of different lengths, so a slot
  clobbered by its neighbour fails on content where a null check would pass on
  garbage. A compile-time assert pins that the origin parameter does not change
  the machine representation and that `NapiPropertyDescriptor` is still 64
  bytes; if it ever did, every `napi_define_properties` call would corrupt
  silently.

  Landed in five steps, each independently green: the spike and plan, then
  `NapiBindings`' 143 slots, then `NapiPropertyDescriptor` and the registry
  internals, then a verified no-op commit pinning `raw.mojo`'s 143 FFI type
  expressions to a literal `MutAnyOrigin` (they were spelled with the aliases,
  which would otherwise have moved underneath them), and finally the alias flip
  itself. The generator no longer emits the decorator either, so
  `npm run generate:addon && git diff --exit-code src/generated/` holds.

- **Docstring coverage ratchet.** `scripts/check-docstring-coverage.mjs` runs
  `mojo doc --diagnose-missing-doc-strings` over the consumer-facing modules and
  compares per-file counts against `scripts/docstring-floor.json` — 351
  undocumented public symbols across 38 modules at adoption. Per-file rather
  than one total, because a single number lets documenting one module pay for
  regressing another. The ratchet fails in both directions: rising is a
  regression, and falling without updating the floor would let the coverage
  just added be undone silently later.

  Asking the compiler rather than a regex matters for more than tidiness —
  `mojo doc` elaborates every declaration in the file it opens, so the gate is
  a third view onto lazily-checked code after `framework_coverage.mojo` (method
  bodies) and `tests/codegen/` (generator templates). A doc failure there is a
  finding, not gate noise. Three framework files that `mojo doc` cannot open at
  all — the main-module `__moveinit__` compiler bug — are listed in
  `KNOWN_UNDOCUMENTABLE` with their reason, and the script fails if one ever
  starts working, so the skip cannot outlive the bug.

  `"""` is now the documented convention for public framework symbols, with a
  worked example in `CONTRIBUTING.md`. No sweep of the existing `##` blocks.

- **Per-call overhead gate.** A non-required `benchmark` job compares median
  ns/call against per-platform ceilings in `scripts/benchmark-ceilings.json`.
  Cached `NapiBindings` exists to keep a `dlopen(NULL)` + `dlsym` off the hot
  path and nothing had ever checked it stayed off; a reintroduced per-call
  lookup costs 10-100x and would ship green.

  Calibrated for that and honest about the rest: it will not see a 10%
  regression on a shared runner and does not claim to. `macos-latest` measures
  ~2.7x the per-call cost of `ubuntu-latest`, hence per-platform ceilings and a
  hard error on an unrecorded platform. Every run prints observed/ceiling as a
  percentage and emits a CI warning above 75%.

- **`mojo_fn` on class setters and static methods**, the last two generator
  rejections. A setter takes the tagged unwrap plus a declared
  `type = "<token>"` for its value and mutates through `mut`; a static takes no
  state at all and works on a class with no `state` declared.

- **Runtime coverage for native class state.** `state = "<struct>"` shipped in
  0.9.0 with codegen coverage only — the kitchen sink compiles a state-backed
  class but never loads it, and `src/exports.toml` declared none — so
  wrap/unwrap, the type tag, `mut` mutation across calls and the finalizer had
  never run. The `Tally` class and `tests/class_state.test.js` drive all of it,
  including borrowing a method, getter or setter onto a foreign wrapped
  instance, which must be a `TypeError` rather than a reinterpret.

### Fixed

- `raw_create_promise` passed its `deferred` argument as if it were a handle.
  It is an output slot — a `napi_deferred*` the callee writes — and its caller
  hands it `Pointer(to=<local>)…as_unsafe_any_origin()`. Retyping it surfaced
  the mistake at compile time; under the old aliases the same confusion would
  have compiled silently, which is the general argument for the flip.
- `NapiNodeVersion` could not compile: `release` was missing
  `@__allow_legacy_any_origin_fields`, latent since dev2026062206 because
  nothing constructs the struct and struct definitions elaborate lazily. Found
  by the docstring gate's first run.
- `toml-dts.js` ignored `?` throughout the class block, so a class method or
  getter declared `"number?"` was typed `number` while the generated callback
  has a real `JsNull` branch. Class members now use the same nullable-aware
  mappers as top-level functions, for arguments and returns alike. A
  setter-only property with a declared type emits that type instead of `any`.
- A generated setter did not type-check its value: the check lives in
  `emitArgPreamble`, which the setter path does not use, so a wrong type fell
  through to the `except:` block as "<prop> setter failed" rather than
  "expected number, got string".

### Changed

- Two test assertions that rotted rather than guarded now derive from the
  source: `typescript.test.js` builds its class skip-list from the `.d.ts`'s
  own `export class` lines (and checks every declared class is really on the
  addon, so the derived list cannot hide a missing export), and
  `toml_lite.test.js` derives the expected `extra_imports` count instead of
  hardcoding it.
- `scripts/benchmark.mjs` gains `--json` and `$NAPI_MOJO_BENCH_BATCHES`; the
  human-readable table is unchanged.
- `CLAUDE.md` referred to `@qkstat/rag` and `packages/rag`, which do not
  exist. The downstream packages are `@qkstat/retrieve` (which holds the GPU
  work) and `@qkstat/embed`.

## 0.9.0 — 2026-08-19

The code generator stops being a convenience for simple functions and becomes
the way an addon is written: zero-copy binary data, arrays of structs, classes
with native Mojo state, nullable arguments, and async without the old caps.
Plus the tutorial that was missing when the CLI shipped, and the allocator
evidence the async string result was owed.

### Changed

- The argument-fetch and type-check chain in `generate-addon.mjs` lived in five
  copies (sync, async, class constructor, instance method, static method) that
  had to be edited in lockstep for any new token or arity — and had already
  drifted. They now share one `emitArgPreamble`. Verified behaviour-preserving:
  `src/generated/`, the kitchen-sink output (every emitter branch) and the
  tutorial addon all regenerate **byte-identical** to the pre-refactor output.

### Added

- **A concurrent-async stress suite, run under a checking allocator in CI.**
  `tests/async_stress.test.js` puts many string-returning async calls in
  flight at once — mixed sizes, interleaved with numeric async, with forced GC
  between rounds — and a new non-required `async-stress` job runs it under a
  checking allocator: Guard Malloc on macOS (which does engage on GitHub
  runners — the job probes for the `GuardMalloc[node-…]` banner and warns if
  that ever stops being true, since a stripped `DYLD_INSERT_LIBRARIES` is not
  an error and would check nothing while going green), always the libmalloc
  knobs `MallocScribble`/`MallocGuardEdges`/`MallocErrorAbort` which the
  system allocator honours directly, and `MALLOC_PERTURB_`/`MALLOC_CHECK_` on
  Linux. This is the evidence the async `string` result was missing: the
  reasoning for why a Mojo String may cross to a worker thread was sound, but
  nothing had run the allocator in checking mode against it. jest is invoked
  directly rather than through npx, which drops `DYLD_INSERT_LIBRARIES`.
- `asyncLabel(s)` — a string-returning async export on the demo addon, so the
  new capability has a runtime target where the jest suite already points.
- `npm run generate:docs` says what it documents. It runs typedoc over
  `build/index.d.ts` — the **demo addon's** surface — while being named and
  titled as if it covered the framework. Output moves to
  `docs/api-demo-addon/` with a matching title. A reference for the framework
  itself is scoped in `docs/plan-api-reference.md`, whose finding is that 87%
  of the 397 public framework defs carry no doc comment at all, so the
  bottleneck is content rather than tooling.
- **Async generation: no argument cap, and `string` results.** The four-argument
  limit came from the entry callback's arity chain, not from anything about
  threads, and disappeared when that chain was unified — async now uses the
  same heap-argv path as sync. `returns = "string"` also works: the data
  struct holds a Mojo `String`, moved rather than copied in its move
  constructor. The rule that this struct may hold "only simple types" was
  folklore; the constraints that actually bind on the worker thread are no
  N-API calls and no dlopen/dlsym, and CLAUDE.md now says so. Concurrency is
  covered by the stress suite above, added in this same release.
- **Nullable arguments are real now.** `args = ["string?"]` hands the Mojo
  function an `Optional[String]` — `None` for JS null or undefined, a
  converted value otherwise — and the typed check sits *inside* the null test,
  so a wrong type still raises the descriptive TypeError instead of falling
  into the generic catch. Works for number, string, boolean, the integer
  tokens and declared structs. This replaces the rejection added earlier in
  this cycle, which existed because the `.d.ts` advertised `| null` while the
  extract converted unconditionally. `number[]`, `float64array` and `buffer`
  are still refused, now with the reason: an absent array is an empty one, and
  an absent zero-copy view has no buffer.
- **Classes can keep native Mojo state.** `state = "<struct>"` plus
  `constructor_mojo_fn` makes the generator heap-allocate a declared struct,
  wrap it onto the instance, and hand it to every `mojo_fn` member — a
  mutating method takes it `mut`, a getter borrows it — with the GC finalizer
  emitted alongside. Previously a generated class had nowhere to put Mojo data
  and had to stash values as JS properties. Instances are stamped with a
  128-bit type tag derived (deterministically, so regeneration is byte-stable)
  from the class name, and every member verifies it, so borrowing a method onto
  a foreign object raises a TypeError instead of reinterpreting memory.
  `mojo_fn` on setters and static methods is rejected rather than ignored.
- **Generated structs implement `ToJsValue`/`FromJsValue`, and `<struct>[]`
  works everywhere a type token is accepted.** Declaring `[structs.config]` has
  always given you `config` as a token; it now also gives `config[]`, in
  argument and return position, mapping to `List[ConfigData]` in Mojo and
  `Config[]` in TypeScript. The array form is carried entirely by the trait
  conformance plus the existing parametric `to_js_array`/`from_js_array` — no
  per-struct array emitter.
- **Zero-copy binary tokens in the code generator.** `float64array` as an
  argument hands the Mojo function a `Span[Float64]` aliasing the JS
  `Float64Array`'s own backing store; as a return type the function hands back
  a `MojoFloat64Array` whose allocation JavaScript adopts. No copy in either
  direction — the story Mojo exists for, previously reachable only from a
  hand-written callback. `buffer` gives a `Span[Byte]` view over a Node
  `Buffer` and is argument-only: there is no Mojo-owned `Buffer` type to hand
  back without copying, so `returns = "buffer"` is rejected with that reason
  rather than silently copying. TypeScript emits `Float64Array` and `Buffer`.
  The input Span aliases engine-owned memory and is valid only for the
  duration of the call.
- **[docs/TUTORIAL.md](docs/TUTORIAL.md)** — the CLI's missing half. Walks from
  `napi-mojo init` to a published-shaped addon: a pure function, a nullable
  return, a struct in both directions, async work on a worker thread, and a
  class. Its finished addon is a real fixture, `examples/tutorial/`, and a new
  CI step generates, compiles and calls every one of its exports on both
  platforms — so the doc's snippets cannot rot the way prose examples do (this
  repo has shipped that failure three times).

## 0.8.1 — 2026-08-19

### Fixed — code generator

Three emitter bugs, each reachable only from a consumer's own `exports.toml`
(`src/exports.toml` contains none of these shapes, and the kitchen-sink gate
covers template branches, not malformed input). `napi-mojo init` shipping in
0.8.0 is what made user-authored TOML the common case.

- A struct declared with no fields emitted `def __init__(out self, ):` plus a
  `__moveinit__` and copy ctor with empty bodies — three syntax errors that
  surfaced at `mojo build`, far from the missing `[structs.<name>.fields]`
  table that caused them. Now rejected with that cause named.
- A struct field named `obj` redeclared `from_js`'s own `var obj` and made
  every later field read its property off a `Float64`; `val`, `b` and `env`
  shadowed the converter's parameters the same way. Field locals are now
  `_f_`-prefixed, so no field name can collide.
- A converting token in argument position could carry `?` (`number?`,
  `string?`, a struct): the `.d.ts` advertised `| null` while the generated
  extract called `Js*.from_napi_value` on the value unconditionally, so the
  advertised `null` raised at runtime. Now rejected, with the supported
  spellings named. `?` is unchanged on return types and on pass-through
  argument tokens (`any?`/`object?`/`array?`), where `| null` is the truth.

`tests/codegen_guards.test.js` covers the rejection branches — the half
`tests/codegen/` cannot, since that target has to compile — and the kitchen
sink now declares the four colliding field names and both remaining
pass-through nullable tokens.

## 0.8.0 — 2026-08-18

### BREAKING: the env-only overload surface is deleted (#42)

Every function that duplicated a cached-`Bindings` twin with a per-call
`dlopen(NULL)`+`dlsym` variant is gone — 125 of 130 env-only `raw_*` wrappers
and ~170 framework halves (~4,800 lines). Migration for addon code:

- Callbacks fetch cached bindings first — `var b = CbArgs.get_bindings(env, info)`
  — and pass `b` as the first argument to every framework call:
  `JsString.create(env, s)` → `JsString.create(b, env, s)`.
- `ModuleBuilder(env, exports)` (2-arg) is gone: allocate `NapiBindings`, run
  `init_bindings`, and pass the pointer as the third argument. `ModuleBuilder`/
  `ClassBuilder` registration calls are otherwise unchanged (they derive cached
  bindings internally from `data`, which MUST be the bindings pointer).
- `ToJsValue`/`FromJsValue` trait methods are now Bindings-first
  (`to_js(b, env)` / `from_js(b, env, val)`), which also removes a per-element
  `dlsym` from `to_js_array[T]`/`from_js_array[T]`.
- Still env-only, deliberately: `CbArgs`'s bootstrap methods (built on
  `raw_get_cb_info`) and `error.mojo`'s `throw_js_*` helpers (the
  `except:`-block fallback surface).
- `examples/hello-addon.mojo` shows the full minimal pattern.

### BREAKING: class wrap/unwrap is type-tagged (#39)

`wrap_native(b, env, this, data_ptr, fin_ptr, tag)` stamps a 128-bit
`NapiTypeTag`; the tag-taking overloads of `unwrap_native[T]` /
`unwrap_native_from_this[T]` verify it and throw a JS `TypeError` on mismatch —
so borrowing a method onto a foreign wrapped instance is an error instead of
memory corruption. The untagged unwraps remain for explicit accept-set checks
(inheritance). Untagged `napi_wrap` via `raw_wrap` still works but is not the
recommended path.

### Fixed

- `JsString.from_napi_value` silently truncated multi-byte strings whose
  256-byte fast-path read ended on a codepoint boundary (#38).
- `JsFunction.create_named` passed `NAPI_AUTO_LENGTH` for a heap `String`,
  letting N-API `strlen` an unterminated buffer (#38).
- `JsObject.set_named_property`/`get_named_property` fed non-NUL-terminated
  heap Strings to the C-string N-API; they now use length-delimited JS-string
  keys (#38).
- A bindings-init failure made `require()` return `{}` silently; it now throws
  "failed to resolve N-API symbols (Node.js >= 22.12 required)" (#38).
- `CbArgs.get_bindings*` verify a magic sentinel before trusting callback data;
  the ClassRegistry slot is null-checked; `get_argv` returns the actual
  argument count (#40).
- The generator's ≥5-arg template emitted Mojo that could not compile; caught
  and fixed alongside the new kitchen-sink compile gate (#40, #41).
- `asyncProgress`'s worker thread no longer takes the loader lock per queued
  item, and its TSFN payload is freed when queueing fails (#41).

### Added

- **`napi-mojo` CLI** (#44) — the consumer toolchain, previously a set of
  copy-the-repo-layout instructions:

  ```bash
  npx napi-mojo init my-addon        # scaffold exports.toml + lib.mojo + package.json
  npx napi-mojo generate --dts       # exports.toml -> generated Mojo + index.d.ts
  npx napi-mojo build --bundle       # compile, optionally with the Mojo runtime alongside
  ```

  `build` resolves the compiler as `--mojo` > `$NAPI_MOJO_MOJO` > `pixi run mojo`
  (when a `pixi.toml` is found above the entry) > `mojo`, and defaults its
  include path to this package's `src/`, so an installed addon needs no
  knowledge of where the framework lives. CI runs the whole path end to end —
  scaffold, generate, compile, call from Node — on macOS and Linux.
- `bindings_from_context()` — magic-checked recovery of cached bindings from
  TSFN contexts, finalize hints, and cleanup-hook args (#41).
- `type_tag_object` / `check_object_type_tag` / `wrap_native` framework
  wrappers (#39).
- `addObservableCleanupHook()` — a cleanup hook with an observable effect, so
  a child process can assert hooks actually *run* at env teardown rather than
  only that registration returned true (#45).
- `tests/codegen/` kitchen-sink compile target: every generator template
  branch is generated and compiled in CI (#41).
- `tests/worker_threads.test.js` — the framework under a second `napi_env`:
  per-env instance data, classes and type tags, TSFN callbacks, and async work
  in a Worker while the main env also works (#45).
- Node 24 CI coverage on both platforms, as a separate non-required job so
  adding it could not rename — and thereby strand — the required checks (#45).

### Removed

- `scripts/benchmark-compare.mjs` and `benchmarks/dlsym_overhead.js` — both
  measured the deleted env-only path.

## 0.7.0 — 2026-08-12

Mojo 1.0.0 stable toolchain adoption (from the 26.6 nightly channel). See the
repo history for earlier releases.
