# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**napi-mojo** — the Mojo equivalent of Rust's `napi-rs`. A framework for building Node.js native addons in Mojo via the Node-API (N-API) C interface. All planned phases complete — 110 exported functions + 3 classes covering the full N-API surface: primitive types, integer types (Int32/UInt32/Int64), object property reading/enumeration/deletion, function calling/creation, array mapping with handle scopes, variable-length arguments, type checking, error propagation (Error/TypeError/RangeError/SyntaxError), promises (create/resolve/reject), async work (worker thread execution + cancellation), ThreadsafeFunction (call JS from worker threads), ArrayBuffer (including external/Mojo-owned memory), Buffer, TypedArray, DataView, class construction (wrap/unwrap, prototype methods, getter/setter, static methods, class inheritance via prototype chain), persistent references, escapable handle scopes, global object access, BigInt (including arbitrary-precision word arrays), Date, Symbol, strict equality, instanceof, object freeze/seal/detach, prototype access, array element has/delete, external data (opaque native pointers with GC finalizers), napi_add_finalizer on arbitrary objects, instance data (per-env singleton), environment cleanup hooks (sync + async), type coercion (Boolean/Number/String/Object), TypeScript definition generation with JSDoc, exception handling (throw/catch any value), property set/has by napi_value key (symbol keys), version info (N-API + Node.js), script execution, async context + callback scope, type tagging, and external memory tracking. Higher-level API includes `fn_ptr()`, `ModuleBuilder`/`ClassBuilder` for ergonomic registration, `unwrap_native[T]()` for class methods, `ToJsValue`/`FromJsValue` conversion traits, parametric array helpers (`to/from_js_array_f64/str`), an `AsyncWork` helper for ergonomic async work (promise + queue + resolve/reject), an external code generator (`scripts/generate-addon.mjs` + `src/exports.toml`) for auto-generating callback trampolines, `MojoFloat64Array` for zero-copy TypedArray output, `parallelize_safe()` for SIMD parallel computation with automatic runtime init, and **cached NapiBindings** — all 135 N-API function pointers resolved once at module init, passed through callback data to every entry-point callback (173-389 ns/call, zero per-call dlsym).

## Commands

```bash
pixi run bash build.sh               # compile src/lib.mojo → build/index.node
npm test                              # run all Jest tests (555 tests)
npm run test:gc                       # run GC finalizer tests (requires --expose-gc)
npx jest tests/basic.test.js          # run a single test file
node scripts/benchmark.mjs            # per-call overhead benchmark

# Spike (run before anything else if starting fresh):
pixi run mojo build --emit shared-lib spike/ffi_probe.mojo -o build/probe.dylib
mv build/probe.dylib build/probe.node
node -e "console.log(require('./build/probe.node').hello())"
```

## Architecture

### The core FFI problem

N-API functions (`napi_create_string_utf8`, `napi_define_properties`, etc.) are **not in libc** — they live in the Node.js host process. When Node.js loads our `.node` file via `dlopen`, N-API symbols are already in the process address space. We access them via `OwnedDLHandle()` (equivalent to `dlopen(NULL, ...)`), which opens the host process symbol table at runtime.

### Cached NapiBindings (zero per-call dlsym)

All 118 N-API function pointers are resolved once at module init via a single `OwnedDLHandle()` + 118 `dlsym` calls, stored in the `NapiBindings` struct (`src/napi/bindings.mojo`). The pointer is passed through `NapiPropertyDescriptor.data` to every callback. Each callback retrieves it via `CbArgs.get_bindings(env, info)` (1 bootstrap dlsym for `napi_get_cb_info`, then all subsequent calls use cached pointers). This eliminates the per-call `OwnedDLHandle()` + `dlsym` overhead that would otherwise occur on every N-API call.

**Callbacks that DON'T use cached bindings** (must use old `OwnedDLHandle` path):

- `except:` blocks (fallback when bindings retrieval itself fails)
- Dynamically created inner callbacks (`inner_callback_fn`, `inner_adder_fn`) — their data pointer holds captured values, not bindings
- Async complete/TSFN/finalizer callbacks — fixed signatures without `info` parameter

### How a `.node` addon works

