# napi-mojo Target Specification

This document defines the target feature set, architecture, and phased development plan for **napi-mojo** — the Mojo equivalent of Rust's napi-rs. It maps napi-rs capabilities to Mojo equivalents, identifies what's already implemented, and specifies what each future phase should deliver.

## Reference: napi-rs Architecture

napi-rs has three layers:
1. **`napi-sys`** — raw FFI bindings to every N-API C function
2. **`napi`** — safe Rust wrappers (`JsString`, `JsObject`, `Env`, etc.)
3. **`napi-derive`** — proc macros (`#[napi]`) for automatic registration, type coercion, and TypeScript generation

napi-mojo follows the same layered approach:
1. **`src/napi/raw.mojo`** — raw FFI via `OwnedDLHandle` (≈ napi-sys)
2. **`src/napi/framework/`** — safe wrappers (`JsString`, `JsObject`, etc.) (≈ napi crate)
3. **No macro layer yet** — Mojo lacks proc macros; registration is manual

---

## Current Coverage (Phase 14 Complete)

### Implemented N-API Functions (73 of ~120)

| Category | Implemented | Key Functions |
|----------|-------------|---------------|
| Strings | 2 | `create_string_utf8`, `get_value_string_utf8` |
| Objects | 5 | `create_object`, `set_named_property`, `get_property`, `get_named_property`, `has_named_property` |
| Numbers | 2 | `create_double`, `get_value_double` |
| Int32 | 2 | `create_int32`, `get_value_int32` |
| UInt32 | 2 | `create_uint32`, `get_value_uint32` |
| Int64 | 2 | `create_int64`, `get_value_int64` |
| Booleans | 2 | `get_boolean`, `get_value_bool` |
| Null/Undefined | 2 | `get_null`, `get_undefined` |
| Type checking | 2 | `typeof`, `is_array` |
| Arrays | 4 | `create_array_with_length`, `set_element`, `get_element`, `get_array_length` |
| Functions | 3 | `call_function`, `create_function`, `get_new_target` |
| Handle scopes | 5 | `open_handle_scope`, `close_handle_scope`, `open_escapable_handle_scope`, `close_escapable_handle_scope`, `escape_handle` |
| Promises | 3 | `create_promise`, `resolve_deferred`, `reject_deferred` |
| Errors | 6 | `throw_error`, `throw_type_error`, `throw_range_error`, `create_error`, `create_type_error`, `create_range_error` |
| Callback info | 1 | `get_cb_info` |
| Properties | 1 | `define_properties` |
| Async work | 3 | `create_async_work`, `queue_async_work`, `delete_async_work` |
| ArrayBuffer | 4 | `create_arraybuffer`, `get_arraybuffer_info`, `is_arraybuffer`, `detach_arraybuffer` |
| Buffer | 4 | `create_buffer`, `create_buffer_copy`, `get_buffer_info`, `is_buffer` |
| TypedArray | 3 | `create_typedarray`, `get_typedarray_info`, `is_typedarray` |
| Class | 5 | `define_class`, `wrap`, `unwrap`, `remove_wrap`, `new_instance` |
| References | 5 | `create_reference`, `delete_reference`, `reference_ref`, `reference_unref`, `get_reference_value` |
| Global | 1 | `get_global` |
| BigInt | 4 | `create_bigint_int64`, `create_bigint_uint64`, `get_value_bigint_int64`, `get_value_bigint_uint64` |
| Date | 3 | `create_date`, `get_date_value`, `is_date` |
| Symbol | 2 | `create_symbol`, `node_api_symbol_for` |

### Implemented Framework Types (24 structs/modules)

