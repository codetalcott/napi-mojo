# Changelog

All notable changes to napi-mojo. The project is in alpha; minor versions may
break the source API that downstream addons compile against.

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

- `bindings_from_context()` — magic-checked recovery of cached bindings from
  TSFN contexts, finalize hints, and cleanup-hook args (#41).
- `type_tag_object` / `check_object_type_tag` / `wrap_native` framework
  wrappers (#39).
- `tests/codegen/` kitchen-sink compile target: every generator template
  branch is generated and compiled in CI (#41).

### Removed

- `scripts/benchmark-compare.mjs` and `benchmarks/dlsym_overhead.js` — both
  measured the deleted env-only path.

## 0.7.0 — 2026-08-12

Mojo 1.0.0 stable toolchain adoption (from the 26.6 nightly channel). See the
repo history for earlier releases.
