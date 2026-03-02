## src/lib.mojo — napi-mojo module entry point (Phase 1+2: monolithic)
##
## This is the GREEN implementation for TDD Cycles 1+2 (hello() + createObject()).
## Intentionally monolithic — all N-API bindings and implementation live here
## until the Phase 3 safety refactor splits them into src/napi/*.mojo.
##
## v26.2 CHANGES:
##   - `alias` → `comptime` (alias deprecated)
##   - UnsafePointer[UInt8] → OpaquePointer[MutAnyOrigin] for opaque handles
##       (fully-concrete type, required for @export on non-parametric functions)
##   - OwnedDLHandle("") → OwnedDLHandle() (no-arg = dlopen(NULL) = process table)
##   - raw_* functions marked `raises`; callers use try/except
##   - Function types in get_function[] use ImmutAnyOrigin/MutAnyOrigin
##   - Function pointer: UnsafePointer(to=fn_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
##   - String pointer: greeting.unsafe_ptr().bitcast[NoneType]() → ImmutAnyOrigin
##   - Result pointer: UnsafePointer(to=result).bitcast[NoneType]() → MutAnyOrigin
##   - InlineArray constructor: InlineArray[T, N](fill=value) (variadic init removed)
##   - from memory import UnsafePointer removed (now in prelude)
##   - from utils import InlineArray removed (now in prelude)
##
## String lifetime rule: always bind strings to named `var` before passing their
## pointer to N-API. Mojo's ASAP destruction frees inline temporaries before N-API
## reads the pointer.

from ffi import OwnedDLHandle

# ---------------------------------------------------------------------------
# Opaque handle types
#
# napi_env and napi_value are opaque pointers (void*) in C.
# OpaquePointer[MutAnyOrigin] = UnsafePointer[NoneType, MutAnyOrigin] — fully
# concrete, no unbound type parameters. Required for @export functions and
# non-parametric function types in get_function[].
# ---------------------------------------------------------------------------
comptime NapiEnv = OpaquePointer[MutAnyOrigin]
comptime NapiValue = OpaquePointer[MutAnyOrigin]
comptime NapiStatus = Int32
comptime NAPI_OK: NapiStatus = 0

# ---------------------------------------------------------------------------
# napi_property_descriptor struct
#
# Must match C definition in node_api.h EXACTLY (60 bytes on 64-bit):
#   const char* utf8name;              // 8 bytes (pointer)
#   napi_value name;                   // 8 bytes (pointer)
#   napi_callback method;              // 8 bytes (fn pointer)
#   napi_callback getter;              // 8 bytes (fn pointer)
#   napi_callback setter;              // 8 bytes (fn pointer)
#   napi_value value;                  // 8 bytes (pointer)
#   napi_property_attributes attributes; // 4 bytes (UInt32)
#   void* data;                        // 8 bytes (pointer)
#   // 4 bytes implicit padding to align struct size to 8 bytes
# ---------------------------------------------------------------------------
struct NapiPropertyDescriptor:
    var utf8name: OpaquePointer[MutAnyOrigin]
    var name: OpaquePointer[MutAnyOrigin]
    var method: OpaquePointer[MutAnyOrigin]   # napi_callback fn pointer
    var getter: OpaquePointer[MutAnyOrigin]
    var setter: OpaquePointer[MutAnyOrigin]
    var value: OpaquePointer[MutAnyOrigin]
    var attributes: UInt32                     # napi_default = 0
    var data: OpaquePointer[MutAnyOrigin]

    fn __init__(out self):
        self.utf8name = OpaquePointer[MutAnyOrigin]()
        self.name = OpaquePointer[MutAnyOrigin]()
        self.method = OpaquePointer[MutAnyOrigin]()
        self.getter = OpaquePointer[MutAnyOrigin]()
        self.setter = OpaquePointer[MutAnyOrigin]()
        self.value = OpaquePointer[MutAnyOrigin]()
        self.attributes = 0
        self.data = OpaquePointer[MutAnyOrigin]()

# ---------------------------------------------------------------------------
# N-API function bindings (via host process symbol lookup)
#
# OwnedDLHandle() calls dlopen(NULL) — opens the host process image, giving
# access to all N-API symbols exported by the Node.js executable.
#
# All raw_* functions raise (OwnedDLHandle() can fail). Phase 3 refactor will
# cache the handle at module level and add check_status() wrappers.
# ---------------------------------------------------------------------------
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

fn raw_create_object(
    env: NapiEnv,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_object")
    return f(env, result)

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

# ---------------------------------------------------------------------------
# hello() — exposed as addon.hello()
#
# Returns the JavaScript string "Hello from Mojo!".
# ---------------------------------------------------------------------------
fn hello_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    var greeting = String("Hello from Mojo!")
    var result: NapiValue = NapiValue()
    try:
        var str_ptr: OpaquePointer[ImmutAnyOrigin] = greeting.unsafe_ptr().bitcast[NoneType]()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
        _ = raw_create_string_utf8(env, str_ptr, UInt(len(greeting)), result_ptr)
    except:
        pass
    return result

# ---------------------------------------------------------------------------
# createObject() — exposed as addon.createObject()
#
# Returns a new empty JavaScript object {}.
# ---------------------------------------------------------------------------
fn create_object_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    var result: NapiValue = NapiValue()
    try:
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
        _ = raw_create_object(env, result_ptr)
    except:
        pass
    return result

# ---------------------------------------------------------------------------
# Module entry point
#
# Node.js finds "napi_register_module_v1" via dlsym after dlopen-ing our
# .node file. The @export decorator ensures C linkage and exact symbol name.
#
# v26.2: NapiEnv/NapiValue = OpaquePointer[MutAnyOrigin] — fully concrete,
# so this function is non-parametric and @export can be applied.
# ---------------------------------------------------------------------------
@export("napi_register_module_v1", ABI="C")
fn register_module(env: NapiEnv, exports: NapiValue) -> NapiValue:
    # Keep name strings alive until napi_define_properties returns.
    # (String lifetime rule: ASAP destruction would free them too early.)
    var hello_name = String("hello")
    var create_object_name = String("createObject")

    # Register each property one at a time (avoids InlineArray Copyable requirement).
    # Property 0: hello
    var hello_desc = NapiPropertyDescriptor()
    hello_desc.utf8name = hello_name.unsafe_ptr_mut().bitcast[NoneType]()
    # v26.2 function pointer syntax: fn ref is 8-byte value holding code address.
    # Deref via bitcast to extract the raw code pointer as OpaquePointer.
    var hello_fn_ref = hello_fn
    hello_desc.method = UnsafePointer(to=hello_fn_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
    hello_desc.attributes = 0

    try:
        var p: OpaquePointer[ImmutAnyOrigin] = UnsafePointer(to=hello_desc).bitcast[NoneType]()
        _ = raw_define_properties(env, exports, 1, p)
    except:
        pass

    # Property 1: createObject
    var create_desc = NapiPropertyDescriptor()
    create_desc.utf8name = create_object_name.unsafe_ptr_mut().bitcast[NoneType]()
    var create_object_fn_ref = create_object_fn
    create_desc.method = UnsafePointer(to=create_object_fn_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
    create_desc.attributes = 0

    try:
        var p: OpaquePointer[ImmutAnyOrigin] = UnsafePointer(to=create_desc).bitcast[NoneType]()
        _ = raw_define_properties(env, exports, 1, p)
    except:
        pass

    return exports
