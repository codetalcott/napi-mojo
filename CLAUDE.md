# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**napi-mojo** — the Mojo equivalent of Rust's `napi-rs`. A framework for building Node.js native addons in Mojo via the Node-API (N-API) C interface. Phase 8 complete — all primitive types, object property reading, function calling, array mapping with handle scopes, argument reading, type checking, error propagation, promises (create/resolve/reject), and async work (worker thread execution with promise resolution) are all working.

## Commands

```bash
pixi run bash build.sh               # compile src/lib.mojo → build/index.node
npm test                              # run all Jest tests (61 tests)
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
src/lib.mojo                             # entry point: callbacks + register_module
src/napi/types.mojo                      # NapiEnv, NapiValue, NapiStatus, NapiDeferred, NapiAsyncWork, NapiPropertyDescriptor, NapiValueType constants
src/napi/raw.mojo                        # OwnedDLHandle symbol resolution (sole user of OwnedDLHandle)
src/napi/error.mojo                      # napi_status_name(), check_status(), throw_js_error(), throw_js_error_dynamic()
src/napi/module.mojo                     # define_property(), register_method()
src/napi/framework/js_string.mojo        # JsString.create(), create_literal(), from_napi_value(), read_arg_0()
src/napi/framework/js_object.mojo        # JsObject.create(), set_property(), set_named_property(), get(), get_property(), get_named_property(), has_property()
src/napi/framework/js_number.mojo        # JsNumber.create(), from_napi_value()
src/napi/framework/js_boolean.mojo       # JsBoolean.create(), from_napi_value()
src/napi/framework/js_null.mojo          # JsNull.create()
src/napi/framework/js_undefined.mojo     # JsUndefined.create()
src/napi/framework/js_array.mojo         # JsArray.create_with_length(), set(), get(), length()
src/napi/framework/js_function.mojo      # JsFunction.call0(), call1(), call2()
src/napi/framework/js_value.mojo         # js_typeof(), js_type_name(), js_is_array()
src/napi/framework/handle_scope.mojo     # HandleScope.open(), close()
src/napi/framework/js_promise.mojo       # JsPromise.create(), resolve(), reject()
src/napi/framework/args.mojo             # CbArgs.get_one(), get_two()
spike/ffi_probe.mojo                     # throwaway FFI validation (run on new machine / Mojo upgrade)
tests/                                   # Jest tests — TDD outside-in
```

### Exported addon functions

| JS name | Mojo fn | Description |
|---------|---------|-------------|
| `hello()` | `hello_fn` | Returns `"Hello from Mojo!"` |
| `createObject()` | `create_object_fn` | Returns `{}` |
| `makeGreeting()` | `make_greeting_fn` | Returns `{message: "Hello!"}` |
| `greet(name)` | `greet_fn` | Returns `"Hello, <name>!"` (type-checks arg) |
| `add(a, b)` | `add_fn` | Returns `a + b` (Float64) |
| `isPositive(n)` | `is_positive_fn` | Returns `n > 0` (Bool) |
| `getNull()` | `get_null_fn` | Returns JavaScript `null` |
| `getUndefined()` | `get_undefined_fn` | Returns JavaScript `undefined` |
| `sumArray(arr)` | `sum_array_fn` | Returns sum of a number array (Float64, validates is_array) |
| `getProperty(obj, key)` | `get_property_fn` | Returns `obj[key]` (uses napi_get_property) |
| `callFunction(fn, arg)` | `call_function_fn` | Calls `fn(arg)` and returns result |
| `mapArray(arr, fn)` | `map_array_fn` | Returns `arr.map(fn)` (handle-scoped loop) |
| `resolveWith(value)` | `resolve_with_fn` | Returns a promise that immediately resolves with `value` |
| `rejectWith(msg)` | `reject_with_fn` | Returns a promise that immediately rejects with Error(`msg`) |
| `asyncDouble(n)` | `async_double_fn` | Returns a promise; computes `n * 2` on worker thread |

## Critical Mojo FFI rules

**Imports** (2026 nightly): `from ffi import OwnedDLHandle` — the `sys.ffi` path is deprecated.

**Build flag**: `mojo build --emit shared-lib` — not `-shared`.

**ASAP destruction + string lifetimes**: Mojo's ASAP (eager) destruction frees a value at its last tracked use. Raw pointer derivations (`unsafe_ptr()`) are NOT tracked uses. For FFI string arguments:

