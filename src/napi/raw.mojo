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
