## src/napi/raw.mojo — raw N-API FFI bindings via host process symbol lookup
##
## This is the ONLY file in the project allowed to use OwnedDLHandle directly.
## All other code must go through these raw_* wrapper functions.
##
## N-API symbols (napi_create_string_utf8, napi_define_properties, etc.) are
## not in libc — they live in the Node.js host process. When Node.js dlopen()s
## our .node file, those symbols are already in the process address space.
## OwnedDLHandle() (no args) calls dlopen(NULL), opening the host process
## image and making all N-API symbols available via dlsym.
##
## All raw_* functions are marked `raises` because OwnedDLHandle() can fail
## (e.g., symbol not found). Callers must handle or propagate the error.

from ffi import OwnedDLHandle
from napi.types import NapiEnv, NapiValue, NapiStatus, NapiAsyncContext, NapiCallbackScope
from napi.bindings import NapiBindings, Bindings

## raw_create_string_utf8 — wraps napi_create_string_utf8
##
## Creates a JavaScript string value from a UTF-8 C string pointer.
## `str_ptr`: pointer to UTF-8 bytes (must remain alive until this returns)
## `length`:  byte length of the string (not including null terminator)
## `result`:  out-pointer; receives the created napi_value
fn raw_create_string_utf8(
    env: NapiEnv,
    str_ptr: OpaquePointer[ImmutAnyOrigin],
    length: UInt,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (
            NapiEnv,
            OpaquePointer[ImmutAnyOrigin],
            UInt,
            OpaquePointer[MutAnyOrigin],
        ) -> NapiStatus
    ]("napi_create_string_utf8")
    return f(env, str_ptr, length, result)

fn raw_create_string_utf8(
    b: Bindings,
    env: NapiEnv,
    str_ptr: OpaquePointer[ImmutAnyOrigin],
    length: UInt,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].create_string_utf8).bitcast[
        fn (NapiEnv, OpaquePointer[ImmutAnyOrigin], UInt, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, str_ptr, length, result)

## raw_create_object — wraps napi_create_object
##
## Creates a new empty JavaScript object {}.
## `result`: out-pointer; receives the created napi_value
fn raw_create_object(
    env: NapiEnv,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_object")
    return f(env, result)

fn raw_create_object(
    b: Bindings,
    env: NapiEnv,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].create_object).bitcast[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, result)

## raw_set_named_property — wraps napi_set_named_property
##
## Sets a named property on a JavaScript object.
## `utf8name`: null-terminated UTF-8 property name (must remain alive until return)
## `value`:    the napi_value to assign to the property
fn raw_set_named_property(
    env: NapiEnv,
    object: NapiValue,
    utf8name: OpaquePointer[ImmutAnyOrigin],
    value: NapiValue,
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[ImmutAnyOrigin], NapiValue) -> NapiStatus
    ]("napi_set_named_property")
    return f(env, object, utf8name, value)

fn raw_set_named_property(
    b: Bindings,
    env: NapiEnv,
    object: NapiValue,
    utf8name: OpaquePointer[ImmutAnyOrigin],
    value: NapiValue,
) -> NapiStatus:
    var f = UnsafePointer(to=b[].set_named_property).bitcast[
        fn (NapiEnv, NapiValue, OpaquePointer[ImmutAnyOrigin], NapiValue) -> NapiStatus
    ]()[]
    return f(env, object, utf8name, value)

## raw_get_cb_info — wraps napi_get_cb_info
##
## Extracts callback arguments and this-value from a napi_callback_info handle.
## `argc`:     in/out — pass max args wanted; receives actual args available
## `argv`:     out — pointer to an array of napi_value (caller allocates)
## `this_arg`: out — pointer to receive the this value (pass NULL to ignore)
## `data`:     out — pointer to receive callback data (pass NULL to ignore)
fn raw_get_cb_info(
    env: NapiEnv,
    info: NapiValue,
    argc: OpaquePointer[MutAnyOrigin],
    argv: OpaquePointer[MutAnyOrigin],
    this_arg: OpaquePointer[MutAnyOrigin],
    data: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (
            NapiEnv,
            NapiValue,
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
        ) -> NapiStatus
    ]("napi_get_cb_info")
    return f(env, info, argc, argv, this_arg, data)

fn raw_get_cb_info(
    b: Bindings,
    env: NapiEnv,
    info: NapiValue,
    argc: OpaquePointer[MutAnyOrigin],
    argv: OpaquePointer[MutAnyOrigin],
    this_arg: OpaquePointer[MutAnyOrigin],
    data: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].get_cb_info).bitcast[
        fn (
            NapiEnv,
            NapiValue,
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
        ) -> NapiStatus
    ]()[]
    return f(env, info, argc, argv, this_arg, data)

## raw_get_value_string_utf8 — wraps napi_get_value_string_utf8
##
## Reads a JavaScript string value into a UTF-8 byte buffer.
## When `buf` is a null pointer and `bufsize` is 0, writes the required byte
## count (excluding null terminator) into `result` without reading any data.
## On a full read, `result` receives the number of bytes written (excl. null).
fn raw_get_value_string_utf8(
    env: NapiEnv,
    value: NapiValue,
    buf: OpaquePointer[MutAnyOrigin],
    bufsize: UInt,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin], UInt, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_value_string_utf8")
    return f(env, value, buf, bufsize, result)

fn raw_get_value_string_utf8(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    buf: OpaquePointer[MutAnyOrigin],
    bufsize: UInt,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].get_value_string_utf8).bitcast[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin], UInt, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, value, buf, bufsize, result)

## raw_define_properties — wraps napi_define_properties
##
## Registers `property_count` properties on `object` using an array of
## NapiPropertyDescriptor structs pointed to by `properties`.
## The caller is responsible for correct struct layout and pointer lifetimes.
fn raw_define_properties(
    env: NapiEnv,
    object: NapiValue,
    property_count: UInt,
    properties: OpaquePointer[ImmutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, UInt, OpaquePointer[ImmutAnyOrigin]) -> NapiStatus
    ]("napi_define_properties")
    return f(env, object, property_count, properties)