| Type | Capabilities |
|------|-------------|
| `JsString` | create, create_literal, from_napi_value, read_arg_0 |
| `JsObject` | create, set_property, set_named_property, get, get_property, get_named_property, has_property |
| `JsNumber` | create (Float64), create_int, from_napi_value, to_int |
| `JsBoolean` | create, from_napi_value |
| `JsNull` | create |
| `JsUndefined` | create |
| `JsArray` | create_with_length, set, get, length |
| `JsFunction` | call0, call1, call2, create, create_with_data |
| `JsPromise` | create, resolve, reject |
| `HandleScope` | open, close |
| `EscapableHandleScope` | open, escape, close |
| `CbArgs` | get_one, get_two, get_this, get_this_and_one, argc, get_argv, get_data |
| `JsInt32` | create, from_napi_value |
| `JsUInt32` | create, from_napi_value |
| `JsInt64` | create, from_napi_value |
| `JsArrayBuffer` | create, create_and_fill, byte_length, data_ptr, is_arraybuffer |
| `JsBuffer` | create, create_and_fill, data_ptr, length, is_buffer |
| `JsTypedArray` | create_float64, create_uint8, create_int32, length, data_ptr, is_typedarray |
| `JsClass` | define_class, register_instance_method, register_getter, register_getter_setter |
| `JsRef` | create, get, delete, inc, dec |
| `JsBigInt` | from_int64, from_uint64, to_int64, to_uint64 |
| `JsDate` | create, timestamp_ms, is_date |
| `JsSymbol` | create, create_for |
| `js_value` | js_typeof, js_type_name, js_is_array, js_get_global |

### Not Yet Implemented

| napi-rs Feature | N-API Functions Needed |
|-----------------|------------------------|
| Property enumeration | `get_property_names`, `get_all_property_names` |
| Property deletion | `delete_property`, `delete_element`, `has_element` |
| Object identity | `strict_equals`, `instanceof` |
| Object freezing | `object_freeze`, `object_seal` |
| Prototype access | `get_prototype`, `node_api_set_prototype` |
| Set property by key | `set_property`, `has_property` (by napi_value key) |
| Coercion | `coerce_to_bool`, `coerce_to_number`, `coerce_to_string`, `coerce_to_object` |
| External data | `create_external`, `get_value_external` |
| ThreadsafeFunction | `create_threadsafe_function`, `call_threadsafe_function`, `acquire/release_threadsafe_function` |
| Async cancel | `cancel_async_work` |
| Cleanup hooks | `add_env_cleanup_hook`, `remove_env_cleanup_hook` |
| Instance data | `set_instance_data`, `get_instance_data` |
| Version info | `get_version`, `get_node_version` |
| Finalizer | `add_finalizer` |
| Script execution | `run_script` |
| Static class methods | Uses `NAPI_PROPERTY_STATIC` attribute |
| Class inheritance | prototype chain setup |
| Arbitrary-precision BigInt | `create_bigint_words`, `get_value_bigint_words` |
| DataView | `create_dataview`, `get_dataview_info`, `is_dataview` |
| Exception handling | `throw` (value), `is_exception_pending`, `get_and_clear_last_exception` |
| TypeScript generation | N/A (build tool) |

---

## Phased Development Plan

### Phase 9: Integer Types + Error Subtypes ✅

**Goal:** Complete numeric type coverage and richer error handling.

#### 9a: Integer Types

New raw FFI functions:
- `raw_create_int32(env, value: Int32, result)` → calls `napi_create_int32`
- `raw_get_value_int32(env, value, result)` → calls `napi_get_value_int32`
- `raw_create_uint32(env, value: UInt32, result)` → calls `napi_create_uint32`
- `raw_get_value_uint32(env, value, result)` → calls `napi_get_value_uint32`
- `raw_create_int64(env, value: Int64, result)` → calls `napi_create_int64`
- `raw_get_value_int64(env, value, result)` → calls `napi_get_value_int64`

New framework type — `JsInt32`:
```
struct JsInt32:
    var value: NapiValue
    fn create(env, n: Int32) raises -> JsInt32
    fn from_napi_value(env, val: NapiValue) raises -> Int32
```

Analogous structs for `JsUInt32` and `JsInt64`.

Update `JsNumber`:
- Add `create_int(env, n: Int)` convenience (uses `napi_create_int64` internally)
- Add `to_int(env, val)` convenience (uses `napi_get_value_int64` internally)

