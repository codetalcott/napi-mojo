## src/lib.mojo — napi-mojo module entry point (Phase 5b: numeric arguments)
##
## Phase 5b adds add(a, b) → a+b via JsNumber and multi-arg extraction.
##
## Module structure:
##   src/napi/types.mojo          — NapiEnv, NapiValue, NapiStatus, NapiPropertyDescriptor
##   src/napi/raw.mojo            — sole OwnedDLHandle user; raw_* bindings
##   src/napi/error.mojo          — check_status()
##   src/napi/module.mojo         — define_property() safe wrapper
##   src/napi/framework/js_string.mojo — JsString.create(), JsString.read_arg_0()
##   src/napi/framework/js_object.mojo — JsObject.create(), set_named_property()
##   src/napi/framework/js_number.mojo — JsNumber.create(), JsNumber.from_napi_value()
##
## This file contains only:
##   1. Imports from the napi/ package
##   2. The napi_callback implementations
##   3. The @export entry point (register_module)

from napi.types import NapiEnv, NapiValue, NapiPropertyDescriptor
from napi.module import define_property
from napi.framework.js_string import JsString
from napi.framework.js_object import JsObject
from napi.framework.js_number import JsNumber
from napi.raw import raw_get_cb_info
from napi.error import check_status

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
# greet(name) — exposed as addon.greet(name)
#
# Takes a JavaScript string argument and returns "Hello, <name>!".
# First function in the addon to read a callback argument from JavaScript.
# ---------------------------------------------------------------------------
fn greet_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var name = JsString.read_arg_0(env, info)
        return JsString.create(env, "Hello, " + name + "!").value
    except:
        return NapiValue()

# ---------------------------------------------------------------------------
# add(a, b) — exposed as addon.add(a, b)
#
# Takes two JavaScript number arguments and returns their sum as a JS number.
# Demonstrates multi-argument extraction via InlineArray[NapiValue, 2] argv
# and numeric I/O via JsNumber.from_napi_value / JsNumber.create.
# ---------------------------------------------------------------------------
fn add_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        # Extract 2 arguments: pass a 2-element NapiValue array as argv.
        # InlineArray stays alive through all accesses below (tracked uses).
        var argc: UInt = 2
        var args = InlineArray[NapiValue, 2](fill=NapiValue())
        var null = OpaquePointer[MutAnyOrigin]()
        check_status(raw_get_cb_info(
            env, info,
            UnsafePointer(to=argc).bitcast[NoneType](),
            UnsafePointer(to=args[0]).bitcast[NoneType](),
            null, null,
        ))
        # Read each argument as Float64, add, return as JS number.
        var a_val = args[0]
        var b_val = args[1]
        var a = JsNumber.from_napi_value(env, a_val)
        var b = JsNumber.from_napi_value(env, b_val)
        return JsNumber.create(env, a + b).value
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
    # Use string literals directly for property names. String literals have
    # STATIC lifetime (data baked into the binary), so ASAP destruction never
    # applies. Using heap Strings caused ASAP to free the buffer before
    # napi_define_properties read the pointer (use-after-free).
    # utf8name is OpaquePointer[ImmutAnyOrigin] — matching C's const char*.

    # Property 0: hello
    var hello_desc = NapiPropertyDescriptor()
    hello_desc.utf8name = "hello".unsafe_ptr().bitcast[NoneType]()
    var hello_fn_ref = hello_fn
    hello_desc.method = UnsafePointer(to=hello_fn_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
    hello_desc.attributes = 0
    try:
        define_property(env, exports, hello_desc)
    except:
        pass

    # Property 1: createObject
    var create_desc = NapiPropertyDescriptor()
    create_desc.utf8name = "createObject".unsafe_ptr().bitcast[NoneType]()
    var create_object_fn_ref = create_object_fn
    create_desc.method = UnsafePointer(to=create_object_fn_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
    create_desc.attributes = 0
    try:
        define_property(env, exports, create_desc)
    except:
        pass

    # Property 2: makeGreeting
    var greeting_desc = NapiPropertyDescriptor()
    greeting_desc.utf8name = "makeGreeting".unsafe_ptr().bitcast[NoneType]()
    var make_greeting_fn_ref = make_greeting_fn
    greeting_desc.method = UnsafePointer(to=make_greeting_fn_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
    greeting_desc.attributes = 0
    try:
        define_property(env, exports, greeting_desc)
    except:
        pass

    # Property 3: greet
    var greet_desc = NapiPropertyDescriptor()
    greet_desc.utf8name = "greet".unsafe_ptr().bitcast[NoneType]()
    var greet_fn_ref = greet_fn
    greet_desc.method = UnsafePointer(to=greet_fn_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
    greet_desc.attributes = 0
    try:
        define_property(env, exports, greet_desc)
    except:
        pass

    # Property 4: add
    var add_desc = NapiPropertyDescriptor()
    add_desc.utf8name = "add".unsafe_ptr().bitcast[NoneType]()
    var add_fn_ref = add_fn
    add_desc.method = UnsafePointer(to=add_fn_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
    add_desc.attributes = 0
    try:
        define_property(env, exports, add_desc)
    except:
        pass

    return exports
