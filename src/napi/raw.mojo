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