Exported test functions:
- `addInts(a, b)` — Int32 addition
- `bitwiseOr(a, b)` — UInt32 bitwise OR

Tests: type-checked integer I/O, overflow behavior, float-to-int truncation.

#### 9b: Error Subtypes

New raw FFI functions:
- `raw_throw_type_error(env, code, msg)` → calls `napi_throw_type_error`
- `raw_throw_range_error(env, code, msg)` → calls `napi_throw_range_error`
- `raw_create_type_error(env, code, msg, result)` → calls `napi_create_type_error`
- `raw_create_range_error(env, code, msg, result)` → calls `napi_create_range_error`

New framework functions:
```
fn throw_js_type_error(env, msg: StringLiteral)
fn throw_js_range_error(env, msg: StringLiteral)
fn throw_js_type_error_dynamic(env, msg: String)
fn throw_js_range_error_dynamic(env, msg: String)
```

Tests: `instanceof TypeError`, `instanceof RangeError` validation.

---

### Phase 10: Buffer, ArrayBuffer, and TypedArray ✅

**Goal:** Enable efficient binary data interchange — the primary performance use case for native addons.

#### 10a: ArrayBuffer

New raw FFI functions:
- `raw_create_arraybuffer(env, byte_length, data_ptr, result)` → calls `napi_create_arraybuffer`
- `raw_get_arraybuffer_info(env, arraybuffer, data_ptr, byte_length)` → calls `napi_get_arraybuffer_info`
- `raw_is_arraybuffer(env, value, result)` → calls `napi_is_arraybuffer`
- `raw_detach_arraybuffer(env, arraybuffer)` → calls `napi_detach_arraybuffer`

New framework type — `JsArrayBuffer`:
```
struct JsArrayBuffer:
    var value: NapiValue
    fn create(env, byte_length: UInt) raises -> JsArrayBuffer
    fn byte_length(env) raises -> UInt
    fn data_ptr(env) raises -> UnsafePointer[Byte]   # raw pointer to backing store
    fn is_arraybuffer(env, val: NapiValue) raises -> Bool
```

#### 10b: Buffer

New raw FFI functions:
- `raw_create_buffer(env, length, data_ptr, result)` → calls `napi_create_buffer`
- `raw_create_buffer_copy(env, length, data, data_ptr, result)` → calls `napi_create_buffer_copy`
- `raw_get_buffer_info(env, value, data_ptr, length)` → calls `napi_get_buffer_info`
- `raw_is_buffer(env, value, result)` → calls `napi_is_buffer`

New framework type — `JsBuffer`:
```
struct JsBuffer:
    var value: NapiValue
    fn create(env, length: UInt) raises -> JsBuffer
    fn copy_from(env, data: Span[Byte]) raises -> JsBuffer    # copy bytes into new Buffer
    fn data_ptr(env) raises -> UnsafePointer[Byte]
    fn length(env) raises -> UInt
    fn is_buffer(env, val: NapiValue) raises -> Bool
```

#### 10c: TypedArray

New raw FFI functions:
- `raw_create_typedarray(env, type, length, arraybuffer, byte_offset, result)` → calls `napi_create_typedarray`
- `raw_get_typedarray_info(env, typedarray, type, length, data, arraybuffer, byte_offset)` → calls `napi_get_typedarray_info`
- `raw_is_typedarray(env, value, result)` → calls `napi_is_typedarray`

TypedArray type enum constants:
```
comptime NAPI_INT8_ARRAY: Int32 = 0
comptime NAPI_UINT8_ARRAY: Int32 = 1
comptime NAPI_UINT8_CLAMPED_ARRAY: Int32 = 2
comptime NAPI_INT16_ARRAY: Int32 = 3
comptime NAPI_UINT16_ARRAY: Int32 = 4
comptime NAPI_INT32_ARRAY: Int32 = 5
comptime NAPI_UINT32_ARRAY: Int32 = 6
comptime NAPI_FLOAT32_ARRAY: Int32 = 7
comptime NAPI_FLOAT64_ARRAY: Int32 = 8
comptime NAPI_BIGINT64_ARRAY: Int32 = 9
comptime NAPI_BIGUINT64_ARRAY: Int32 = 10
```

