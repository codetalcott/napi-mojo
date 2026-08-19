# Changelog

All notable changes to napi-mojo. The project is in alpha; minor versions may
break the source API that downstream addons compile against.

## Unreleased

### Changed

- The argument-fetch and type-check chain in `generate-addon.mjs` lived in five
  copies (sync, async, class constructor, instance method, static method) that
  had to be edited in lockstep for any new token or arity — and had already
  drifted. They now share one `emitArgPreamble`. Verified behaviour-preserving:
  `src/generated/`, the kitchen-sink output (every emitter branch) and the
  tutorial addon all regenerate **byte-identical** to the pre-refactor output.

### Added

- **Async generation: no argument cap, and `string` results.** The four-argument
  limit came from the entry callback's arity chain, not from anything about
  threads, and disappeared when that chain was unified — async now uses the
  same heap-argv path as sync. `returns = "string"` also works: the data
  struct holds a Mojo `String`, moved rather than copied in its move
  constructor. The rule that this struct may hold "only simple types" was
  folklore; the constraints that actually bind on the worker thread are no
  N-API calls and no dlopen/dlsym, and CLAUDE.md now says so. **Not
  established:** behaviour under heavy concurrency — none of this is
  stress- or race-tested.
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
