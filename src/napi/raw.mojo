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
from napi.types import NapiEnv, NapiValue, NapiStatus

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