New framework type — `JsTypedArray`:
```
struct JsTypedArray:
    var value: NapiValue
    fn create_uint8(env, arraybuffer: JsArrayBuffer, offset: UInt, length: UInt) raises -> JsTypedArray
    fn create_float64(env, arraybuffer: JsArrayBuffer, offset: UInt, length: UInt) raises -> JsTypedArray
    fn create_int32(env, arraybuffer: JsArrayBuffer, offset: UInt, length: UInt) raises -> JsTypedArray
    fn array_type(env) raises -> Int32         # returns NAPI_*_ARRAY constant
    fn length(env) raises -> UInt
    fn data_ptr(env) raises -> UnsafePointer[Byte]
    fn arraybuffer(env) raises -> JsArrayBuffer
```

Exported test functions:
- `sumBuffer(buf)` — sum bytes of a Buffer
- `createBuffer(size)` — return a Buffer filled with incrementing values
- `doubleFloat64Array(arr)` — double each element in-place, return same array

Tests: Buffer round-trip, TypedArray element access, zero-copy mutation verification, type validation.

---

### Phase 11: Class Construction ✅

**Goal:** Enable Mojo structs to become JavaScript classes with constructors, methods, getters/setters, and finalizers.

This is the most architecturally significant phase. In napi-rs, `#[napi]` on a struct auto-generates class registration. In napi-mojo, this must be done manually.

#### N-API Functions

New raw FFI functions:
- `raw_define_class(env, utf8name, length, constructor, data, property_count, properties, result)` → calls `napi_define_class`
- `raw_wrap(env, js_object, native_object, finalize_cb, finalize_hint, result)` → calls `napi_wrap`
- `raw_unwrap(env, js_object, result)` → calls `napi_unwrap`
- `raw_remove_wrap(env, js_object, result)` → calls `napi_remove_wrap`
- `raw_new_instance(env, constructor, argc, argv, result)` → calls `napi_new_instance`
- `raw_add_finalizer(env, js_object, native_data, finalize_cb, finalize_hint, result)` → calls `napi_add_finalizer`

#### Framework Design

New framework module — `JsClass`:
```
struct JsClassDef:
    var name: StringLiteral
    var constructor_fn: OpaquePointer[MutAnyOrigin]  # napi_callback
    var methods: List[NapiPropertyDescriptor]         # or fixed-size approach

    fn add_method(name: StringLiteral, fn_ptr: OpaquePointer[MutAnyOrigin])
    fn add_getter(name: StringLiteral, fn_ptr: OpaquePointer[MutAnyOrigin])
    fn add_setter(name: StringLiteral, fn_ptr: OpaquePointer[MutAnyOrigin])
    fn register(env, exports) raises -> NapiValue     # calls napi_define_class
```

Wrapping pattern — store Mojo struct on heap, attach to JS object:
```
# In constructor callback:
var data = alloc[MyStruct](1)
init_pointee_move(data, MyStruct(...))
raw_wrap(env, this_obj, data.bitcast[NoneType](), finalize_fn, ...)

# In method callback:
var data = raw_unwrap(env, this_obj)  # recover heap pointer
var my_struct = data.bitcast[MyStruct]()[]

# In finalizer:
ptr.destroy_pointee()
ptr.free()
```

**Key constraint:** The wrapped native data must be heap-allocated via `alloc[T]` with `Movable` trait. The finalizer callback frees it when the JS object is garbage collected.

Exported test class:
```javascript
const counter = new Counter(0);
counter.increment();
counter.increment();
counter.value;        // 2 (getter)
counter.value = 10;   // setter
counter.value;        // 10
Counter.create(5);    // static factory method
```

Tests: constructor, methods, getters/setters, multiple instances, GC finalizer (weak ref check).

