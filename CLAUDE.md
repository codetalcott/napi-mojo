# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**napi-mojo** — the Mojo equivalent of Rust's `napi-rs`. A framework for building Node.js native addons in Mojo via the Node-API (N-API) C interface. Phase 5d complete — primitive type I/O (string, number, boolean), argument reading, error propagation, and object construction are all working.

## Commands

```bash
pixi run bash build.sh               # compile src/lib.mojo → build/index.node
npm test                              # run all Jest tests (17 tests)
npx jest tests/basic.test.js          # run a single test file

# Spike (run before anything else if starting fresh):
pixi run mojo build --emit shared-lib spike/ffi_probe.mojo -o build/probe.dylib
mv build/probe.dylib build/probe.node
node -e "console.log(require('./build/probe.node').hello())"
```

## Architecture

### The core FFI problem

N-API functions (`napi_create_string_utf8`, `napi_define_properties`, etc.) are **not in libc** — they live in the Node.js host process. When Node.js loads our `.node` file via `dlopen`, N-API symbols are already in the process address space. We access them via `OwnedDLHandle()` (equivalent to `dlopen(NULL, ...)`), which opens the host process symbol table at runtime.

### How a `.node` addon works

1. `mojo build --emit shared-lib` produces a `.dylib` renamed to `.node`
2. Node.js calls `dlopen` on the `.node` file, then `dlsym("napi_register_module_v1")`
3. Our `@export("napi_register_module_v1", ABI="C")` function is called with `(env, exports)`
4. We call `napi_define_properties` to attach Mojo functions to the `exports` object
5. Each exported Mojo function acts as a `napi_callback`: `fn(NapiEnv, NapiValue) -> NapiValue`

### Module structure

```
src/lib.mojo                          # entry point: callbacks + register_module
src/napi/types.mojo                   # NapiEnv, NapiValue, NapiStatus, NapiPropertyDescriptor
src/napi/raw.mojo                     # OwnedDLHandle symbol resolution (sole user of OwnedDLHandle)
src/napi/error.mojo                   # check_status(), throw_js_error()
src/napi/module.mojo                  # define_property(), register_method()
src/napi/framework/js_string.mojo     # JsString.create(), from_napi_value(), read_arg_0()
src/napi/framework/js_object.mojo     # JsObject.create(), set_named_property()
src/napi/framework/js_number.mojo     # JsNumber.create(), from_napi_value()
src/napi/framework/js_boolean.mojo    # JsBoolean.create(), from_napi_value()
src/napi/framework/args.mojo          # CbArgs.get_one(), get_two()
spike/ffi_probe.mojo                  # throwaway FFI validation (run on new machine / Mojo upgrade)
tests/                                # Jest tests — TDD outside-in
```

### Exported addon functions

| JS name | Mojo fn | Description |
|---------|---------|-------------|
| `hello()` | `hello_fn` | Returns `"Hello from Mojo!"` |
| `createObject()` | `create_object_fn` | Returns `{}` |
| `makeGreeting()` | `make_greeting_fn` | Returns `{message: "Hello!"}` |
| `greet(name)` | `greet_fn` | Returns `"Hello, <name>!"` |
| `add(a, b)` | `add_fn` | Returns `a + b` (Float64) |
| `isPositive(n)` | `is_positive_fn` | Returns `n > 0` (Bool) |

## Critical Mojo FFI rules

**Imports** (2026 nightly): `from ffi import OwnedDLHandle` — the `sys.ffi` path is deprecated.

**Build flag**: `mojo build --emit shared-lib` — not `-shared`.

**ASAP destruction + string lifetimes**: Mojo's ASAP (eager) destruction frees a value at its last tracked use. Raw pointer derivations (`unsafe_ptr()`) are NOT tracked uses. For FFI string arguments:
- **String literals** for static names: `"propname".unsafe_ptr().bitcast[NoneType]()` — static `.rodata` lifetime, never freed.
- **Heap Strings** for dynamic content: bind to a named `var`, derive pointer after binding, keep the var alive past the FFI call.
- **`StringLiteral` parameter type** on `throw_js_error` enforces compile-time that only literals are passed.

**Function pointers** (confirmed in spike):
```mojo
var fn_ref = my_callback
desc.method = UnsafePointer(to=fn_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
```

**`NapiPropertyDescriptor` struct layout**: Must exactly match the C definition (8 fields in order: `utf8name`, `name`, `method`, `getter`, `setter`, `value`, `attributes`, `data`). Wrong layout causes silent corruption in `napi_define_properties`.

**Status checking**: Every N-API call returning `NapiStatus` must be immediately passed to `check_status()`. This is enforced throughout the codebase.

## Development workflow

Follow the RED → GREEN → REFACTOR TDD cycle (see `docs/METHODOLOGY.md`). Every feature starts with a failing Jest test. The spike (`spike/ffi_probe.mojo`) is the exception — it is validated experimentally, not by tests.
