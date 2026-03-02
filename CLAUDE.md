# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**napi-mojo** — the Mojo equivalent of Rust's `napi-rs`. A framework for building Node.js native addons in Mojo via the Node-API (N-API) C interface. Currently in early development (Phase 1–2 implemented, not yet compiled/tested).

## Commands

```bash
npm install                          # install Jest
npm run build                        # compile src/lib.mojo → build/index.node
npm test                             # run all Jest tests
npx jest tests/basic.test.js         # run a single test file

# Spike (run before anything else if starting fresh):
mojo build --emit shared-lib spike/ffi_probe.mojo -o build/probe.dylib
mv build/probe.dylib build/probe.node
nm -gU build/probe.dylib | grep napi_register_module_v1   # verify symbol export
node -e "require('./build/probe.node')"                    # verify Node.js loads it
node -e "console.log(require('./build/probe.node').hello())"  # full end-to-end check
```

## Architecture

### The core FFI problem

N-API functions (`napi_create_string_utf8`, `napi_define_properties`, etc.) are **not in libc** — they live in the Node.js host process. When Node.js loads our `.node` file via `dlopen`, N-API symbols are already in the process address space. We access them via `OwnedDLHandle("")` (equivalent to `dlopen(NULL, ...)`), which opens the host process symbol table at runtime.

### How a `.node` addon works

1. `mojo build --emit shared-lib` produces a `.dylib` renamed to `.node`
2. Node.js calls `dlopen` on the `.node` file, then `dlsym("napi_register_module_v1")`
3. Our `@export("napi_register_module_v1", ABI="C")` function is called with `(env, exports)`
4. We call `napi_define_properties` to attach Mojo functions to the `exports` object
5. Each exported Mojo function acts as a `napi_callback`: `fn(NapiEnv, NapiValue) -> NapiValue`

### Current code structure

- **`src/lib.mojo`** — monolithic Phase 1–2 implementation: type aliases, `NapiPropertyDescriptor`, raw N-API bindings via `OwnedDLHandle`, `hello_fn`, `create_object_fn`, and the `register_module` entry point. Intentionally not split into modules yet (Phase 3 refactor will do that).
- **`spike/ffi_probe.mojo`** — throwaway experiment to validate the FFI mechanism before any TDD work. Must be run first on a new machine or after major Mojo version changes.
- **`tests/`** — Jest tests only. TDD is outside-in: JS tests are written first (RED), then Mojo is written to pass them (GREEN), then refactored.

### Planned module split (Phase 3)

```
src/napi/types.mojo    # NapiEnv, NapiValue, NapiStatus, NapiPropertyDescriptor
src/napi/raw.mojo      # OwnedDLHandle symbol resolution (only file allowed to use it)
src/napi/error.mojo    # NapiError, check_status()
src/napi/module.mojo   # napi_define_properties wrapper
src/napi/framework/    # JsString, JsObject high-level wrappers (Phase 4)
```

## Critical Mojo FFI rules

**Imports** (2026 nightly): `from ffi import OwnedDLHandle` — the `sys.ffi` path is deprecated.

**Build flag**: `mojo build --emit shared-lib` — not `-shared`.

**String lifetimes**: Always bind strings to a named `var` before calling `.unsafe_ptr()`. Mojo's ASAP (eager) destruction frees inline temporaries before N-API reads the pointer:
```mojo
var s = String("hello")          # correct — lives until end of scope
fn_ptr(s.unsafe_ptr(), len(s))
```

**Function pointers**: The Mojo syntax for obtaining a raw function pointer (needed for `napi_callback`) is unconfirmed — `spike/ffi_probe.mojo` Step 4 must validate it. Candidates: `__mlir_op.\`pop.fn_ptr\`[my_fn]()` or `UnsafePointer(my_fn)`. Update CONTRIBUTING.md once confirmed.

**`NapiPropertyDescriptor` struct layout**: Must exactly match the C definition (8 fields in order: `utf8name`, `name`, `method`, `getter`, `setter`, `value`, `attributes`, `data`). Wrong layout causes silent corruption in `napi_define_properties`.

**Status checking**: Every N-API call returns `NapiStatus`. Currently unchecked in Phase 1–2; `check_status()` wrapper is added in Phase 3.

## Development workflow

Follow the RED → GREEN → REFACTOR TDD cycle (see METHODOLOGY.md). Every feature starts with a failing Jest test. The spike (`spike/ffi_probe.mojo`) is the exception — it is validated experimentally, not by tests.