---

### Phase 12: Function Creation + Global Access ✅

**Goal:** Create JavaScript functions from Mojo (not just export callbacks), and access the global object.

#### Function Creation

New raw FFI functions:
- `raw_create_function(env, utf8name, length, cb, data, result)` → calls `napi_create_function`
- `raw_get_new_target(env, info, result)` → calls `napi_get_new_target`

New framework method on `JsFunction`:
```
fn create(env, name: StringLiteral, cb: OpaquePointer[MutAnyOrigin]) raises -> JsFunction
```

This enables patterns like:
- Returning closures/callbacks from Mojo to JS
- Creating method functions dynamically
- Factory patterns

#### Global Object

New raw FFI function:
- `raw_get_global(env, result)` → calls `napi_get_global`

New framework function:
```
fn js_get_global(env) raises -> JsObject
```

Use cases: accessing `console`, `setTimeout`, `process`, `Buffer` constructor.

#### Variable Argument Count

Extend `CbArgs`:
```
fn get_n(env, info, n: Int) raises -> List[NapiValue]
fn argc(env, info) raises -> Int    # query argument count without reading
```

Tests: dynamic function creation, calling created functions, global object property access, `new.target` detection.

---

### Phase 13: References + Escapable Handle Scopes ✅

**Goal:** Prevent garbage collection of JS values held across async boundaries; escape values from inner scopes.

#### References

New raw FFI functions:
- `raw_create_reference(env, value, initial_refcount, result)` → calls `napi_create_reference`
- `raw_delete_reference(env, ref)` → calls `napi_delete_reference`
- `raw_reference_ref(env, ref, result)` → calls `napi_reference_ref`
- `raw_reference_unref(env, ref, result)` → calls `napi_reference_unref`
- `raw_get_reference_value(env, ref, result)` → calls `napi_get_reference_value`

New framework type — `JsRef`:
```
struct JsRef:
    var ref: OpaquePointer[MutAnyOrigin]  # napi_ref

    fn create(env, value: NapiValue, refcount: UInt32) raises -> JsRef
    fn delete(env) raises
    fn inc(env) raises -> UInt32
    fn dec(env) raises -> UInt32
    fn get(env) raises -> NapiValue
```

#### Escapable Handle Scopes

New raw FFI functions:
- `raw_open_escapable_handle_scope(env, result)` → calls `napi_open_escapable_handle_scope`
- `raw_close_escapable_handle_scope(env, scope)` → calls `napi_close_escapable_handle_scope`
- `raw_escape_handle(env, scope, escapee, result)` → calls `napi_escape_handle`

New framework type — `EscapableHandleScope`:
```
struct EscapableHandleScope:
    var scope: OpaquePointer[MutAnyOrigin]

    fn open(env) raises -> EscapableHandleScope
    fn escape(env, value: NapiValue) raises -> NapiValue  # can only be called once
    fn close(env) raises
```

Use case: creating a value inside a handle scope that must outlive the scope (e.g., building an object in a helper function that returns it to the caller).

Tests: reference prevents GC, reference deletion allows GC, escapable scope returns value to parent.

---

### Phase 14: BigInt + Date + Symbol ✅

**Goal:** Support remaining JavaScript primitive-ish types.

#### BigInt (requires N-API version 6+)

New raw FFI functions:
- `raw_create_bigint_int64(env, value, result)` → calls `napi_create_bigint_int64`
- `raw_create_bigint_uint64(env, value, result)` → calls `napi_create_bigint_uint64`
- `raw_get_value_bigint_int64(env, value, result, lossless)` → calls `napi_get_value_bigint_int64`
- `raw_get_value_bigint_uint64(env, value, result, lossless)` → calls `napi_get_value_bigint_uint64`

New framework type — `JsBigInt`:
```
struct JsBigInt:
    var value: NapiValue
    fn from_int64(env, n: Int64) raises -> JsBigInt
    fn from_uint64(env, n: UInt64) raises -> JsBigInt
    fn to_int64(env) raises -> Int64
    fn to_uint64(env) raises -> UInt64
```