1. `mojo build --emit shared-lib` produces a `.dylib` renamed to `.node`
2. Node.js calls `dlopen` on the `.node` file, then `dlsym("napi_register_module_v1")`
3. Our `@export("napi_register_module_v1", ABI="C")` function is called with `(env, exports)`
4. We allocate `NapiBindings`, resolve all 118 symbols, pass pointer through `ModuleBuilder`
5. Each exported Mojo function acts as a `napi_callback`: `fn(NapiEnv, NapiValue) -> NapiValue`

### Module structure

```
src/lib.mojo                             # entry point: callbacks + register_module
src/napi/types.mojo                      # NapiEnv, NapiValue, NapiStatus, NapiDeferred, NapiAsyncWork, NapiPropertyDescriptor, NapiValueType constants, TypedArray type constants, property attribute constants
src/napi/bindings.mojo                   # NapiBindings struct (118 cached fn ptrs), init_bindings(), Bindings type alias
src/napi/raw.mojo                        # OwnedDLHandle symbol resolution + bindings-accepting overloads
src/napi/error.mojo                      # napi_status_name(), check_status(), throw_js_error(), throw_js_error_dynamic(), throw_js_type_error(), throw_js_range_error()
src/napi/module.mojo                     # define_property(), register_method()
src/napi/framework/js_string.mojo        # JsString.create(), create_literal(), from_napi_value(), read_arg_0()
src/napi/framework/js_object.mojo        # JsObject.create(), set_property(), set_named_property(), set(), get(), get_property(), get_named_property(), has(), has_property(), keys(), has_own(), delete_prop(), instance_of(), freeze(), seal(), prototype()
src/napi/framework/js_number.mojo        # JsNumber.create(), create_int(), from_napi_value(), to_int()
src/napi/framework/js_boolean.mojo       # JsBoolean.create(), from_napi_value()
src/napi/framework/js_int32.mojo         # JsInt32.create(), from_napi_value()
src/napi/framework/js_uint32.mojo        # JsUInt32.create(), from_napi_value()
src/napi/framework/js_int64.mojo         # JsInt64.create(), from_napi_value()
src/napi/framework/js_null.mojo          # JsNull.create()
src/napi/framework/js_undefined.mojo     # JsUndefined.create()
src/napi/framework/js_array.mojo         # JsArray.create_with_length(), set(), get(), length(), has(), delete_element()
src/napi/framework/js_function.mojo      # JsFunction.call0(), call1(), call2(), create(), create_with_data()
src/napi/framework/js_value.mojo         # js_typeof(), js_type_name(), js_is_array(), js_strict_equals(), js_get_global()
src/napi/framework/handle_scope.mojo     # HandleScope.open(), close()
src/napi/framework/js_promise.mojo       # JsPromise.create(), resolve(), reject()
src/napi/framework/js_arraybuffer.mojo   # JsArrayBuffer.create(), byte_length(), data_ptr(), is_arraybuffer()
src/napi/framework/js_buffer.mojo        # JsBuffer.create(), data_ptr(), length(), is_buffer()
src/napi/framework/js_typedarray.mojo    # JsTypedArray.create_float64/uint8/int32/int8/uint8_clamped/int16/uint16/uint32/float32/bigint64/biguint64(), array_type(), length(), data_ptr(), arraybuffer(), is_typedarray()
src/napi/framework/js_class.mojo         # define_class(), register_instance_method(), register_getter(), register_getter_setter(), register_static_method(), register_static_getter(), register_static_getter_setter(), set_class_prototype()
src/napi/framework/js_ref.mojo           # JsRef.create(), get(), delete(), inc(), dec()
src/napi/framework/escapable_handle_scope.mojo # EscapableHandleScope.open(), escape(), close()
src/napi/framework/js_bigint.mojo        # JsBigInt.from_int64(), from_uint64(), to_int64(), to_uint64(), from_words(), word_count(), to_words()
src/napi/framework/js_date.mojo          # JsDate.create(), timestamp_ms(), is_date()
src/napi/framework/js_symbol.mojo        # JsSymbol.create(), create_for()
src/napi/framework/js_external.mojo      # JsExternal.create(), create_no_release(), get_data()
src/napi/framework/js_coerce.mojo        # js_coerce_to_bool(), js_coerce_to_number(), js_coerce_to_string(), js_coerce_to_object()
src/napi/framework/js_exception.mojo     # js_throw(), js_is_exception_pending(), js_get_and_clear_last_exception()
src/napi/framework/js_version.mojo       # get_napi_version(), get_node_version_ptr()
src/napi/framework/js_dataview.mojo      # JsDataView.create(), byte_length(), byte_offset(), data_ptr(), arraybuffer(), is_dataview()
src/napi/framework/threadsafe_function.mojo # ThreadsafeFunction.create(), call_blocking(), call_nonblocking(), acquire(), release(), abort()
src/napi/framework/args.mojo             # CbArgs.get_one(), get_two(), get_this(), get_this_and_one(), argc(), get_argv(), get_data()
src/napi/framework/register.mojo         # fn_ptr(), ModuleBuilder, ClassBuilder — ergonomic registration helpers
src/napi/framework/convert.mojo          # ToJsValue/FromJsValue traits, JsF64/JsI32/JsBool/JsStr/JsRaw wrappers; to/from_js_array_f64/str parametric helpers
src/napi/framework/async_work.mojo       # AsyncWork.queue/resolve/reject_with_error — async work ergonomics
src/napi/framework/runtime.mojo          # init_async_runtime(), parallelize_safe() — async runtime init + safe parallel dispatch
src/napi/framework/js_mojo_array.mojo    # MojoFloat64Array — Mojo-owned Float64 buffer with zero-copy to_js() output
src/napi/framework/js_async_context.mojo # JsAsyncContext — napi_async_init/destroy wrappers
src/napi/framework/callback_scope.mojo   # CallbackScope — napi_open/close_callback_scope wrappers
src/exports.toml                         # Function declarations for code generator
src/generated/callbacks.mojo             # AUTO-GENERATED callbacks from exports.toml
spike/ffi_probe.mojo                     # throwaway FFI validation (run on new machine / Mojo upgrade)
scripts/generate-dts.js                  # auto-generate build/index.d.ts from lib.mojo
scripts/generate-addon.mjs              # auto-generate callback trampolines from src/exports.toml (bindings-aware)
scripts/benchmark.mjs                   # per-call overhead benchmark (node scripts/benchmark.mjs)
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
| `asyncDouble(n)` | `async_double_fn` | Returns a promise; computes `n * 2` on worker thread (uses AsyncWork helpers) |
| `asyncTriple(n)` | `async_triple_fn` | Returns a promise; computes `n * 3` on worker thread (uses AsyncWork helpers) |
| `addInts(a, b)` | `add_ints_fn` | Returns `a + b` (Int32 addition) |
| `bitwiseOr(a, b)` | `bitwise_or_fn` | Returns `a \| b` (UInt32 bitwise OR) |
| `throwTypeError()` | `throw_type_error_fn` | Throws a JavaScript `TypeError` |
| `throwRangeError()` | `throw_range_error_fn` | Throws a JavaScript `RangeError` |
| `addIntsStrict(a, b)` | `add_ints_strict_fn` | Like `addInts` but throws `TypeError` on type mismatch |
| `createArrayBuffer(size)` | `create_arraybuffer_fn` | Creates an ArrayBuffer filled with incrementing bytes |
| `arrayBufferLength(buf)` | `arraybuffer_length_fn` | Returns the byte length of an ArrayBuffer |
| `sumBuffer(buf)` | `sum_buffer_fn` | Sums the bytes of a Node.js Buffer |
| `createBuffer(size)` | `create_buffer_fn` | Creates a Buffer filled with incrementing bytes |
| `doubleFloat64Array(arr)` | `double_float64_array_fn` | Doubles each element of a Float64Array in-place |
| `createTypedArrayView(type, ab, off, len)` | `create_typed_array_view_fn` | Creates a TypedArray view (int8/uint8/int16/int32/float32/float64/etc.) |
| `getTypedArrayType(ta)` | `get_typed_array_type_fn` | Returns the NAPI_*_ARRAY type constant |
| `getTypedArrayLength(ta)` | `get_typed_array_length_fn` | Returns element count of a TypedArray |
| `new Counter(n)` | `counter_constructor_fn` | Class: constructor, `.increment()`, `.reset()`, `.value` getter/setter |
| `Counter.isCounter(val)` | `counter_is_counter_fn` | Returns `true` if `val instanceof Counter` |
| `Counter.fromValue(n)` | `counter_from_value_fn` | Factory: creates `new Counter(n)` via `napi_new_instance` |
| `sumArgs(...)` | `sum_args_fn` | Returns sum of all number arguments (variable args) |
| `createCallback()` | `create_callback_fn` | Returns a Mojo-created JS function |
| `createAdder(n)` | `create_adder_fn` | Returns a function that adds `n` to its argument (closure pattern) |
| `getGlobal()` | `get_global_fn` | Returns the global object (`globalThis`) |
| `testRef()` | `test_ref_fn` | Creates object, stores/retrieves via napi_ref, returns |
| `testRefObject()` | `test_ref_object_fn` | Object reference round-trip |
| `testRefString(s)` | `test_ref_string_fn` | String reference round-trip (wrapped in object) |
| `buildInScope()` | `build_in_scope_fn` | Creates object in escapable handle scope, escapes it |
| `addBigInts(a, b)` | `add_bigints_fn` | Returns `a + b` (BigInt) |
| `createDate(ms)` | `create_date_fn` | Creates a Date from millisecond timestamp |
| `getDateValue(d)` | `get_date_value_fn` | Returns the timestamp of a Date object |
| `createSymbol(desc)` | `create_symbol_fn` | Creates a new unique Symbol |
| `symbolFor(key)` | `symbol_for_fn` | Returns the global Symbol for a key (`Symbol.for`) |
| `getKeys(obj)` | `get_keys_fn` | Returns array of own enumerable keys (`Object.keys`) |
| `hasOwn(obj, key)` | `has_own_fn` | Checks if obj has own property |
| `deleteProperty(obj, key)` | `delete_property_fn` | Deletes a property, returns mutated object |
| `strictEquals(a, b)` | `strict_equals_fn` | Returns `a === b` |
| `isInstanceOf(obj, ctor)` | `is_instance_of_fn` | Returns `obj instanceof ctor` |
| `freezeObject(obj)` | `freeze_object_fn` | Freezes and returns object |
| `sealObject(obj)` | `seal_object_fn` | Seals and returns object |
| `arrayHasElement(arr, i)` | `array_has_element_fn` | Checks if index exists in array |
| `arrayDeleteElement(arr, i)` | `array_delete_element_fn` | Deletes element at index (sparse) |
| `getPrototype(obj)` | `get_prototype_fn` | Returns `Object.getPrototypeOf(obj)` |
| `asyncProgress(count, cb)` | `async_progress_fn` | Calls `cb(i)` for i in 0..count-1 from worker thread via TSFN, returns promise |
| `createExternal(x, y)` | `create_external_fn` | Creates an external wrapping `{x, y}` with GC finalizer |
| `getExternalData(ext)` | `get_external_data_fn` | Retrieves `{x, y}` from an external value |
| `isExternal(val)` | `is_external_fn` | Returns `true` if value is an external |
| `coerceToBool(val)` | `coerce_to_bool_fn` | Returns `Boolean(val)` (JS coercion) |
| `coerceToNumber(val)` | `coerce_to_number_fn` | Returns `Number(val)` (throws on Symbol) |
| `coerceToString(val)` | `coerce_to_string_fn` | Returns `String(val)` (throws on Symbol) |
| `coerceToObject(val)` | `coerce_to_object_fn` | Returns `Object(val)` (throws on null/undefined) |
| `setPropertyByKey(obj, key, val)` | `set_property_by_key_fn` | Sets `obj[key] = val` using napi_value key (string/symbol) |
| `hasPropertyByKey(obj, key)` | `has_property_by_key_fn` | Returns `key in obj` using napi_value key (walks prototype) |
| `throwValue(val)` | `throw_value_fn` | Throws any JS value as an exception |
| `catchAndReturn(val)` | `catch_and_return_fn` | Throws then catches a value, returns the caught value |
| `getNapiVersion()` | `get_napi_version_fn` | Returns the highest N-API version supported |
| `getNodeVersion()` | `get_node_version_fn` | Returns `{major, minor, patch}` of the Node.js runtime |
| `createDataView(ab, offset, len)` | `create_dataview_fn` | Creates a DataView over an ArrayBuffer |
| `getDataViewInfo(dv)` | `get_dataview_info_fn` | Returns `{byteLength, byteOffset}` of a DataView |
| `isDataView(val)` | `is_dataview_fn` | Returns `true` if value is a DataView |
| `bigIntFromWords(sign, words)` | `bigint_from_words_fn` | Creates BigInt from sign + word array |
| `bigIntToWords(bi)` | `bigint_to_words_fn` | Returns `{sign, words}` from a BigInt |
| `createExternalArrayBuffer(size)` | `create_external_arraybuffer_fn` | Creates ArrayBuffer backed by Mojo-owned memory with GC finalizer |
| `attachFinalizer(obj)` | `attach_finalizer_fn` | Attaches a native GC finalizer to any JS object |
| `setInstanceData(n)` | `set_instance_data_fn` | Stores a number as per-env instance data |
| `getInstanceData()` | `get_instance_data_fn` | Retrieves the per-env instance data number |
| `addCleanupHook()` | `add_cleanup_hook_fn` | Registers an env cleanup hook, returns true |
| `removeCleanupHook()` | `remove_cleanup_hook_fn` | Registers and removes a cleanup hook, returns true |
| `cancelAsyncWork()` | `cancel_async_work_fn` | Queues then cancels async work, returns rejected promise |
| `new Animal(name)` | `animal_constructor_fn` | Class: constructor, `.name` getter, `.speak()`, `Animal.isAnimal()` |
| `new Dog(name, breed)` | `dog_constructor_fn` | Class: inherits from Animal, `.breed` getter |
| `runScript(code)` | `run_script_fn` | Evaluates a JS string, returns result |
| `isError(val)` | `is_error_fn` | Returns `true` if val is a JavaScript Error |
| `adjustExternalMemory(n)` | `adjust_external_memory_fn` | Adjusts reported external memory (GC hint), returns new total |
| `detachArrayBuffer(ab)` | `detach_arraybuffer_fn` | Detaches an ArrayBuffer (makes it unusable) |
| `isDetachedArrayBuffer(ab)` | `is_detached_arraybuffer_fn` | Returns `true` if ArrayBuffer is detached |
| `typeTagObject(obj)` | `type_tag_object_fn` | Tags an object with a type tag for later verification |
| `checkObjectTypeTag(obj, tag)` | `check_object_type_tag_fn` | Verifies object's type tag matches expected tag |
| `throwSyntaxError(msg)` | `throw_syntax_error_fn` | Throws a JavaScript `SyntaxError` |
| `getAllPropertyNames(obj)` | `get_all_property_names_fn` | Returns all property names including inherited (`napi_get_all_property_names`) |
| `testWeakRef(val)` | `test_weak_ref_fn` | Tests napi_ref with refcount=0 (weak reference round-trip) |
| `createBufferCopy(data)` | `create_buffer_copy_fn` | Creates a Buffer copy from input bytes |
| `makeCallback(fn, arg)` | `make_callback_fn` | Calls `fn(arg)` via `napi_make_callback` (async context propagation) |
| `makeCallback0(fn)` | `make_callback0_fn` | Calls `fn()` via `napi_make_callback` |
| `makeCallback2(fn, a, b)` | `make_callback2_fn` | Calls `fn(a, b)` via `napi_make_callback` |
| `makeCallbackScope(fn, arg)` | `make_callback_scope_fn` | Calls `fn(arg)` within an explicit callback scope |
| `createNamedFn(name, arity)` | `create_named_fn_fn` | Creates a function with specified name and `.length` arity |
| `newCounterFromRegistry(n)` | `new_counter_from_registry_fn` | Creates a Counter via ClassRegistry (`napi_new_instance`) |
| `getUvEventLoop()` | `get_uv_event_loop_fn` | Returns the libuv event loop pointer (external value) |
| `addAsyncCleanupHook()` | `add_async_cleanup_hook_fn` | Registers an async env cleanup hook, returns true |
| `removeAsyncCleanupHook()` | `remove_async_cleanup_hook_fn` | Registers then removes an async cleanup hook, returns true |
| `getErrorMessage(err)` | `get_error_message_fn` | Returns `.message` string from any Error-like object |
| `getErrorStack(err)` | `get_error_stack_fn` | Returns `.stack` string from any Error-like object |
| `getOptValue(obj)` | `get_opt_value_fn` | Returns `obj.x` if present, else `null` (tests `JsObject.get_opt`) |
| `toJsString(val)` | `to_js_string_fn` | Converts any value to string (passes JS strings through, coerces others) |
| `sumJsArray(arr)` | `sum_js_array_fn` | Sums a Float64Array using `from_js_array_f64` convert helper |
| `doubleArray(arr)` | `double_array_fn` | Returns new array with each element doubled (convert helper round-trip) |
| `reverseStrings(arr)` | `reverse_strings_fn` | Reverses a string array using `from/to_js_array_str` |
| `joinStrings(arr, sep)` | `join_strings_fn` | Joins a string array with separator |
| `objectFromArrays(keys, vals)` | `object_from_arrays_fn` | Creates object from parallel key/value arrays |
| `objectToArrays(obj)` | `object_to_arrays_fn` | Returns `{keys, values}` arrays from an object |
| `genericDoubleArray(arr)` | `generic_double_array_fn` | Generic parametric version of `doubleArray` (demonstrates `ToJsValue`/`FromJsValue`) |
| `genericReverseStrings(arr)` | `generic_reverse_strings_ref` | Generic parametric version of `reverseStrings` |

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

**Class construction (napi_define_class + napi_wrap)**: Use `define_class(env, "Name", constructor_ptr)` to register a class with a bare constructor (property_count=0). Instance methods/getters go on the **prototype** — retrieve via `napi_get_named_property(env, constructor, "prototype", &proto)`, then call `napi_define_properties` on the prototype (NOT the constructor). In the constructor callback, use `CbArgs.get_this()` to get the `this` object, heap-allocate a native data struct with `alloc[T](1)`, and `napi_wrap` it onto `this` with a finalizer. In method callbacks, use `napi_unwrap` to retrieve the native pointer. The finalizer (`fn(NapiEnv, OpaquePointer, OpaquePointer)`) calls `ptr.destroy_pointee()` + `ptr.free()`.

**UnsafePointer origin requirement**: In Mojo v26.2, `UnsafePointer[Byte]` cannot infer the mutability parameter in return type position. Use `UnsafePointer[Byte, MutAnyOrigin]` explicitly for data pointer return types (e.g., in Buffer/ArrayBuffer/TypedArray wrappers).

**Jest cross-realm instanceof**: `instanceof TypeError` / `instanceof RangeError` / `instanceof Date` fails in Jest's sandboxed VM (separate realms). Use `try/catch` with `expect(e.name).toBe('TypeError')` instead of `.toThrow(TypeError)`. For Date, use `Object.prototype.toString.call(d) === '[object Date]'` or check for `typeof d.getTime === 'function'`.

**`ref` is a keyword in Mojo**: Cannot use `ref` as a variable/field name. Use `handle`, `napi_ref`, or `js_ref` instead.

**ThreadsafeFunction (TSFN) race condition**: `napi_call_threadsafe_function` queues calls — the `call_js_cb` may not have fired by the time the async work `complete` callback runs. Use `thread_finalize_cb` (not `complete`) to resolve promises, since `thread_finalize_cb` fires only after ALL pending `call_js_cb` invocations complete. The `complete` callback should only store status and call `napi_release_threadsafe_function`.

**`napi_call_threadsafe_function` has no `env` parameter**: Unlike every other N-API function, it takes `(tsfn, data, mode)` only — designed to be called from any thread. `OwnedDLHandle()` works from worker threads since `dlopen(NULL)` is POSIX thread-safe.

**TSFN `call_js_cb` teardown safety**: During Node.js shutdown, `call_js_cb` may receive `env=NULL` and `js_callback=NULL`. Must check before calling N-API functions — only free the data pointer and return.

**napi_create_reference only supports objects/functions/symbols**: Primitive values (numbers, strings, booleans) cannot be stored in napi_ref. Wrap in an object first if you need to reference a primitive.

**Variable-length arguments**: Use `CbArgs.argc(env, info)` to query count, `alloc[NapiValue](count)` for the buffer, `CbArgs.get_argv(env, info, count, argv_ptr)` to fill it. The argv_ptr parameter requires `UnsafePointer[NapiValue, MutAnyOrigin]` (explicit origin).

**Function creation with closure data**: `JsFunction.create_with_data(env, name, cb_ptr, data_ptr)` passes an arbitrary data pointer to the callback. Retrieve in the callback via `CbArgs.get_data(env, info)`. Heap-allocated data leaks unless manually freed (no destructor hook on plain functions).

**`node_api_symbol_for`**: Uses `node_api_` prefix (not `napi_`). Takes a C string + length, not a napi_value description.

## Development workflow

Follow the RED → GREEN → REFACTOR TDD cycle (see `docs/METHODOLOGY.md`). Every feature starts with a failing Jest test. The spike (`spike/ffi_probe.mojo`) is the exception — it is validated experimentally, not by tests.
