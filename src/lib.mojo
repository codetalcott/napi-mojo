## src/lib.mojo — napi-mojo module entry point (Phase 3: modular)
##
## Phase 3 safety refactor of the Phase 1+2 monolith:
##   - Type definitions moved to src/napi/types.mojo
##   - Raw FFI bindings moved to src/napi/raw.mojo (sole OwnedDLHandle user)
##   - Error handling in src/napi/error.mojo (check_status)
##   - Safe property registration in src/napi/module.mojo (define_property)
##
## This file contains only:
##   1. Imports from the napi/ package
##   2. The two napi_callback implementations (hello_fn, create_object_fn)
##   3. The @export entry point (register_module)
##
## String lifetime rule: always bind strings to named `var` before passing
## their pointer to N-API. Mojo's ASAP destruction frees inline temporaries
## before N-API reads the pointer.

from napi.types import NapiEnv, NapiValue, NapiPropertyDescriptor
from napi.raw import raw_create_string_utf8, raw_create_object
from napi.error import check_status
from napi.module import define_property

# ---------------------------------------------------------------------------
# hello() — exposed as addon.hello()
#
# Returns the JavaScript string "Hello from Mojo!".
# Signature matches napi_callback: fn(NapiEnv, NapiValue) -> NapiValue.
# Cannot be `raises` — Node.js calls this directly via C function pointer.
# ---------------------------------------------------------------------------
fn hello_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    var greeting = String("Hello from Mojo!")
    var result: NapiValue = NapiValue()
    try:
        var str_ptr: OpaquePointer[ImmutAnyOrigin] = greeting.unsafe_ptr().bitcast[NoneType]()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
        var status = raw_create_string_utf8(env, str_ptr, UInt(len(greeting)), result_ptr)
        check_status(status)
    except:
        pass
    return result

# ---------------------------------------------------------------------------
# createObject() — exposed as addon.createObject()
#
# Returns a new empty JavaScript object {}.
# Same napi_callback signature constraints as hello_fn above.
# ---------------------------------------------------------------------------
fn create_object_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    var result: NapiValue = NapiValue()
    try:
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
        var status = raw_create_object(env, result_ptr)
        check_status(status)
    except:
        pass
    return result

# ---------------------------------------------------------------------------
# Module entry point
#
# Node.js finds "napi_register_module_v1" via dlsym after dlopen-ing our
# .node file. The @export decorator ensures C linkage and the exact symbol
# name Node.js expects.
#
# v26.2: NapiEnv/NapiValue = OpaquePointer[MutAnyOrigin] — fully concrete,
# so this function is non-parametric and @export can be applied.
# ---------------------------------------------------------------------------
@export("napi_register_module_v1", ABI="C")
fn register_module(env: NapiEnv, exports: NapiValue) -> NapiValue:
    # Keep name strings alive until define_property returns.
    # (String lifetime rule: ASAP destruction would free them too early.)
    var hello_name = String("hello")
    var create_object_name = String("createObject")

    # Property 0: hello
    # Registers hello_fn as the "hello" method on the exports object.
    var hello_desc = NapiPropertyDescriptor()
    hello_desc.utf8name = hello_name.unsafe_ptr_mut().bitcast[NoneType]()
    # v26.2 function pointer syntax: fn ref is an 8-byte value holding the
    # code address. Bitcast via UnsafePointer to extract it as OpaquePointer.
    var hello_fn_ref = hello_fn
    hello_desc.method = UnsafePointer(to=hello_fn_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
    hello_desc.attributes = 0

    try:
        define_property(env, exports, hello_desc)
    except:
        pass

    # Property 1: createObject
    var create_desc = NapiPropertyDescriptor()
    create_desc.utf8name = create_object_name.unsafe_ptr_mut().bitcast[NoneType]()
    var create_object_fn_ref = create_object_fn
    create_desc.method = UnsafePointer(to=create_object_fn_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
    create_desc.attributes = 0

    try:
        define_property(env, exports, create_desc)
    except:
        pass

    return exports