#### Date (requires N-API version 5+)

New raw FFI functions:
- `raw_create_date(env, time: Float64, result)` → calls `napi_create_date`
- `raw_get_date_value(env, value, result)` → calls `napi_get_date_value`
- `raw_is_date(env, value, result)` → calls `napi_is_date`

New framework type — `JsDate`:
```
struct JsDate:
    var value: NapiValue
    fn create(env, timestamp_ms: Float64) raises -> JsDate
    fn timestamp_ms(env) raises -> Float64
    fn is_date(env, val: NapiValue) raises -> Bool
```

#### Symbol

New raw FFI functions:
- `raw_create_symbol(env, description, result)` → calls `napi_create_symbol`
- `raw_symbol_for(env, description, length, result)` → calls `node_api_symbol_for`

New framework type — `JsSymbol`:
```
struct JsSymbol:
    var value: NapiValue
    fn create(env, description: String) raises -> JsSymbol
    fn create_global(env, key: String) raises -> JsSymbol  # Symbol.for()
```

Tests: BigInt round-trip, Date creation from timestamp, Symbol uniqueness, Symbol.for() global registry.

---

### Phase 15: Property Enumeration + Object Utilities

**Goal:** Enable introspection of JS objects — enumerate keys, check equality, freeze/seal.

New raw FFI functions:
- `raw_get_property_names(env, object, result)` → calls `napi_get_property_names`
- `raw_get_all_property_names(env, object, key_mode, key_filter, key_conversion, result)` → calls `napi_get_all_property_names`
- `raw_has_own_property(env, object, key, result)` → calls `napi_has_own_property`
- `raw_delete_property(env, object, key, result)` → calls `napi_delete_property`
- `raw_has_element(env, object, index, result)` → calls `napi_has_element`
- `raw_delete_element(env, object, index, result)` → calls `napi_delete_element`
- `raw_strict_equals(env, lhs, rhs, result)` → calls `napi_strict_equals`
- `raw_instanceof(env, object, constructor, result)` → calls `napi_instanceof`
- `raw_object_freeze(env, object)` → calls `napi_object_freeze`
- `raw_object_seal(env, object)` → calls `napi_object_seal`
- `raw_get_prototype(env, object, result)` → calls `napi_get_prototype`

New framework methods on `JsObject`:
```
fn keys(env) raises -> JsArray                              # enumerable own keys
fn has_own(env, key: NapiValue) raises -> Bool
fn delete(env, key: NapiValue) raises -> Bool
fn freeze(env) raises
fn seal(env) raises
fn prototype(env) raises -> NapiValue
fn strict_equals(env, other: NapiValue) raises -> Bool
fn instance_of(env, constructor: NapiValue) raises -> Bool
```

Tests: key enumeration, delete property, freeze prevents modification, seal prevents addition, strict equality, instanceof.

---

### Phase 16: ThreadsafeFunction

**Goal:** Enable calling JavaScript functions from Mojo worker threads. This is critical for streaming, event-driven, and long-running background work.

New raw FFI functions:
- `raw_create_threadsafe_function(env, func, async_resource, async_resource_name, max_queue_size, initial_thread_count, thread_finalize_data, thread_finalize_cb, context, call_js_cb, result)` → calls `napi_create_threadsafe_function`
- `raw_call_threadsafe_function(tsfn, data, is_blocking)` → calls `napi_call_threadsafe_function`
- `raw_acquire_threadsafe_function(tsfn)` → calls `napi_acquire_threadsafe_function`
- `raw_release_threadsafe_function(tsfn, mode)` → calls `napi_release_threadsafe_function`

New framework type — `ThreadsafeFunction`:
```
struct ThreadsafeFunction:
    var tsfn: OpaquePointer[MutAnyOrigin]

    fn create(env, func: JsFunction, max_queue: UInt) raises -> ThreadsafeFunction
    fn call_blocking(data: OpaquePointer[MutAnyOrigin]) raises
    fn call_nonblocking(data: OpaquePointer[MutAnyOrigin]) raises
    fn acquire() raises
    fn release() raises
```

