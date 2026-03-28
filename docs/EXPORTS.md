# Exported addon functions

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
| `createPropertyKey(str)` | `create_property_key_fn` | Creates an engine-internalized property key string (N-API v10) |
| `createExternalString(str)` | `create_external_string_fn` | Creates a zero-copy external Latin-1 string with GC finalizer (N-API v10) |
| `bufferFromArrayBuffer(ab, offset, length)` | `buffer_from_arraybuffer_fn` | Zero-copy Buffer view into an ArrayBuffer slice (N-API v10) |
