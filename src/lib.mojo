## src/lib.mojo — napi-mojo module entry point (Phase 4: framework wrappers)
##
## Phase 4 adds JsString/JsObject framework wrappers and a new makeGreeting()
## function. hello_fn and create_object_fn are refactored to use the wrappers.
##
## Module structure:
##   src/napi/types.mojo          — NapiEnv, NapiValue, NapiStatus, NapiPropertyDescriptor
##   src/napi/raw.mojo            — sole OwnedDLHandle user; raw_* bindings
##   src/napi/error.mojo          — check_status()
##   src/napi/module.mojo         — define_property() safe wrapper
##   src/napi/framework/js_string.mojo — JsString.create()
##   src/napi/framework/js_object.mojo — JsObject.create(), set_named_property()
##
## This file contains only:
##   1. Imports from the napi/ package
##   2. The napi_callback implementations
##   3. The @export entry point (register_module)

from napi.types import NapiEnv, NapiValue, NapiPropertyDescriptor
from napi.module import define_property
from napi.framework.js_string import JsString
from napi.framework.js_object import JsObject

# ---------------------------------------------------------------------------
# hello() — exposed as addon.hello()
#
# Returns the JavaScript string "Hello from Mojo!".
# Signature matches napi_callback: fn(NapiEnv, NapiValue) -> NapiValue.
# Cannot be `raises` — Node.js calls this directly via C function pointer.
# ---------------------------------------------------------------------------
fn hello_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        return JsString.create(env, "Hello from Mojo!").value
    except:
        return NapiValue()

# ---------------------------------------------------------------------------
# createObject() — exposed as addon.createObject()
#
# Returns a new empty JavaScript object {}.
# ---------------------------------------------------------------------------
fn create_object_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        return JsObject.create(env).value
    except:
        return NapiValue()

# ---------------------------------------------------------------------------
# makeGreeting() — exposed as addon.makeGreeting()
#
# Returns the JavaScript object {message: "Hello!"}.
# Demonstrates JsObject.set_named_property with a JsString value.
# ---------------------------------------------------------------------------
fn make_greeting_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var obj = JsObject.create(env)
        var msg = JsString.create(env, "Hello!")
        var prop_name = String("message")
        obj.set_named_property(env, prop_name, msg.value)
        return obj.value
    except:
        return NapiValue()

# ---------------------------------------------------------------------------
# Module entry point
#
# Node.js finds "napi_register_module_v1" via dlsym after dlopen-ing our
# .node file. The @export decorator ensures C linkage and the exact symbol
# name Node.js expects.
# ---------------------------------------------------------------------------
@export("napi_register_module_v1", ABI="C")
fn register_module(env: NapiEnv, exports: NapiValue) -> NapiValue:
    # Keep name strings alive until define_property returns.
    # (String lifetime rule: ASAP destruction would free them too early.)
    var hello_name = String("hello")
    var create_object_name = String("createObject")
    var make_greeting_name = String("makeGreeting")

    # Property 0: hello
    var hello_desc = NapiPropertyDescriptor()
    hello_desc.utf8name = hello_name.unsafe_ptr_mut().bitcast[NoneType]()
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

    # Property 2: makeGreeting
    var greeting_desc = NapiPropertyDescriptor()
    greeting_desc.utf8name = make_greeting_name.unsafe_ptr_mut().bitcast[NoneType]()
    var make_greeting_fn_ref = make_greeting_fn
    greeting_desc.method = UnsafePointer(to=make_greeting_fn_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
    greeting_desc.attributes = 0
    try:
        define_property(env, exports, greeting_desc)
    except:
        pass

    return exports