Use cases:
- Progress reporting from worker threads
- Streaming data processing
- Event-driven native code calling back into JS

Tests: call JS callback from async execute callback, blocking vs non-blocking modes, queue full behavior.

---

### Phase 17: External Data + Coercion

**Goal:** Wrap opaque Mojo pointers as JS values, and support implicit JS type coercion.

#### External

New raw FFI functions:
- `raw_create_external(env, data, finalize_cb, finalize_hint, result)` → calls `napi_create_external`
- `raw_get_value_external(env, value, result)` → calls `napi_get_value_external`

New framework type — `JsExternal`:
```
struct JsExternal:
    var value: NapiValue
    fn create[T](env, data: UnsafePointer[T], finalize_cb) raises -> JsExternal
    fn unwrap[T](env) raises -> UnsafePointer[T]
```

#### Coercion

New raw FFI functions:
- `raw_coerce_to_bool(env, value, result)` → calls `napi_coerce_to_bool`
- `raw_coerce_to_number(env, value, result)` → calls `napi_coerce_to_number`
- `raw_coerce_to_string(env, value, result)` → calls `napi_coerce_to_string`
- `raw_coerce_to_object(env, value, result)` → calls `napi_coerce_to_object`

New framework functions:
```
fn js_coerce_to_bool(env, val: NapiValue) raises -> NapiValue
fn js_coerce_to_number(env, val: NapiValue) raises -> NapiValue
fn js_coerce_to_string(env, val: NapiValue) raises -> NapiValue
fn js_coerce_to_object(env, val: NapiValue) raises -> NapiValue
```

Tests: external data round-trip with finalizer, coercion of various types.

---

### Phase 18: TypeScript Definition Generation

**Goal:** Auto-generate `.d.ts` files from the addon's exported functions.

Since Mojo lacks proc macros, this must be a build-time tool. Approach:

1. **Convention-based scanning** — a script (Node.js or Mojo) reads `src/lib.mojo`, extracts `register_method` calls and their callback signatures
2. **Type inference** — map Mojo callback patterns to TypeScript types:
   - `JsString.create` return → `string`
   - `JsNumber.create` return → `number`
   - `JsBoolean.create` return → `boolean`
   - `JsObject.create` return → `object`
   - `JsArray` return → `any[]`
   - `JsPromise` return → `Promise<T>`
   - `JsNull.create` → `null`
   - `JsUndefined.create` → `undefined`
3. **Output** — write `build/index.d.ts`

Minimal viable output:
```typescript
export function hello(): string;
export function createObject(): object;
export function greet(name: string): string;
export function add(a: number, b: number): number;
export function asyncDouble(n: number): Promise<number>;
// ...
```

Stretch: a Mojo-side metadata registry where each exported function declares its TS signature.

---

### Phase 19: Build & Distribution (prebuildify)

**Goal:** Package the addon for npm distribution with prebuilt binaries.

#### Platform matrix

| OS | Arch | Shared lib extension |
|----|------|---------------------|
| macOS | arm64 (Apple Silicon) | .dylib → .node |
| macOS | x86_64 | .dylib → .node |
| Linux | x86_64 | .so → .node |
| Linux | arm64 | .so → .node |

#### npm package structure (napi-rs pattern)

```
@napi-mojo/example/
├── package.json                    # main package with optionalDependencies
├── index.js                        # platform detection + binary loading
├── index.d.ts                      # TypeScript definitions
└── npm/
    ├── darwin-arm64/
    │   ├── package.json
    │   └── example.darwin-arm64.node
    ├── darwin-x64/
    │   ├── package.json
    │   └── example.darwin-x64.node
    ├── linux-x64-gnu/
    │   ├── package.json
    │   └── example.linux-x64-gnu.node
    └── linux-arm64-gnu/
        ├── package.json
        └── example.linux-arm64-gnu.node
```

#### CI pipeline