- **String literals** for static names: `"propname".unsafe_ptr().bitcast[NoneType]()` — static `.rodata` lifetime, never freed. Use `JsString.create_literal` and `JsObject.set_property`.
- **Heap Strings** for dynamic content: bind to a named `var`, derive pointer after binding, keep the var alive past the FFI call. Use `throw_js_error_dynamic` for computed error messages.
- **`StringLiteral` parameter type** on `throw_js_error` enforces compile-time that only literals are passed.

**Function pointers** (confirmed in spike):
```mojo
var fn_ref = my_callback
desc.method = UnsafePointer(to=fn_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
```

**`NapiPropertyDescriptor` struct layout**: Must exactly match the C definition (8 fields in order: `utf8name`, `name`, `method`, `getter`, `setter`, `value`, `attributes`, `data`). Wrong layout causes silent corruption in `napi_define_properties`.

**Status checking**: Every N-API call returning `NapiStatus` must be immediately passed to `check_status()`. Errors now surface as readable names (e.g., `napi_string_expected`) via `napi_status_name()`.

**String construction from bytes** (Mojo v26.2): Use `String(from_utf8: Span[Byte])` to build a Mojo String from a raw byte buffer — validates UTF-8 and handles all Unicode correctly. The old `chr()` byte-by-byte approach is ASCII-only and broken for multi-byte sequences.

**`StringLiteral` cannot be returned from runtime-branch functions** — it is parameterized on its compile-time value. Use `String` as the return type for any function that picks from multiple string literals at runtime (see `js_type_name`, `napi_status_name`).

**Type checking before reading**: Use `js_typeof(env, val)` to inspect a value's type before attempting to read it. Compare against `NAPI_TYPE_STRING`, `NAPI_TYPE_NUMBER`, etc. from `napi.types`. This enables descriptive type-mismatch errors. Use `js_is_array(env, val)` to distinguish arrays from plain objects (`napi_typeof` returns `object` for both).

**Property reading with napi_value keys**: Use `napi_get_property(env, obj, key_napi_value, result)` (via `JsObject.get()`) instead of `napi_get_named_property(env, obj, c_string, result)` when the key comes from JavaScript. The named variant requires a null-terminated C string; round-tripping a JS string through `JsString.from_napi_value` → `String.unsafe_ptr()` loses the null terminator, causing property lookup failures. Pass the JS string napi_value directly as the key.

**Handle scopes for loops**: When a loop creates many temporary `napi_value` handles (e.g., `mapArray`), wrap each iteration in `HandleScope.open(env)` / `hs.close(env)`. Values set on objects/arrays outside the scope survive closure. The result container (array/object) MUST be created outside the loop's handle scope. Mojo has no RAII — `close()` must be called explicitly.

**Heap allocation** (Mojo v26.2): Use `alloc[T](count)` from `memory` module (NOT `UnsafePointer[T].alloc(count)` — that syntax was removed). The struct must implement `Movable` with `fn __moveinit__(out self, deinit take: Self)`. Free with `ptr.destroy_pointee()` then `ptr.free()`.

**Async work callbacks**: The execute callback (`fn(NapiEnv, OpaquePointer[MutAnyOrigin])`) runs on a **worker thread** and MUST NOT call any N-API functions — only pure computation on the heap-allocated data struct. The complete callback (`fn(NapiEnv, NapiStatus, OpaquePointer[MutAnyOrigin])`) runs on the **main thread** and can safely call N-API functions. Both return `None` (not `NapiValue`). The same bitcast pattern works for extracting function pointers.

**Async data struct lifetime**: Heap-allocate with `alloc[T](1)` + `init_pointee_move()`. The data struct must contain only simple types (no Mojo `String` or objects with destructors) since the execute callback runs on a worker thread. Pass `data_ptr.bitcast[NoneType]()` as the `void*` data argument. Clean up in the complete callback with `ptr.destroy_pointee()` + `ptr.free()`. The `NapiAsyncWork` handle has a chicken-and-egg: initialize as `NapiAsyncWork()`, create async work, then write the handle back into the data struct before queuing.

**Promise creation**: `napi_create_promise` returns both a deferred handle and a promise napi_value. Use `JsPromise.create(env)` which pairs them. Each deferred can only be resolved OR rejected once. For rejection, create an Error object with `raw_create_error` (not `throw_js_error`) to get a value without setting a pending exception.

## Development workflow

Follow the RED → GREEN → REFACTOR TDD cycle (see `docs/METHODOLOGY.md`). Every feature starts with a failing Jest test. The spike (`spike/ffi_probe.mojo`) is the exception — it is validated experimentally, not by tests.