fn raw_define_properties(
    b: Bindings,
    env: NapiEnv,
    object: NapiValue,
    property_count: UInt,
    properties: OpaquePointer[ImmutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].define_properties).bitcast[
        fn (NapiEnv, NapiValue, UInt, OpaquePointer[ImmutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, object, property_count, properties)

## raw_get_value_double — wraps napi_get_value_double
##
## Reads a JavaScript number value as a C double (Float64).
## `value`:  the napi_value holding the JS number
## `result`: out-pointer; receives the double value
fn raw_get_value_double(
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_value_double")
    return f(env, value, result)

fn raw_get_value_double(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].get_value_double).bitcast[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, value, result)

## raw_create_double — wraps napi_create_double
##
## Creates a JavaScript number value from a C double (Float64).
## `value`:  the double to wrap as a JS number
## `result`: out-pointer; receives the created napi_value
fn raw_create_double(
    env: NapiEnv,
    value: Float64,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, Float64, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_double")
    return f(env, value, result)

fn raw_create_double(
    b: Bindings,
    env: NapiEnv,
    value: Float64,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].create_double).bitcast[
        fn (NapiEnv, Float64, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, value, result)

## raw_throw_error — wraps napi_throw_error
##
## Sets a pending JavaScript Error exception in the current environment.
## `code`: optional error code string (pass OpaquePointer[ImmutAnyOrigin]() for none)
## `msg`:  UTF-8 error message (must remain alive until this returns)
##
## After calling this, the callback must return immediately with NapiValue().
## Node.js will propagate the pending exception when the callback returns.
fn raw_throw_error(
    env: NapiEnv,
    code: OpaquePointer[ImmutAnyOrigin],
    msg: OpaquePointer[ImmutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, OpaquePointer[ImmutAnyOrigin], OpaquePointer[ImmutAnyOrigin]) -> NapiStatus
    ]("napi_throw_error")
    return f(env, code, msg)

fn raw_throw_error(
    b: Bindings,
    env: NapiEnv,
    code: OpaquePointer[ImmutAnyOrigin],
    msg: OpaquePointer[ImmutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].throw_error).bitcast[
        fn (NapiEnv, OpaquePointer[ImmutAnyOrigin], OpaquePointer[ImmutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, code, msg)

## raw_get_boolean — wraps napi_get_boolean
##
## Returns the napi_value for the JavaScript true or false singleton.
## `value`:  true → JS true, false → JS false
## `result`: out-pointer; receives the boolean napi_value
fn raw_get_boolean(
    env: NapiEnv,
    value: Bool,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, Bool, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_boolean")
    return f(env, value, result)

fn raw_get_boolean(
    b: Bindings,
    env: NapiEnv,
    value: Bool,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].get_boolean).bitcast[
        fn (NapiEnv, Bool, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, value, result)

## raw_get_value_bool — wraps napi_get_value_bool
##
## Reads the C bool value of a JavaScript boolean napi_value.
## `value`:  a napi_value holding a JS boolean
## `result`: out-pointer to a Bool; receives true (1) or false (0)
fn raw_get_value_bool(
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_value_bool")
    return f(env, value, result)

fn raw_get_value_bool(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].get_value_bool).bitcast[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, value, result)

## raw_typeof — wraps napi_typeof
##
## Returns the napi_valuetype of a JavaScript value as an Int32.
## `value`:  the napi_value to inspect
## `result`: out-pointer to an Int32; receives the napi_valuetype
fn raw_typeof(
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_typeof")
    return f(env, value, result)

fn raw_typeof(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].typeof_).bitcast[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, value, result)

## raw_get_null — wraps napi_get_null
##
## Returns the napi_value for the JavaScript null singleton.
## `result`: out-pointer; receives the null napi_value
fn raw_get_null(
    env: NapiEnv,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_null")
    return f(env, result)

fn raw_get_null(
    b: Bindings,
    env: NapiEnv,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].get_null).bitcast[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, result)

## raw_get_undefined — wraps napi_get_undefined
##
## Returns the napi_value for the JavaScript undefined singleton.
## `result`: out-pointer; receives the undefined napi_value
fn raw_get_undefined(
    env: NapiEnv,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_undefined")
    return f(env, result)

fn raw_get_undefined(
    b: Bindings,
    env: NapiEnv,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].get_undefined).bitcast[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, result)

## raw_create_array_with_length — wraps napi_create_array_with_length
##
## Creates a new JavaScript array with the given initial length.
## `length`: the initial length (sets array.length property)
## `result`: out-pointer; receives the created array napi_value
fn raw_create_array_with_length(
    env: NapiEnv,
    length: UInt,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, UInt, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_array_with_length")
    return f(env, length, result)

fn raw_create_array_with_length(
    b: Bindings,
    env: NapiEnv,
    length: UInt,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].create_array_with_length).bitcast[
        fn (NapiEnv, UInt, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, length, result)

## raw_set_element — wraps napi_set_element
##
## Sets a value at a specific integer index in a JavaScript array.
## `object`: the array napi_value
## `index`:  the integer index
## `value`:  the napi_value to store at `index`
fn raw_set_element(
    env: NapiEnv,
    object: NapiValue,
    index: UInt32,
    value: NapiValue,
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, UInt32, NapiValue) -> NapiStatus
    ]("napi_set_element")
    return f(env, object, index, value)

fn raw_set_element(
    b: Bindings,
    env: NapiEnv,
    object: NapiValue,
    index: UInt32,
    value: NapiValue,
) -> NapiStatus:
    var f = UnsafePointer(to=b[].set_element).bitcast[
        fn (NapiEnv, NapiValue, UInt32, NapiValue) -> NapiStatus
    ]()[]
    return f(env, object, index, value)

## raw_get_element — wraps napi_get_element
##
## Gets the value at a specific integer index in a JavaScript array.
## `object`: the array napi_value
## `index`:  the integer index
## `result`: out-pointer; receives the napi_value at `index`
fn raw_get_element(
    env: NapiEnv,
    object: NapiValue,
    index: UInt32,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, UInt32, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_element")
    return f(env, object, index, result)

fn raw_get_element(
    b: Bindings,
    env: NapiEnv,
    object: NapiValue,
    index: UInt32,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].get_element).bitcast[
        fn (NapiEnv, NapiValue, UInt32, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, object, index, result)

## raw_get_array_length — wraps napi_get_array_length
##
## Returns the length of a JavaScript array as a UInt32.
## `object`: the array napi_value
## `result`: out-pointer to a UInt32; receives the array length
fn raw_get_array_length(
    env: NapiEnv,
    object: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_array_length")
    return f(env, object, result)

fn raw_get_array_length(
    b: Bindings,
    env: NapiEnv,
    object: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].get_array_length).bitcast[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, object, result)

## raw_get_property — wraps napi_get_property
##
## Reads a property from a JavaScript object using a napi_value key.
## `object`: the object napi_value to read from
## `key`:    the property key as a napi_value (string, symbol, etc.)
## `result`: out-pointer; receives the property's napi_value
fn raw_get_property(
    env: NapiEnv,
    object: NapiValue,
    key: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_property")
    return f(env, object, key, result)

fn raw_get_property(
    b: Bindings,
    env: NapiEnv,
    object: NapiValue,
    key: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].get_property).bitcast[
        fn (NapiEnv, NapiValue, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, object, key, result)

## raw_is_array — wraps napi_is_array
##
## Checks whether a JavaScript value is an Array.
## `value`:  the napi_value to check
## `result`: out-pointer to a Bool; receives true if value is an Array
fn raw_is_array(
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_is_array")
    return f(env, value, result)

fn raw_is_array(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].is_array).bitcast[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, value, result)

## raw_get_named_property — wraps napi_get_named_property
##
## Reads a named property from a JavaScript object.
## `object`:   the object napi_value to read from
## `utf8name`: null-terminated UTF-8 property name (must remain alive until return)
## `result`:   out-pointer; receives the property's napi_value
fn raw_get_named_property(
    env: NapiEnv,
    object: NapiValue,
    utf8name: OpaquePointer[ImmutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[ImmutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_named_property")
    return f(env, object, utf8name, result)

fn raw_get_named_property(
    b: Bindings,
    env: NapiEnv,
    object: NapiValue,
    utf8name: OpaquePointer[ImmutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].get_named_property).bitcast[
        fn (NapiEnv, NapiValue, OpaquePointer[ImmutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, object, utf8name, result)

## raw_has_named_property — wraps napi_has_named_property
##
## Checks whether a named property exists on a JavaScript object.
## `object`:   the object napi_value to check
## `utf8name`: null-terminated UTF-8 property name (must remain alive until return)
## `result`:   out-pointer to a Bool; receives true if property exists
fn raw_has_named_property(
    env: NapiEnv,
    object: NapiValue,
    utf8name: OpaquePointer[ImmutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[ImmutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_has_named_property")
    return f(env, object, utf8name, result)

fn raw_has_named_property(
    b: Bindings,
    env: NapiEnv,
    object: NapiValue,
    utf8name: OpaquePointer[ImmutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].has_named_property).bitcast[
        fn (NapiEnv, NapiValue, OpaquePointer[ImmutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, object, utf8name, result)

## raw_call_function — wraps napi_call_function
##
## Calls a JavaScript function value.
## `recv`:   the `this` value for the call (pass undefined for unbound calls)
## `func`:   the napi_value of the function to call
## `argc`:   number of arguments
## `argv`:   pointer to array of napi_value arguments (NULL if argc == 0)
## `result`: out-pointer; receives the return value
fn raw_call_function(
    env: NapiEnv,
    recv: NapiValue,
    func: NapiValue,
    argc: UInt,
    argv: OpaquePointer[ImmutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, NapiValue, UInt, OpaquePointer[ImmutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_call_function")
    return f(env, recv, func, argc, argv, result)

fn raw_call_function(
    b: Bindings,
    env: NapiEnv,
    recv: NapiValue,
    func: NapiValue,
    argc: UInt,
    argv: OpaquePointer[ImmutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].call_function).bitcast[
        fn (NapiEnv, NapiValue, NapiValue, UInt, OpaquePointer[ImmutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, recv, func, argc, argv, result)

## raw_open_handle_scope — wraps napi_open_handle_scope
##
## Creates a new handle scope. All napi_values created within this scope
## are released when the scope is closed. Use in loops that create many
## temporary napi_values to prevent handle exhaustion.
## `result`: out-pointer; receives the new napi_handle_scope
fn raw_open_handle_scope(
    env: NapiEnv,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_open_handle_scope")
    return f(env, result)

fn raw_open_handle_scope(
    b: Bindings,
    env: NapiEnv,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].open_handle_scope).bitcast[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, result)

## raw_close_handle_scope — wraps napi_close_handle_scope
##
## Closes a handle scope, releasing all napi_values created within it.
## Values referenced by objects outside the scope survive (e.g., elements
## already set on an array via napi_set_element).
## `scope`: the handle scope to close (passed by value, not as pointer)
fn raw_close_handle_scope(
    env: NapiEnv,
    scope: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_close_handle_scope")
    return f(env, scope)

fn raw_close_handle_scope(
    b: Bindings,
    env: NapiEnv,
    scope: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].close_handle_scope).bitcast[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, scope)

## raw_create_promise — wraps napi_create_promise
##
## Creates a new JavaScript Promise and its associated deferred handle.
## `deferred`: out-pointer; receives the napi_deferred (used to resolve/reject)
## `promise`:  out-pointer; receives the napi_value of the created Promise
fn raw_create_promise(
    env: NapiEnv,
    deferred: OpaquePointer[MutAnyOrigin],
    promise: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_promise")
    return f(env, deferred, promise)

fn raw_create_promise(
    b: Bindings,
    env: NapiEnv,
    deferred: OpaquePointer[MutAnyOrigin],
    promise: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].create_promise).bitcast[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, deferred, promise)

## raw_resolve_deferred — wraps napi_resolve_deferred
##
## Resolves the promise associated with a deferred handle. The deferred is
## consumed and must not be used again after this call.
## `deferred`:   the napi_deferred handle (passed by value, not pointer)
## `resolution`: the napi_value to resolve the promise with
fn raw_resolve_deferred(
    env: NapiEnv,
    deferred: OpaquePointer[MutAnyOrigin],
    resolution: NapiValue,
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin], NapiValue) -> NapiStatus
    ]("napi_resolve_deferred")
    return f(env, deferred, resolution)

fn raw_resolve_deferred(
    b: Bindings,
    env: NapiEnv,
    deferred: OpaquePointer[MutAnyOrigin],
    resolution: NapiValue,
) -> NapiStatus:
    var f = UnsafePointer(to=b[].resolve_deferred).bitcast[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin], NapiValue) -> NapiStatus
    ]()[]
    return f(env, deferred, resolution)

## raw_reject_deferred — wraps napi_reject_deferred
##
## Rejects the promise associated with a deferred handle. The deferred is
## consumed and must not be used again after this call.
## `deferred`:  the napi_deferred handle (passed by value, not pointer)
## `rejection`: the napi_value to reject the promise with (typically an Error)
fn raw_reject_deferred(
    env: NapiEnv,
    deferred: OpaquePointer[MutAnyOrigin],
    rejection: NapiValue,
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin], NapiValue) -> NapiStatus
    ]("napi_reject_deferred")
    return f(env, deferred, rejection)

fn raw_reject_deferred(
    b: Bindings,
    env: NapiEnv,
    deferred: OpaquePointer[MutAnyOrigin],
    rejection: NapiValue,
) -> NapiStatus:
    var f = UnsafePointer(to=b[].reject_deferred).bitcast[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin], NapiValue) -> NapiStatus
    ]()[]
    return f(env, deferred, rejection)

## raw_create_error — wraps napi_create_error
##
## Creates a new JavaScript Error object (without throwing it). Use when you
## need an Error value (e.g., for promise rejection) rather than setting a
## pending exception.
## `code`:   error code napi_value (pass NapiValue() for no code)
## `msg`:    error message napi_value (must be a JS string)
## `result`: out-pointer; receives the created Error napi_value
fn raw_create_error(
    env: NapiEnv,
    code: NapiValue,
    msg: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_error")
    return f(env, code, msg, result)

fn raw_create_error(
    b: Bindings,
    env: NapiEnv,
    code: NapiValue,
    msg: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].create_error).bitcast[
        fn (NapiEnv, NapiValue, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, code, msg, result)

## raw_create_async_work — wraps napi_create_async_work
##
## Creates an async work item. The execute callback runs on a worker thread
## (MUST NOT call N-API functions). The complete callback runs on the main
## thread after execute finishes.
##
## `async_resource`:      pass NapiValue() (NULL) for default
## `async_resource_name`: a napi_value string identifying this work (for diagnostics)
## `execute`:             worker thread callback: fn(NapiEnv, void*) -> void
## `complete`:            main thread callback: fn(NapiEnv, NapiStatus, void*) -> void
## `data`:                void* pointer shared between execute and complete
## `result`:              out-pointer; receives the napi_async_work handle
fn raw_create_async_work(
    env: NapiEnv,
    async_resource: NapiValue,
    async_resource_name: NapiValue,
    execute: OpaquePointer[MutAnyOrigin],
    complete: OpaquePointer[MutAnyOrigin],
    data: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (
            NapiEnv,
            NapiValue,
            NapiValue,
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
        ) -> NapiStatus
    ]("napi_create_async_work")
    return f(env, async_resource, async_resource_name, execute, complete, data, result)

fn raw_create_async_work(
    b: Bindings,
    env: NapiEnv,
    async_resource: NapiValue,
    async_resource_name: NapiValue,
    execute: OpaquePointer[MutAnyOrigin],
    complete: OpaquePointer[MutAnyOrigin],
    data: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].create_async_work).bitcast[
        fn (
            NapiEnv,
            NapiValue,
            NapiValue,
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
        ) -> NapiStatus
    ]()[]
    return f(env, async_resource, async_resource_name, execute, complete, data, result)

## raw_queue_async_work — wraps napi_queue_async_work
##
## Queues the async work for execution on the Node.js thread pool.
## `work`: the napi_async_work handle from napi_create_async_work
fn raw_queue_async_work(
    env: NapiEnv,
    work: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_queue_async_work")
    return f(env, work)

fn raw_queue_async_work(
    b: Bindings,
    env: NapiEnv,
    work: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].queue_async_work).bitcast[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, work)

## raw_delete_async_work — wraps napi_delete_async_work
##
## Frees the resources associated with an async work item.
## Must be called after the work has completed (typically in the complete
## callback or after it has run).
## `work`: the napi_async_work handle to delete
fn raw_delete_async_work(
    env: NapiEnv,
    work: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_delete_async_work")
    return f(env, work)

fn raw_delete_async_work(
    b: Bindings,
    env: NapiEnv,
    work: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].delete_async_work).bitcast[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, work)

## raw_create_int32 — wraps napi_create_int32
##
## Creates a JavaScript number from a signed 32-bit integer.
fn raw_create_int32(
    env: NapiEnv,
    value: Int32,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, Int32, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_int32")
    return f(env, value, result)

fn raw_create_int32(
    b: Bindings,
    env: NapiEnv,
    value: Int32,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].create_int32).bitcast[
        fn (NapiEnv, Int32, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, value, result)

## raw_get_value_int32 — wraps napi_get_value_int32
##
## Reads a JavaScript number as a signed 32-bit integer (truncates).
fn raw_get_value_int32(
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_value_int32")
    return f(env, value, result)

fn raw_get_value_int32(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].get_value_int32).bitcast[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, value, result)

## raw_create_uint32 — wraps napi_create_uint32
##
## Creates a JavaScript number from an unsigned 32-bit integer.
fn raw_create_uint32(
    env: NapiEnv,
    value: UInt32,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, UInt32, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_uint32")
    return f(env, value, result)

fn raw_create_uint32(
    b: Bindings,
    env: NapiEnv,
    value: UInt32,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].create_uint32).bitcast[
        fn (NapiEnv, UInt32, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, value, result)

## raw_get_value_uint32 — wraps napi_get_value_uint32
##
## Reads a JavaScript number as an unsigned 32-bit integer (truncates).
fn raw_get_value_uint32(
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_value_uint32")
    return f(env, value, result)

fn raw_get_value_uint32(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].get_value_uint32).bitcast[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, value, result)

## raw_create_int64 — wraps napi_create_int64
##
## Creates a JavaScript number from a signed 64-bit integer.
fn raw_create_int64(
    env: NapiEnv,
    value: Int64,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, Int64, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_int64")
    return f(env, value, result)

fn raw_create_int64(
    b: Bindings,
    env: NapiEnv,
    value: Int64,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].create_int64).bitcast[
        fn (NapiEnv, Int64, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, value, result)

## raw_get_value_int64 — wraps napi_get_value_int64
##
## Reads a JavaScript number as a signed 64-bit integer (truncates).
fn raw_get_value_int64(
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_value_int64")
    return f(env, value, result)

fn raw_get_value_int64(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].get_value_int64).bitcast[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, value, result)

## raw_throw_type_error — wraps napi_throw_type_error
##
## Sets a pending JavaScript TypeError exception.
fn raw_throw_type_error(
    env: NapiEnv,
    code: OpaquePointer[ImmutAnyOrigin],
    msg: OpaquePointer[ImmutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, OpaquePointer[ImmutAnyOrigin], OpaquePointer[ImmutAnyOrigin]) -> NapiStatus
    ]("napi_throw_type_error")
    return f(env, code, msg)

fn raw_throw_type_error(
    b: Bindings,
    env: NapiEnv,
    code: OpaquePointer[ImmutAnyOrigin],
    msg: OpaquePointer[ImmutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].throw_type_error).bitcast[
        fn (NapiEnv, OpaquePointer[ImmutAnyOrigin], OpaquePointer[ImmutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, code, msg)

## raw_throw_range_error — wraps napi_throw_range_error
##
## Sets a pending JavaScript RangeError exception.
fn raw_throw_range_error(
    env: NapiEnv,
    code: OpaquePointer[ImmutAnyOrigin],
    msg: OpaquePointer[ImmutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, OpaquePointer[ImmutAnyOrigin], OpaquePointer[ImmutAnyOrigin]) -> NapiStatus
    ]("napi_throw_range_error")
    return f(env, code, msg)

fn raw_throw_range_error(
    b: Bindings,
    env: NapiEnv,
    code: OpaquePointer[ImmutAnyOrigin],
    msg: OpaquePointer[ImmutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].throw_range_error).bitcast[
        fn (NapiEnv, OpaquePointer[ImmutAnyOrigin], OpaquePointer[ImmutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, code, msg)

## raw_create_type_error — wraps napi_create_type_error
##
## Creates a TypeError object (without throwing). For promise rejection.
fn raw_create_type_error(
    env: NapiEnv,
    code: NapiValue,
    msg: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_type_error")
    return f(env, code, msg, result)

fn raw_create_type_error(
    b: Bindings,
    env: NapiEnv,
    code: NapiValue,
    msg: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].create_type_error).bitcast[
        fn (NapiEnv, NapiValue, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, code, msg, result)

## raw_create_range_error — wraps napi_create_range_error
##
## Creates a RangeError object (without throwing). For promise rejection.
fn raw_create_range_error(
    env: NapiEnv,
    code: NapiValue,
    msg: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_range_error")
    return f(env, code, msg, result)

fn raw_create_range_error(
    b: Bindings,
    env: NapiEnv,
    code: NapiValue,
    msg: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].create_range_error).bitcast[
        fn (NapiEnv, NapiValue, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, code, msg, result)

## raw_create_arraybuffer — wraps napi_create_arraybuffer
##
## Creates a new ArrayBuffer with the specified byte length.
## `data_ptr`: out void** — receives pointer to the backing store.
## `result`:   out napi_value* — receives the ArrayBuffer.
fn raw_create_arraybuffer(
    env: NapiEnv,
    byte_length: UInt,
    data_ptr: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, UInt, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_arraybuffer")
    return f(env, byte_length, data_ptr, result)

fn raw_create_arraybuffer(
    b: Bindings,
    env: NapiEnv,
    byte_length: UInt,
    data_ptr: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].create_arraybuffer).bitcast[
        fn (NapiEnv, UInt, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, byte_length, data_ptr, result)

## raw_get_arraybuffer_info — wraps napi_get_arraybuffer_info
##
## Retrieves backing store pointer and byte length of an ArrayBuffer.
fn raw_get_arraybuffer_info(
    env: NapiEnv,
    arraybuffer: NapiValue,
    data_ptr: OpaquePointer[MutAnyOrigin],
    byte_length: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_arraybuffer_info")
    return f(env, arraybuffer, data_ptr, byte_length)

fn raw_get_arraybuffer_info(
    b: Bindings,
    env: NapiEnv,
    arraybuffer: NapiValue,
    data_ptr: OpaquePointer[MutAnyOrigin],
    byte_length: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].get_arraybuffer_info).bitcast[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, arraybuffer, data_ptr, byte_length)

## raw_is_arraybuffer — wraps napi_is_arraybuffer
##
## Checks whether a value is an ArrayBuffer.
fn raw_is_arraybuffer(
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_is_arraybuffer")
    return f(env, value, result)

fn raw_is_arraybuffer(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].is_arraybuffer).bitcast[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, value, result)

## raw_detach_arraybuffer — wraps napi_detach_arraybuffer
fn raw_detach_arraybuffer(
    env: NapiEnv,
    arraybuffer: NapiValue,
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue) -> NapiStatus
    ]("napi_detach_arraybuffer")
    return f(env, arraybuffer)

fn raw_detach_arraybuffer(
    b: Bindings,
    env: NapiEnv,
    arraybuffer: NapiValue,
) -> NapiStatus:
    var f = UnsafePointer(to=b[].detach_arraybuffer).bitcast[
        fn (NapiEnv, NapiValue) -> NapiStatus
    ]()[]
    return f(env, arraybuffer)

## raw_create_buffer — wraps napi_create_buffer
##
## Creates a new Node.js Buffer with uninitialized contents.
## `data_ptr`: out void** — receives the backing store pointer.
fn raw_create_buffer(
    env: NapiEnv,
    length: UInt,
    data_ptr: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, UInt, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_buffer")
    return f(env, length, data_ptr, result)

fn raw_create_buffer(
    b: Bindings,
    env: NapiEnv,
    length: UInt,
    data_ptr: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].create_buffer).bitcast[
        fn (NapiEnv, UInt, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, length, data_ptr, result)

## raw_create_buffer_copy — wraps napi_create_buffer_copy
##
## Creates a new Buffer whose content is a copy of the supplied bytes.
fn raw_create_buffer_copy(
    env: NapiEnv,
    length: UInt,
    data: OpaquePointer[ImmutAnyOrigin],
    data_ptr: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, UInt, OpaquePointer[ImmutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_buffer_copy")
    return f(env, length, data, data_ptr, result)

fn raw_create_buffer_copy(
    b: Bindings,
    env: NapiEnv,
    length: UInt,
    data: OpaquePointer[ImmutAnyOrigin],
    data_ptr: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].create_buffer_copy).bitcast[
        fn (NapiEnv, UInt, OpaquePointer[ImmutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, length, data, data_ptr, result)

## raw_get_buffer_info — wraps napi_get_buffer_info
##
## Retrieves the backing store pointer and byte length of a Buffer.
fn raw_get_buffer_info(
    env: NapiEnv,
    value: NapiValue,
    data_ptr: OpaquePointer[MutAnyOrigin],
    length: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_buffer_info")
    return f(env, value, data_ptr, length)

fn raw_get_buffer_info(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    data_ptr: OpaquePointer[MutAnyOrigin],
    length: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].get_buffer_info).bitcast[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, value, data_ptr, length)

## raw_is_buffer — wraps napi_is_buffer
##
## Checks whether a value is a Node.js Buffer.
fn raw_is_buffer(
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_is_buffer")
    return f(env, value, result)

fn raw_is_buffer(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].is_buffer).bitcast[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, value, result)

## raw_create_typedarray — wraps napi_create_typedarray
##
## Creates a TypedArray view over an existing ArrayBuffer.
## `array_type`:  NAPI_*_ARRAY constant (e.g., NAPI_FLOAT64_ARRAY)
## `length`:      number of elements (NOT bytes)
## `arraybuffer`: the ArrayBuffer napi_value
## `byte_offset`: byte offset into the ArrayBuffer
fn raw_create_typedarray(
    env: NapiEnv,
    array_type: Int32,
    length: UInt,
    arraybuffer: NapiValue,
    byte_offset: UInt,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, Int32, UInt, NapiValue, UInt, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_typedarray")
    return f(env, array_type, length, arraybuffer, byte_offset, result)

fn raw_create_typedarray(
    b: Bindings,
    env: NapiEnv,
    array_type: Int32,
    length: UInt,
    arraybuffer: NapiValue,
    byte_offset: UInt,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].create_typedarray).bitcast[
        fn (NapiEnv, Int32, UInt, NapiValue, UInt, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, array_type, length, arraybuffer, byte_offset, result)

## raw_get_typedarray_info — wraps napi_get_typedarray_info
##
## Retrieves all metadata from a TypedArray. Pass NULL for unused out-params.
fn raw_get_typedarray_info(
    env: NapiEnv,
    typedarray: NapiValue,
    array_type: OpaquePointer[MutAnyOrigin],
    length: OpaquePointer[MutAnyOrigin],
    data: OpaquePointer[MutAnyOrigin],
    arraybuffer: OpaquePointer[MutAnyOrigin],
    byte_offset: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_typedarray_info")
    return f(env, typedarray, array_type, length, data, arraybuffer, byte_offset)

fn raw_get_typedarray_info(
    b: Bindings,
    env: NapiEnv,
    typedarray: NapiValue,
    array_type: OpaquePointer[MutAnyOrigin],
    length: OpaquePointer[MutAnyOrigin],
    data: OpaquePointer[MutAnyOrigin],
    arraybuffer: OpaquePointer[MutAnyOrigin],
    byte_offset: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].get_typedarray_info).bitcast[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, typedarray, array_type, length, data, arraybuffer, byte_offset)

## raw_is_typedarray — wraps napi_is_typedarray
##
## Checks whether a value is a TypedArray (any type).
fn raw_is_typedarray(
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_is_typedarray")
    return f(env, value, result)

fn raw_is_typedarray(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].is_typedarray).bitcast[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, value, result)

## raw_define_class — wraps napi_define_class
##
## Defines a JavaScript class with a native constructor.
## `utf8name`:       class name (null-terminated)
## `length`:         byte length of name (NAPI_AUTO_LENGTH for strlen)
## `constructor`:    napi_callback for `new ClassName()`
## `data`:           optional data (pass NULL)
## `property_count`: number of property descriptors (0 for none)
## `properties`:     array of NapiPropertyDescriptor (NULL if count==0)
## `result`:         out-pointer; receives the constructor napi_value
fn raw_define_class(
    env: NapiEnv,
    utf8name: OpaquePointer[ImmutAnyOrigin],
    length: UInt,
    constructor: OpaquePointer[MutAnyOrigin],
    data: OpaquePointer[MutAnyOrigin],
    property_count: UInt,
    properties: OpaquePointer[ImmutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, OpaquePointer[ImmutAnyOrigin], UInt, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], UInt, OpaquePointer[ImmutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_define_class")
    return f(env, utf8name, length, constructor, data, property_count, properties, result)

fn raw_define_class(
    b: Bindings,
    env: NapiEnv,
    utf8name: OpaquePointer[ImmutAnyOrigin],
    length: UInt,
    constructor: OpaquePointer[MutAnyOrigin],
    data: OpaquePointer[MutAnyOrigin],
    property_count: UInt,
    properties: OpaquePointer[ImmutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].define_class).bitcast[
        fn (NapiEnv, OpaquePointer[ImmutAnyOrigin], UInt, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], UInt, OpaquePointer[ImmutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, utf8name, length, constructor, data, property_count, properties, result)

## raw_wrap — wraps napi_wrap
##
## Associates a heap-allocated native object with a JavaScript object.
## `finalize_cb`: called on GC: fn(env, data, hint) -> void
## `finalize_hint`: pass NULL
## `result`: out napi_ref* (pass NULL to skip creating a reference)
fn raw_wrap(
    env: NapiEnv,
    js_object: NapiValue,
    native_object: OpaquePointer[MutAnyOrigin],
    finalize_cb: OpaquePointer[MutAnyOrigin],
    finalize_hint: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_wrap")
    return f(env, js_object, native_object, finalize_cb, finalize_hint, result)

fn raw_wrap(
    b: Bindings,
    env: NapiEnv,
    js_object: NapiValue,
    native_object: OpaquePointer[MutAnyOrigin],
    finalize_cb: OpaquePointer[MutAnyOrigin],
    finalize_hint: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].wrap).bitcast[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, js_object, native_object, finalize_cb, finalize_hint, result)

## raw_unwrap — wraps napi_unwrap
##
## Retrieves the native pointer previously set via raw_wrap.
fn raw_unwrap(
    env: NapiEnv,
    js_object: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_unwrap")
    return f(env, js_object, result)

fn raw_unwrap(
    b: Bindings,
    env: NapiEnv,
    js_object: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].unwrap).bitcast[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, js_object, result)

## raw_remove_wrap — wraps napi_remove_wrap
##
## Removes the native wrap from a JS object without freeing.
fn raw_remove_wrap(
    env: NapiEnv,
    js_object: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_remove_wrap")
    return f(env, js_object, result)

fn raw_remove_wrap(
    b: Bindings,
    env: NapiEnv,
    js_object: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].remove_wrap).bitcast[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, js_object, result)

## raw_new_instance — wraps napi_new_instance
##
## Calls a constructor function with `new`, returning the new instance.
fn raw_new_instance(
    env: NapiEnv,
    constructor: NapiValue,
    argc: UInt,
    argv: OpaquePointer[ImmutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, UInt, OpaquePointer[ImmutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_new_instance")
    return f(env, constructor, argc, argv, result)

fn raw_new_instance(
    b: Bindings,
    env: NapiEnv,
    constructor: NapiValue,
    argc: UInt,
    argv: OpaquePointer[ImmutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].new_instance).bitcast[
        fn (NapiEnv, NapiValue, UInt, OpaquePointer[ImmutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, constructor, argc, argv, result)

## raw_create_function — wraps napi_create_function
##
## Creates a new JavaScript function from a napi_callback.
## utf8name: null-terminated function name (or NULL)
## length: length of name (NAPI_AUTO_LENGTH to use strlen)
## cb: function pointer to the napi_callback
## data: arbitrary data pointer passed to the callback (or NULL)
fn raw_create_function(
    env: NapiEnv,
    utf8name: OpaquePointer[ImmutAnyOrigin],
    length: UInt,
    cb: OpaquePointer[MutAnyOrigin],
    data: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, OpaquePointer[ImmutAnyOrigin], UInt, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_function")
    return f(env, utf8name, length, cb, data, result)

fn raw_create_function(
    b: Bindings,
    env: NapiEnv,
    utf8name: OpaquePointer[ImmutAnyOrigin],
    length: UInt,
    cb: OpaquePointer[MutAnyOrigin],
    data: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].create_function).bitcast[
        fn (NapiEnv, OpaquePointer[ImmutAnyOrigin], UInt, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, utf8name, length, cb, data, result)

## raw_get_new_target — wraps napi_get_new_target
##
## Returns the new.target value of the current callback.
## If the callback was not called with `new`, result is NULL.
fn raw_get_new_target(
    env: NapiEnv,
    info: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_new_target")
    return f(env, info, result)

fn raw_get_new_target(
    b: Bindings,
    env: NapiEnv,
    info: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].get_new_target).bitcast[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, info, result)

## raw_get_global — wraps napi_get_global
##
## Returns the global object (globalThis).
fn raw_get_global(
    env: NapiEnv,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_global")
    return f(env, result)

fn raw_get_global(
    b: Bindings,
    env: NapiEnv,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].get_global).bitcast[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, result)

## raw_create_reference — wraps napi_create_reference
##
## Creates a persistent reference to a napi_value with an initial refcount.
fn raw_create_reference(
    env: NapiEnv,
    value: NapiValue,
    initial_refcount: UInt32,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, UInt32, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_reference")
    return f(env, value, initial_refcount, result)

fn raw_create_reference(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    initial_refcount: UInt32,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].create_reference).bitcast[
        fn (NapiEnv, NapiValue, UInt32, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, value, initial_refcount, result)

## raw_delete_reference — wraps napi_delete_reference
##
## Deletes a reference. The ref must not be used after this call.
fn raw_delete_reference(
    env: NapiEnv,
    napi_ref: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_delete_reference")
    return f(env, napi_ref)

fn raw_delete_reference(
    b: Bindings,
    env: NapiEnv,
    napi_ref: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].delete_reference).bitcast[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, napi_ref)

## raw_reference_ref — wraps napi_reference_ref
##
## Increments the reference count; returns the new count.
fn raw_reference_ref(
    env: NapiEnv,
    napi_ref: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_reference_ref")
    return f(env, napi_ref, result)

fn raw_reference_ref(
    b: Bindings,
    env: NapiEnv,
    napi_ref: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].reference_ref).bitcast[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, napi_ref, result)

## raw_reference_unref — wraps napi_reference_unref
##
## Decrements the reference count; returns the new count.
fn raw_reference_unref(
    env: NapiEnv,
    napi_ref: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_reference_unref")
    return f(env, napi_ref, result)

fn raw_reference_unref(
    b: Bindings,
    env: NapiEnv,
    napi_ref: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].reference_unref).bitcast[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, napi_ref, result)

## raw_get_reference_value — wraps napi_get_reference_value
##
## Retrieves the napi_value from a reference.
fn raw_get_reference_value(
    env: NapiEnv,
    napi_ref: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_reference_value")
    return f(env, napi_ref, result)

fn raw_get_reference_value(
    b: Bindings,
    env: NapiEnv,
    napi_ref: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].get_reference_value).bitcast[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, napi_ref, result)

## raw_open_escapable_handle_scope — wraps napi_open_escapable_handle_scope
fn raw_open_escapable_handle_scope(
    env: NapiEnv,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_open_escapable_handle_scope")
    return f(env, result)

fn raw_open_escapable_handle_scope(
    b: Bindings,
    env: NapiEnv,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].open_escapable_handle_scope).bitcast[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, result)

## raw_close_escapable_handle_scope — wraps napi_close_escapable_handle_scope
fn raw_close_escapable_handle_scope(
    env: NapiEnv,
    scope: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_close_escapable_handle_scope")
    return f(env, scope)

fn raw_close_escapable_handle_scope(
    b: Bindings,
    env: NapiEnv,
    scope: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].close_escapable_handle_scope).bitcast[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, scope)

## raw_escape_handle — wraps napi_escape_handle
##
## Promotes a value from an escapable handle scope to the outer scope.
## Can only be called ONCE per escapable scope.
fn raw_escape_handle(
    env: NapiEnv,
    scope: OpaquePointer[MutAnyOrigin],
    escapee: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin], NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_escape_handle")
    return f(env, scope, escapee, result)

fn raw_escape_handle(
    b: Bindings,
    env: NapiEnv,
    scope: OpaquePointer[MutAnyOrigin],
    escapee: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].escape_handle).bitcast[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin], NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, scope, escapee, result)

## raw_create_bigint_int64 — wraps napi_create_bigint_int64
fn raw_create_bigint_int64(
    env: NapiEnv,
    value: Int64,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, Int64, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_bigint_int64")
    return f(env, value, result)

fn raw_create_bigint_int64(
    b: Bindings,
    env: NapiEnv,
    value: Int64,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].create_bigint_int64).bitcast[
        fn (NapiEnv, Int64, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, value, result)

## raw_create_bigint_uint64 — wraps napi_create_bigint_uint64
fn raw_create_bigint_uint64(
    env: NapiEnv,
    value: UInt64,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, UInt64, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_bigint_uint64")
    return f(env, value, result)

fn raw_create_bigint_uint64(
    b: Bindings,
    env: NapiEnv,
    value: UInt64,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].create_bigint_uint64).bitcast[
        fn (NapiEnv, UInt64, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, value, result)

## raw_get_value_bigint_int64 — wraps napi_get_value_bigint_int64
##
## Extra out-param `lossless` indicates if the value fits in Int64.
fn raw_get_value_bigint_int64(
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
    lossless: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_value_bigint_int64")
    return f(env, value, result, lossless)

fn raw_get_value_bigint_int64(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
    lossless: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].get_value_bigint_int64).bitcast[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, value, result, lossless)

## raw_get_value_bigint_uint64 — wraps napi_get_value_bigint_uint64
fn raw_get_value_bigint_uint64(
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
    lossless: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_value_bigint_uint64")
    return f(env, value, result, lossless)

fn raw_get_value_bigint_uint64(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
    lossless: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].get_value_bigint_uint64).bitcast[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, value, result, lossless)

## raw_create_date — wraps napi_create_date
fn raw_create_date(
    env: NapiEnv,
    time: Float64,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, Float64, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_date")
    return f(env, time, result)

fn raw_create_date(
    b: Bindings,
    env: NapiEnv,
    time: Float64,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].create_date).bitcast[
        fn (NapiEnv, Float64, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, time, result)

## raw_get_date_value — wraps napi_get_date_value
fn raw_get_date_value(
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_date_value")
    return f(env, value, result)

fn raw_get_date_value(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].get_date_value).bitcast[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, value, result)

## raw_is_date — wraps napi_is_date
fn raw_is_date(
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_is_date")
    return f(env, value, result)

fn raw_is_date(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].is_date).bitcast[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, value, result)

## raw_create_symbol — wraps napi_create_symbol (node_api.h — napi_ prefix)
fn raw_create_symbol(
    env: NapiEnv,
    description: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_symbol")
    return f(env, description, result)

fn raw_create_symbol(
    b: Bindings,
    env: NapiEnv,
    description: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].create_symbol).bitcast[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, description, result)

## raw_symbol_for — wraps node_api_symbol_for (note: node_api_ prefix)
##
## Returns the global Symbol for the given key (like Symbol.for()).
fn raw_symbol_for(
    env: NapiEnv,
    description: OpaquePointer[ImmutAnyOrigin],
    length: UInt,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, OpaquePointer[ImmutAnyOrigin], UInt, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("node_api_symbol_for")
    return f(env, description, length, result)

fn raw_symbol_for(
    b: Bindings,
    env: NapiEnv,
    description: OpaquePointer[ImmutAnyOrigin],
    length: UInt,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].symbol_for).bitcast[
        fn (NapiEnv, OpaquePointer[ImmutAnyOrigin], UInt, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, description, length, result)

## raw_get_property_names — wraps napi_get_property_names
##
## Returns an array of the object's enumerable property names (including
## inherited). For own-only enumerable string keys (Object.keys behavior),
## use raw_get_all_property_names with key_mode=1, key_filter=18.
fn raw_get_property_names(
    env: NapiEnv,
    object: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_property_names")
    return f(env, object, result)

fn raw_get_property_names(
    b: Bindings,
    env: NapiEnv,
    object: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].get_property_names).bitcast[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, object, result)

## raw_get_all_property_names — wraps napi_get_all_property_names
##
## Returns property names with filtering control. Parameters:
## `key_mode`:       0 = napi_key_include_prototypes, 1 = napi_key_own_only
## `key_filter`:     bitmask: 0=all, 1=writable, 2=enumerable, 4=configurable, 8=skip_strings, 16=skip_symbols
## `key_conversion`: 0 = keep_numbers, 1 = numbers_to_strings
fn raw_get_all_property_names(
    env: NapiEnv,
    object: NapiValue,
    key_mode: Int32,
    key_filter: Int32,
    key_conversion: Int32,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, Int32, Int32, Int32, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_all_property_names")
    return f(env, object, key_mode, key_filter, key_conversion, result)

fn raw_get_all_property_names(
    b: Bindings,
    env: NapiEnv,
    object: NapiValue,
    key_mode: Int32,
    key_filter: Int32,
    key_conversion: Int32,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].get_all_property_names).bitcast[
        fn (NapiEnv, NapiValue, Int32, Int32, Int32, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, object, key_mode, key_filter, key_conversion, result)

## raw_has_own_property — wraps napi_has_own_property
##
## Checks whether the object has the specified key as an own (non-inherited)
## property. `key` must be a string or symbol napi_value.
fn raw_has_own_property(
    env: NapiEnv,
    object: NapiValue,
    key: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_has_own_property")
    return f(env, object, key, result)

fn raw_has_own_property(
    b: Bindings,
    env: NapiEnv,
    object: NapiValue,
    key: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].has_own_property).bitcast[
        fn (NapiEnv, NapiValue, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, object, key, result)

## raw_delete_property — wraps napi_delete_property
##
## Deletes a property from an object by key (napi_value string or symbol).
## `result` receives a bool indicating whether the property was deleted.
fn raw_delete_property(
    env: NapiEnv,
    object: NapiValue,
    key: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_delete_property")
    return f(env, object, key, result)

fn raw_delete_property(
    b: Bindings,
    env: NapiEnv,
    object: NapiValue,
    key: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].delete_property).bitcast[
        fn (NapiEnv, NapiValue, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, object, key, result)

## raw_strict_equals — wraps napi_strict_equals
##
## Checks strict equality (===) between two values.
fn raw_strict_equals(
    env: NapiEnv,
    lhs: NapiValue,
    rhs: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_strict_equals")
    return f(env, lhs, rhs, result)

fn raw_strict_equals(
    b: Bindings,
    env: NapiEnv,
    lhs: NapiValue,
    rhs: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].strict_equals).bitcast[
        fn (NapiEnv, NapiValue, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, lhs, rhs, result)

## raw_instanceof — wraps napi_instanceof
##
## Checks if `object` is an instance of `constructor`.
fn raw_instanceof(
    env: NapiEnv,
    object: NapiValue,
    constructor: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_instanceof")
    return f(env, object, constructor, result)

fn raw_instanceof(
    b: Bindings,
    env: NapiEnv,
    object: NapiValue,
    constructor: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].instanceof_).bitcast[
        fn (NapiEnv, NapiValue, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, object, constructor, result)

## raw_object_freeze — wraps napi_object_freeze (N-API v8+)
##
## Freezes the object, preventing modifications to its properties.
fn raw_object_freeze(
    env: NapiEnv,
    object: NapiValue,
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue) -> NapiStatus
    ]("napi_object_freeze")
    return f(env, object)

fn raw_object_freeze(
    b: Bindings,
    env: NapiEnv,
    object: NapiValue,
) -> NapiStatus:
    var f = UnsafePointer(to=b[].object_freeze).bitcast[
        fn (NapiEnv, NapiValue) -> NapiStatus
    ]()[]
    return f(env, object)

## raw_object_seal — wraps napi_object_seal (N-API v8+)
##
## Seals the object, preventing addition/deletion of properties.
fn raw_object_seal(
    env: NapiEnv,
    object: NapiValue,
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue) -> NapiStatus
    ]("napi_object_seal")
    return f(env, object)

fn raw_object_seal(
    b: Bindings,
    env: NapiEnv,
    object: NapiValue,
) -> NapiStatus:
    var f = UnsafePointer(to=b[].object_seal).bitcast[
        fn (NapiEnv, NapiValue) -> NapiStatus
    ]()[]
    return f(env, object)

## raw_has_element — wraps napi_has_element
##
## Checks whether an element exists at the given index.
fn raw_has_element(
    env: NapiEnv,
    object: NapiValue,
    index: UInt32,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, UInt32, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_has_element")
    return f(env, object, index, result)

fn raw_has_element(
    b: Bindings,
    env: NapiEnv,
    object: NapiValue,
    index: UInt32,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].has_element).bitcast[
        fn (NapiEnv, NapiValue, UInt32, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, object, index, result)

## raw_delete_element — wraps napi_delete_element
##
## Deletes the element at the given index (makes the array sparse).
fn raw_delete_element(
    env: NapiEnv,
    object: NapiValue,
    index: UInt32,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, UInt32, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_delete_element")
    return f(env, object, index, result)

fn raw_delete_element(
    b: Bindings,
    env: NapiEnv,
    object: NapiValue,
    index: UInt32,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].delete_element).bitcast[
        fn (NapiEnv, NapiValue, UInt32, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, object, index, result)

## raw_get_prototype — wraps napi_get_prototype
##
## Returns the prototype of the given object.
fn raw_get_prototype(
    env: NapiEnv,
    object: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_prototype")
    return f(env, object, result)

fn raw_get_prototype(
    b: Bindings,
    env: NapiEnv,
    object: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].get_prototype).bitcast[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, object, result)

## raw_create_threadsafe_function — wraps napi_create_threadsafe_function
##
## Creates a thread-safe function that can be called from any thread.
## `func`:                 JS function to invoke (or NULL if call_js_cb handles it)
## `async_resource`:       optional async resource (NULL)
## `async_resource_name`:  napi_value string for async diagnostics
## `max_queue_size`:       0 = unlimited
## `initial_thread_count`: number of initial acquires (typically 1)
## `thread_finalize_data`: data passed to thread_finalize_cb (NULL)
## `thread_finalize_cb`:   cleanup callback when TSFN is destroyed (NULL)
## `context`:              arbitrary context pointer (NULL)
## `call_js_cb`:           fn(env, js_callback, context, data) — main thread callback
## `result`:               out-pointer; receives the napi_threadsafe_function
fn raw_create_threadsafe_function(
    env: NapiEnv,
    func: NapiValue,
    async_resource: NapiValue,
    async_resource_name: NapiValue,
    max_queue_size: UInt,
    initial_thread_count: UInt,
    thread_finalize_data: OpaquePointer[MutAnyOrigin],
    thread_finalize_cb: OpaquePointer[MutAnyOrigin],
    context: OpaquePointer[MutAnyOrigin],
    call_js_cb: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, NapiValue, NapiValue, UInt, UInt, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_threadsafe_function")
    return f(env, func, async_resource, async_resource_name,
             max_queue_size, initial_thread_count,
             thread_finalize_data, thread_finalize_cb,
             context, call_js_cb, result)

fn raw_create_threadsafe_function(
    b: Bindings,
    env: NapiEnv,
    func: NapiValue,
    async_resource: NapiValue,
    async_resource_name: NapiValue,
    max_queue_size: UInt,
    initial_thread_count: UInt,
    thread_finalize_data: OpaquePointer[MutAnyOrigin],
    thread_finalize_cb: OpaquePointer[MutAnyOrigin],
    context: OpaquePointer[MutAnyOrigin],
    call_js_cb: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].create_threadsafe_function).bitcast[
        fn (NapiEnv, NapiValue, NapiValue, NapiValue, UInt, UInt, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, func, async_resource, async_resource_name,
             max_queue_size, initial_thread_count,
             thread_finalize_data, thread_finalize_cb,
             context, call_js_cb, result)

## raw_call_threadsafe_function — wraps napi_call_threadsafe_function
##
## Queues a call to the JS function from ANY thread.
## NOTE: Unlike all other raw_* functions, this does NOT take env — it is
## designed to be called from non-JS threads.
## `func`:       the napi_threadsafe_function handle
## `data`:       arbitrary data pointer passed to call_js_cb
## `is_blocking`: NAPI_TSFN_BLOCKING (1) or NAPI_TSFN_NONBLOCKING (0)
fn raw_call_threadsafe_function(
    func: OpaquePointer[MutAnyOrigin],
    data: OpaquePointer[MutAnyOrigin],
    is_blocking: Int32,
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], Int32) -> NapiStatus
    ]("napi_call_threadsafe_function")
    return f(func, data, is_blocking)

fn raw_call_threadsafe_function(
    b: Bindings,
    func: OpaquePointer[MutAnyOrigin],
    data: OpaquePointer[MutAnyOrigin],
    is_blocking: Int32,
) -> NapiStatus:
    var f = UnsafePointer(to=b[].call_threadsafe_function).bitcast[
        fn (OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], Int32) -> NapiStatus
    ]()[]
    return f(func, data, is_blocking)

## raw_acquire_threadsafe_function — wraps napi_acquire_threadsafe_function
##
## Increments the thread reference count. Must be called from a new thread
## before it starts calling the TSFN (unless it is the initial thread).
fn raw_acquire_threadsafe_function(
    func: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_acquire_threadsafe_function")
    return f(func)

fn raw_acquire_threadsafe_function(
    b: Bindings,
    func: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].acquire_threadsafe_function).bitcast[
        fn (OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(func)

## raw_release_threadsafe_function — wraps napi_release_threadsafe_function
##
## Decrements the thread reference count. When the count reaches 0, the TSFN
## is destroyed.
## `mode`: NAPI_TSFN_RELEASE (0) or NAPI_TSFN_ABORT (1)
fn raw_release_threadsafe_function(
    func: OpaquePointer[MutAnyOrigin],
    mode: Int32,
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (OpaquePointer[MutAnyOrigin], Int32) -> NapiStatus
    ]("napi_release_threadsafe_function")
    return f(func, mode)

fn raw_release_threadsafe_function(
    b: Bindings,
    func: OpaquePointer[MutAnyOrigin],
    mode: Int32,
) -> NapiStatus:
    var f = UnsafePointer(to=b[].release_threadsafe_function).bitcast[
        fn (OpaquePointer[MutAnyOrigin], Int32) -> NapiStatus
    ]()[]
    return f(func, mode)

# ---------------------------------------------------------------------------
# External data
# ---------------------------------------------------------------------------

## raw_create_external — wraps napi_create_external
##
## Creates a JavaScript external value wrapping an opaque native pointer.
## The finalize_cb (if non-null) is called when the external is garbage collected.
## finalize_cb signature: fn(env, finalize_data, finalize_hint)
fn raw_create_external(
    env: NapiEnv,
    data: OpaquePointer[MutAnyOrigin],
    finalize_cb: OpaquePointer[MutAnyOrigin],
    finalize_hint: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_external")
    return f(env, data, finalize_cb, finalize_hint, result)

fn raw_create_external(
    b: Bindings,
    env: NapiEnv,
    data: OpaquePointer[MutAnyOrigin],
    finalize_cb: OpaquePointer[MutAnyOrigin],
    finalize_hint: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].create_external).bitcast[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, data, finalize_cb, finalize_hint, result)

## raw_get_value_external — wraps napi_get_value_external
##
## Retrieves the opaque native pointer from an external value.
fn raw_get_value_external(
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_value_external")
    return f(env, value, result)

fn raw_get_value_external(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].get_value_external).bitcast[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, value, result)

# ---------------------------------------------------------------------------
# Type coercion
# ---------------------------------------------------------------------------

## raw_get_version — wraps napi_get_version
##
## Returns the highest N-API version supported by this runtime.
fn raw_get_version(
    env: NapiEnv,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_version")
    return f(env, result)

fn raw_get_version(
    b: Bindings,
    env: NapiEnv,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].get_version).bitcast[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, result)

## raw_get_node_version — wraps napi_get_node_version
##
## Writes a pointer to a statically-allocated napi_node_version struct.
## The result is a napi_node_version** (double pointer).
fn raw_get_node_version(
    env: NapiEnv,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_node_version")
    return f(env, result)

fn raw_get_node_version(
    b: Bindings,
    env: NapiEnv,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].get_node_version).bitcast[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, result)

## raw_set_property — wraps napi_set_property
##
## Sets a property on an object using a napi_value key (string, symbol, etc.).
## Unlike raw_set_named_property which takes a C string key.
fn raw_set_property(
    env: NapiEnv,
    object: NapiValue,
    key: NapiValue,
    value: NapiValue,
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, NapiValue, NapiValue) -> NapiStatus
    ]("napi_set_property")
    return f(env, object, key, value)

fn raw_set_property(
    b: Bindings,
    env: NapiEnv,
    object: NapiValue,
    key: NapiValue,
    value: NapiValue,
) -> NapiStatus:
    var f = UnsafePointer(to=b[].set_property).bitcast[
        fn (NapiEnv, NapiValue, NapiValue, NapiValue) -> NapiStatus
    ]()[]
    return f(env, object, key, value)

## raw_has_property — wraps napi_has_property
##
## Checks whether a property exists on an object using a napi_value key.
## Walks the prototype chain (unlike has_own_property which checks own only).
fn raw_has_property(
    env: NapiEnv,
    object: NapiValue,
    key: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_has_property")
    return f(env, object, key, result)

fn raw_has_property(
    b: Bindings,
    env: NapiEnv,
    object: NapiValue,
    key: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].has_property).bitcast[
        fn (NapiEnv, NapiValue, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, object, key, result)

## raw_throw — wraps napi_throw
##
## Throws any JavaScript value as an exception. Unlike napi_throw_error which
## creates a new Error from a string, this throws an arbitrary value (string,
## number, object, Error instance, null, undefined, etc.).
fn raw_throw(
    env: NapiEnv,
    error: NapiValue,
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue) -> NapiStatus
    ]("napi_throw")
    return f(env, error)

fn raw_throw(
    b: Bindings,
    env: NapiEnv,
    error: NapiValue,
) -> NapiStatus:
    var f = UnsafePointer(to=b[].throw_).bitcast[
        fn (NapiEnv, NapiValue) -> NapiStatus
    ]()[]
    return f(env, error)

## raw_is_exception_pending — wraps napi_is_exception_pending
##
## Returns whether a JavaScript exception is currently pending.
fn raw_is_exception_pending(
    env: NapiEnv,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_is_exception_pending")
    return f(env, result)

fn raw_is_exception_pending(
    b: Bindings,
    env: NapiEnv,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].is_exception_pending).bitcast[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, result)

## raw_get_and_clear_last_exception — wraps napi_get_and_clear_last_exception
##
## Retrieves the pending JavaScript exception and clears it, allowing
## native code to inspect or handle the error without re-throwing.
fn raw_get_and_clear_last_exception(
    env: NapiEnv,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_and_clear_last_exception")
    return f(env, result)

fn raw_get_and_clear_last_exception(
    b: Bindings,
    env: NapiEnv,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].get_and_clear_last_exception).bitcast[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, result)

## raw_coerce_to_bool — wraps napi_coerce_to_bool
##
## Equivalent to Boolean(value) in JavaScript.
fn raw_coerce_to_bool(
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_coerce_to_bool")
    return f(env, value, result)

fn raw_coerce_to_bool(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].coerce_to_bool).bitcast[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, value, result)

## raw_coerce_to_number — wraps napi_coerce_to_number
##
## Equivalent to Number(value) in JavaScript.
## Throws TypeError on Symbol values.
fn raw_coerce_to_number(
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_coerce_to_number")
    return f(env, value, result)

fn raw_coerce_to_number(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].coerce_to_number).bitcast[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, value, result)

## raw_coerce_to_string — wraps napi_coerce_to_string
##
## Equivalent to String(value) in JavaScript.
## Throws TypeError on Symbol values.
fn raw_coerce_to_string(
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_coerce_to_string")
    return f(env, value, result)

fn raw_coerce_to_string(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].coerce_to_string).bitcast[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, value, result)

## raw_coerce_to_object — wraps napi_coerce_to_object
##
## Equivalent to Object(value) in JavaScript.
## Wraps primitives in their object wrappers.
fn raw_coerce_to_object(
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_coerce_to_object")
    return f(env, value, result)

fn raw_coerce_to_object(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].coerce_to_object).bitcast[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, value, result)

## raw_create_dataview — wraps napi_create_dataview
##
## Creates a DataView over an existing ArrayBuffer.
## byte_offset + byte_length must not exceed the ArrayBuffer's size.
fn raw_create_dataview(
    env: NapiEnv,
    byte_length: UInt,
    arraybuffer: NapiValue,
    byte_offset: UInt,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, UInt, NapiValue, UInt, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_dataview")
    return f(env, byte_length, arraybuffer, byte_offset, result)

fn raw_create_dataview(
    b: Bindings,
    env: NapiEnv,
    byte_length: UInt,
    arraybuffer: NapiValue,
    byte_offset: UInt,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].create_dataview).bitcast[
        fn (NapiEnv, UInt, NapiValue, UInt, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, byte_length, arraybuffer, byte_offset, result)

## raw_get_dataview_info — wraps napi_get_dataview_info
##
## Retrieves DataView properties: byte_length, data pointer, arraybuffer, byte_offset.
## Any out-param can be NULL (OpaquePointer()) to skip that field.
fn raw_get_dataview_info(
    env: NapiEnv,
    dataview: NapiValue,
    byte_length: OpaquePointer[MutAnyOrigin],
    data: OpaquePointer[MutAnyOrigin],
    arraybuffer: OpaquePointer[MutAnyOrigin],
    byte_offset: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue,
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_dataview_info")
    return f(env, dataview, byte_length, data, arraybuffer, byte_offset)

fn raw_get_dataview_info(
    b: Bindings,
    env: NapiEnv,
    dataview: NapiValue,
    byte_length: OpaquePointer[MutAnyOrigin],
    data: OpaquePointer[MutAnyOrigin],
    arraybuffer: OpaquePointer[MutAnyOrigin],
    byte_offset: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].get_dataview_info).bitcast[
        fn (NapiEnv, NapiValue,
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, dataview, byte_length, data, arraybuffer, byte_offset)

## raw_is_dataview — wraps napi_is_dataview
##
## Checks whether a value is a DataView.
fn raw_is_dataview(
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_is_dataview")
    return f(env, value, result)

fn raw_is_dataview(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].is_dataview).bitcast[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, value, result)

## raw_create_bigint_words — wraps napi_create_bigint_words
##
## Creates an arbitrary-precision BigInt from an array of 64-bit words.
## sign_bit: 0 = positive, 1 = negative
## words: pointer to array of uint64_t in little-endian word order
fn raw_create_bigint_words(
    env: NapiEnv,
    sign_bit: Int32,
    word_count: UInt,
    words: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, Int32, UInt, OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_bigint_words")
    return f(env, sign_bit, word_count, words, result)

fn raw_create_bigint_words(
    b: Bindings,
    env: NapiEnv,
    sign_bit: Int32,
    word_count: UInt,
    words: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].create_bigint_words).bitcast[
        fn (NapiEnv, Int32, UInt, OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, sign_bit, word_count, words, result)

## raw_get_value_bigint_words — wraps napi_get_value_bigint_words
##
## Extracts sign and 64-bit words from a BigInt.
## Two-phase pattern: call with words=NULL to get word_count, then allocate and call again.
fn raw_get_value_bigint_words(
    env: NapiEnv,
    value: NapiValue,
    sign_bit: OpaquePointer[MutAnyOrigin],
    word_count: OpaquePointer[MutAnyOrigin],
    words: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue,
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_value_bigint_words")
    return f(env, value, sign_bit, word_count, words)

fn raw_get_value_bigint_words(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    sign_bit: OpaquePointer[MutAnyOrigin],
    word_count: OpaquePointer[MutAnyOrigin],
    words: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].get_value_bigint_words).bitcast[
        fn (NapiEnv, NapiValue,
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, value, sign_bit, word_count, words)

## raw_add_finalizer — wraps napi_add_finalizer
##
## Attaches a GC finalizer to any JS object (not just wrapped objects).
## Can be called multiple times on the same object.
## result: optional napi_ref* out-param (pass NULL to skip)
fn raw_add_finalizer(
    env: NapiEnv,
    js_object: NapiValue,
    native_object: OpaquePointer[MutAnyOrigin],
    finalize_cb: OpaquePointer[MutAnyOrigin],
    finalize_hint: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue,
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_add_finalizer")
    return f(env, js_object, native_object, finalize_cb, finalize_hint, result)

fn raw_add_finalizer(
    b: Bindings,
    env: NapiEnv,
    js_object: NapiValue,
    native_object: OpaquePointer[MutAnyOrigin],
    finalize_cb: OpaquePointer[MutAnyOrigin],
    finalize_hint: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].add_finalizer).bitcast[
        fn (NapiEnv, NapiValue,
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, js_object, native_object, finalize_cb, finalize_hint, result)

## raw_create_external_arraybuffer — wraps napi_create_external_arraybuffer
##
## Creates an ArrayBuffer backed by existing native memory (zero-copy).
## The finalize_cb is called when the ArrayBuffer is GC'd to free the memory.
fn raw_create_external_arraybuffer(
    env: NapiEnv,
    external_data: OpaquePointer[MutAnyOrigin],
    byte_length: UInt,
    finalize_cb: OpaquePointer[MutAnyOrigin],
    finalize_hint: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv,
            OpaquePointer[MutAnyOrigin], UInt,
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_external_arraybuffer")
    return f(env, external_data, byte_length, finalize_cb, finalize_hint, result)

fn raw_create_external_arraybuffer(
    b: Bindings,
    env: NapiEnv,
    external_data: OpaquePointer[MutAnyOrigin],
    byte_length: UInt,
    finalize_cb: OpaquePointer[MutAnyOrigin],
    finalize_hint: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].create_external_arraybuffer).bitcast[
        fn (NapiEnv,
            OpaquePointer[MutAnyOrigin], UInt,
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, external_data, byte_length, finalize_cb, finalize_hint, result)

## raw_set_instance_data — wraps napi_set_instance_data
##
## Sets per-environment singleton data with an optional finalizer.
fn raw_set_instance_data(
    env: NapiEnv,
    data: OpaquePointer[MutAnyOrigin],
    finalize_cb: OpaquePointer[MutAnyOrigin],
    finalize_hint: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_set_instance_data")
    return f(env, data, finalize_cb, finalize_hint)

fn raw_set_instance_data(
    b: Bindings,
    env: NapiEnv,
    data: OpaquePointer[MutAnyOrigin],
    finalize_cb: OpaquePointer[MutAnyOrigin],
    finalize_hint: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].set_instance_data).bitcast[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, data, finalize_cb, finalize_hint)

## raw_get_instance_data — wraps napi_get_instance_data
##
## Retrieves per-environment singleton data. Returns NULL if not set.
fn raw_get_instance_data(
    env: NapiEnv,
    data: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_instance_data")
    return f(env, data)

fn raw_get_instance_data(
    b: Bindings,
    env: NapiEnv,
    data: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].get_instance_data).bitcast[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, data)

## raw_add_env_cleanup_hook — wraps napi_add_env_cleanup_hook
##
## Registers a cleanup function called during env teardown.
## fun signature: fn(void*) — NOT a napi_callback.
fn raw_add_env_cleanup_hook(
    env: NapiEnv,
    fun: OpaquePointer[MutAnyOrigin],
    arg: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_add_env_cleanup_hook")
    return f(env, fun, arg)

fn raw_add_env_cleanup_hook(
    b: Bindings,
    env: NapiEnv,
    fun: OpaquePointer[MutAnyOrigin],
    arg: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].add_env_cleanup_hook).bitcast[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, fun, arg)

## raw_remove_env_cleanup_hook — wraps napi_remove_env_cleanup_hook
##
## Unregisters a previously registered cleanup hook.
fn raw_remove_env_cleanup_hook(
    env: NapiEnv,
    fun: OpaquePointer[MutAnyOrigin],
    arg: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_remove_env_cleanup_hook")
    return f(env, fun, arg)

fn raw_remove_env_cleanup_hook(
    b: Bindings,
    env: NapiEnv,
    fun: OpaquePointer[MutAnyOrigin],
    arg: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].remove_env_cleanup_hook).bitcast[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, fun, arg)

## raw_cancel_async_work — wraps napi_cancel_async_work
##
## Attempts to cancel a queued async work item.
## Returns napi_generic_failure if the worker has already started.
fn raw_cancel_async_work(
    env: NapiEnv,
    work: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_cancel_async_work")
    return f(env, work)

fn raw_cancel_async_work(
    b: Bindings,
    env: NapiEnv,
    work: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].cancel_async_work).bitcast[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, work)

## raw_is_error — wraps napi_is_error
##
## Checks whether a JavaScript value is an Error object.
## `value`:  the napi_value to check
## `result`: out-pointer; receives a Bool (true if value is an Error)
fn raw_is_error(
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_is_error")
    return f(env, value, result)

fn raw_is_error(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].is_error).bitcast[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, value, result)

## raw_adjust_external_memory — wraps napi_adjust_external_memory
##
## Tells V8 about native memory allocations so the GC can schedule appropriately.
## `change_in_bytes`: amount of memory allocated (positive) or freed (negative)
## `result`:          out-pointer; receives the adjusted value (Int64)
fn raw_adjust_external_memory(
    env: NapiEnv,
    change_in_bytes: Int64,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, Int64, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_adjust_external_memory")
    return f(env, change_in_bytes, result)

fn raw_adjust_external_memory(
    b: Bindings,
    env: NapiEnv,
    change_in_bytes: Int64,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].adjust_external_memory).bitcast[
        fn (NapiEnv, Int64, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, change_in_bytes, result)

## raw_run_script — wraps napi_run_script
##
## Evaluates a JavaScript string (equivalent to eval()).
## `script`: a napi_value containing the JS source string
## `result`: out-pointer; receives the evaluation result napi_value
fn raw_run_script(
    env: NapiEnv,
    script: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_run_script")
    return f(env, script, result)

fn raw_run_script(
    b: Bindings,
    env: NapiEnv,
    script: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].run_script).bitcast[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, script, result)

## raw_throw_syntax_error — wraps node_api_throw_syntax_error (N-API v9)
##
## Sets a pending JavaScript SyntaxError exception.
## Note: uses node_api_ prefix (not napi_).
fn raw_throw_syntax_error(
    env: NapiEnv,
    code: OpaquePointer[ImmutAnyOrigin],
    msg: OpaquePointer[ImmutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, OpaquePointer[ImmutAnyOrigin], OpaquePointer[ImmutAnyOrigin]) -> NapiStatus
    ]("node_api_throw_syntax_error")
    return f(env, code, msg)

fn raw_throw_syntax_error(
    b: Bindings,
    env: NapiEnv,
    code: OpaquePointer[ImmutAnyOrigin],
    msg: OpaquePointer[ImmutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].throw_syntax_error).bitcast[
        fn (NapiEnv, OpaquePointer[ImmutAnyOrigin], OpaquePointer[ImmutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, code, msg)

## raw_create_syntax_error — wraps node_api_create_syntax_error (N-API v9)
##
## Creates a SyntaxError object without throwing it.
fn raw_create_syntax_error(
    env: NapiEnv,
    code: NapiValue,
    msg: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("node_api_create_syntax_error")
    return f(env, code, msg, result)

fn raw_create_syntax_error(
    b: Bindings,
    env: NapiEnv,
    code: NapiValue,
    msg: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].create_syntax_error).bitcast[
        fn (NapiEnv, NapiValue, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, code, msg, result)

## raw_is_detached_arraybuffer — wraps napi_is_detached_arraybuffer (N-API v7)
##
## Checks whether an ArrayBuffer has been detached.
fn raw_is_detached_arraybuffer(
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_is_detached_arraybuffer")
    return f(env, value, result)

fn raw_is_detached_arraybuffer(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].is_detached_arraybuffer).bitcast[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, value, result)

## raw_fatal_exception — wraps napi_fatal_exception
##
## Triggers an uncaughtException in Node.js. The error must be an Error object.
fn raw_fatal_exception(
    env: NapiEnv,
    err: NapiValue,
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue) -> NapiStatus
    ]("napi_fatal_exception")
    return f(env, err)

fn raw_fatal_exception(
    b: Bindings,
    env: NapiEnv,
    err: NapiValue,
) -> NapiStatus:
    var f = UnsafePointer(to=b[].fatal_exception).bitcast[
        fn (NapiEnv, NapiValue) -> NapiStatus
    ]()[]
    return f(env, err)

## raw_type_tag_object — wraps napi_type_tag_object (N-API v8)
##
## Associates a UUID-like type tag with a JS object for later checking.
## `type_tag`: pointer to a struct { lower: UInt64, upper: UInt64 }
fn raw_type_tag_object(
    env: NapiEnv,
    value: NapiValue,
    type_tag: OpaquePointer[ImmutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[ImmutAnyOrigin]) -> NapiStatus
    ]("napi_type_tag_object")
    return f(env, value, type_tag)

fn raw_type_tag_object(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    type_tag: OpaquePointer[ImmutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].type_tag_object).bitcast[
        fn (NapiEnv, NapiValue, OpaquePointer[ImmutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, value, type_tag)

## raw_check_object_type_tag — wraps napi_check_object_type_tag (N-API v8)
##
## Checks whether an object has the given type tag.
fn raw_check_object_type_tag(
    env: NapiEnv,
    value: NapiValue,
    type_tag: OpaquePointer[ImmutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[ImmutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_check_object_type_tag")
    return f(env, value, type_tag, result)

fn raw_check_object_type_tag(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    type_tag: OpaquePointer[ImmutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].check_object_type_tag).bitcast[
        fn (NapiEnv, NapiValue, OpaquePointer[ImmutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, value, type_tag, result)

## raw_add_async_cleanup_hook — wraps napi_add_async_cleanup_hook (N-API v8)
##
## Registers an async cleanup hook that fires after the event loop drains.
## hook_cb: fn(handle, arg) callback. remove_handle: out handle for removal.
fn raw_add_async_cleanup_hook(
    env: NapiEnv,
    hook_cb: OpaquePointer[MutAnyOrigin],
    arg: OpaquePointer[MutAnyOrigin],
    remove_handle: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_add_async_cleanup_hook")
    return f(env, hook_cb, arg, remove_handle)

fn raw_add_async_cleanup_hook(
    b: Bindings,
    env: NapiEnv,
    hook_cb: OpaquePointer[MutAnyOrigin],
    arg: OpaquePointer[MutAnyOrigin],
    remove_handle: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].add_async_cleanup_hook).bitcast[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, hook_cb, arg, remove_handle)

## raw_remove_async_cleanup_hook — wraps napi_remove_async_cleanup_hook (N-API v8)
##
## Removes an async cleanup hook using the handle returned by add.
## Note: no env parameter — can be called from any thread.
fn raw_remove_async_cleanup_hook(
    handle: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_remove_async_cleanup_hook")
    return f(handle)

fn raw_remove_async_cleanup_hook(
    b: Bindings,
    handle: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].remove_async_cleanup_hook).bitcast[
        fn (OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(handle)

## raw_get_uv_event_loop — wraps napi_get_uv_event_loop (N-API v2)
##
## Returns the uv_loop_t* for the current environment via the out pointer.
## The loop pointer is valid for the lifetime of the env.
fn raw_get_uv_event_loop(
    env: NapiEnv,
    loop_out: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_uv_event_loop")
    return f(env, loop_out)

fn raw_get_uv_event_loop(
    b: Bindings,
    env: NapiEnv,
    loop_out: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].get_uv_event_loop).bitcast[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, loop_out)

## raw_async_init — wraps napi_async_init (N-API v1)
##
## Creates an async context for async_hooks tracking.
## async_resource: JS object representing the resource (pass undefined for none)
## async_resource_name: string napi_value naming the resource type
## result: out-pointer; receives the napi_async_context handle
fn raw_async_init(
    b: Bindings,
    env: NapiEnv,
    async_resource: NapiValue,
    async_resource_name: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].async_init).bitcast[
        fn (NapiEnv, NapiValue, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, async_resource, async_resource_name, result)

## raw_async_destroy — wraps napi_async_destroy (N-API v1)
##
## Destroys an async context previously created with napi_async_init.
fn raw_async_destroy(
    b: Bindings,
    env: NapiEnv,
    async_context: NapiAsyncContext,
) -> NapiStatus:
    var f = UnsafePointer(to=b[].async_destroy).bitcast[
        fn (NapiEnv, NapiAsyncContext) -> NapiStatus
    ]()[]
    return f(env, async_context)

## raw_make_callback — wraps napi_make_callback (N-API v1)
##
## Calls a JS function in the given async context. Unlike napi_call_function,
## this correctly triggers async_hooks before/after callbacks and propagates
## AsyncLocalStorage context established by the given async_context.
## recv:   the `this` value for the call
## func:   the JS function napi_value to invoke
## argc:   number of arguments
## argv:   pointer to argc consecutive napi_value arguments (immutable)
## result: out-pointer; receives the return value
fn raw_make_callback(
    b: Bindings,
    env: NapiEnv,
    async_context: NapiAsyncContext,
    recv: NapiValue,
    func: NapiValue,
    argc: UInt,
    argv: OpaquePointer[ImmutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].make_callback).bitcast[
        fn (NapiEnv, NapiAsyncContext, NapiValue, NapiValue, UInt, OpaquePointer[ImmutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, async_context, recv, func, argc, argv, result)

## raw_open_callback_scope — wraps napi_open_callback_scope (N-API v3)
##
## Opens a callback scope that sets up the async context for subsequent
## N-API calls. Required for correct async_hooks integration when making
## synchronous calls from within an async operation.
## resource_object: JS object for async tracking (or undefined)
## context:         async context from napi_async_init
## result:          out-pointer; receives the napi_callback_scope handle
fn raw_open_callback_scope(
    b: Bindings,
    env: NapiEnv,
    resource_object: NapiValue,
    context: NapiAsyncContext,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = UnsafePointer(to=b[].open_callback_scope).bitcast[
        fn (NapiEnv, NapiValue, NapiAsyncContext, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]()[]
    return f(env, resource_object, context, result)

## raw_close_callback_scope — wraps napi_close_callback_scope (N-API v3)
##
## Closes a callback scope previously opened with napi_open_callback_scope.
fn raw_close_callback_scope(
    b: Bindings,
    env: NapiEnv,
    scope: NapiCallbackScope,
) -> NapiStatus:
    var f = UnsafePointer(to=b[].close_callback_scope).bitcast[
        fn (NapiEnv, NapiCallbackScope) -> NapiStatus
    ]()[]
    return f(env, scope)