- GitHub Actions matrix build across macOS arm64, macOS x64, Linux x64, Linux arm64
- Each runner: install pixi + Mojo, compile, rename, upload as artifact
- Release job: download all artifacts, publish platform packages to npm

---

## napi-rs Feature Parity Reference

Complete mapping of napi-rs features to napi-mojo status and target phase:

| napi-rs Feature | napi-mojo Status | Target Phase |
|----------------|-----------------|-------------|
| String (UTF-8) | Done | — |
| Number (Float64) | Done | — |
| Boolean | Done | — |
| Null / Undefined | Done | — |
| Object create/read/write | Done | — |
| Array create/read/write | Done | — |
| Function calling | Done | — |
| Promise create/resolve/reject | Done | — |
| Async work (worker thread) | Done | — |
| Handle scopes | Done | — |
| Error throwing | Done | — |
| Type checking (typeof) | Done | — |
| Callback argument extraction | Done | — |
| Integer types (i32/u32/i64) | Done | Phase 9 |
| TypeError / RangeError | Done | Phase 9 |
| Buffer | Done | Phase 10 |
| ArrayBuffer | Done | Phase 10 |
| TypedArray | Done | Phase 10 |
| Class (constructor/methods) | Done | Phase 11 |
| Class (getters/setters) | Done | Phase 11 |
| Class (static methods) | Not started | Phase 15 |
| Class (custom finalizer) | Done | Phase 11 |
| Function creation | Done | Phase 12 |
| Global object access | Done | Phase 12 |
| Variable arg count | Done | Phase 12 |
| References (prevent GC) | Done | Phase 13 |
| Escapable handle scopes | Done | Phase 13 |
| BigInt | Done | Phase 14 |
| Date | Done | Phase 14 |
| Symbol | Done | Phase 14 |
| Property enumeration | Not started | Phase 15 |
| Object freeze/seal | Not started | Phase 15 |
| strict_equals / instanceof | Not started | Phase 15 |
| ThreadsafeFunction | Not started | Phase 16 |
| External data | Not started | Phase 17 |
| Type coercion | Not started | Phase 17 |
| TypeScript .d.ts generation | Not started | Phase 18 |
| Prebuilt binary distribution | Not started | Phase 19 |
| Serde-like serialization | Not applicable | — |
| Proc macro (#[napi]) | Not applicable | — |
| Tokio runtime integration | Not applicable | — |
| `Either<A, B>` union types | Not applicable | — |
| WASM fallback | Not applicable | — |

"Not applicable" means the feature depends on Rust-specific capabilities (proc macros, trait system, tokio ecosystem) that have no direct Mojo equivalent today.

---

## Design Principles

These principles guide all phases:

1. **Safety over convenience** — every N-API status code is checked; every type is validated before use
2. **Literal-first string handling** — use `StringLiteral` for static names to avoid ASAP destruction bugs
3. **Explicit lifetime management** — no RAII in Mojo means handle scopes, references, and finalizers must be closed/freed manually
4. **One-at-a-time property registration** — avoids `InlineArray` Copyable issues with struct arrays
5. **Heap allocation for cross-boundary data** — `alloc[T]` + `Movable` trait for any data that crosses async or GC boundaries
6. **Worker thread purity** — execute callbacks must never touch N-API; only the complete callback can
7. **Test-driven outside-in** — every feature starts as a failing Jest test (see `docs/METHODOLOGY.md`)

---

## N-API Version Requirements

| Feature | Minimum N-API Version |
|---------|----------------------|
| Core (strings, numbers, objects, arrays) | 1 |
| Promises | 1 |
| Async work | 1 |
| Date | 5 |
| BigInt | 6 |
| Object freeze/seal | 8 |
| Type tags | 8 |
| SharedArrayBuffer | 9 |

Node.js 18+ supports N-API version 9. Node.js 20+ supports version 9. Node.js 22+ supports version 10. Targeting N-API 6+ (Node.js 14+) covers all planned features except freeze/seal and type tags.
