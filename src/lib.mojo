## src/lib.mojo — napi-mojo module entry point
##
## Exports: hello, createObject, makeGreeting, greet, add, isPositive
##
## Module structure:
##   src/napi/types.mojo                — NapiEnv, NapiValue, NapiStatus, NapiPropertyDescriptor
##   src/napi/raw.mojo                  — sole OwnedDLHandle user; raw_* bindings
##   src/napi/error.mojo                — check_status(), throw_js_error()
##   src/napi/module.mojo               — define_property(), register_method()
##   src/napi/framework/js_string.mojo  — JsString.create(), from_napi_value(), read_arg_0()
##   src/napi/framework/js_object.mojo  — JsObject.create(), set_named_property()
##   src/napi/framework/js_number.mojo  — JsNumber.create(), from_napi_value()
##   src/napi/framework/js_boolean.mojo — JsBoolean.create(), from_napi_value()
##   src/napi/framework/args.mojo       — CbArgs.get_one(), get_two()
##
## This file contains only:
##   1. Imports from the napi/ package
##   2. The napi_callback implementations
##   3. The @export entry point (register_module)

from napi.types import NapiEnv, NapiValue
from napi.module import register_method
from napi.framework.js_string import JsString
from napi.framework.js_object import JsObject
from napi.framework.js_number import JsNumber
from napi.framework.js_boolean import JsBoolean
from napi.framework.args import CbArgs
from napi.error import throw_js_error

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
        throw_js_error(env, "greet requires one string argument")
        return NapiValue()

# ---------------------------------------------------------------------------
# add(a, b) — exposed as addon.add(a, b)
#
# Takes two JavaScript number arguments and returns their sum as a JS number.
# Uses CbArgs.get_two for argument extraction and JsNumber for numeric I/O.
# ---------------------------------------------------------------------------
fn add_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var args = CbArgs.get_two(env, info)
        var a = JsNumber.from_napi_value(env, args[0])
        var b = JsNumber.from_napi_value(env, args[1])
        return JsNumber.create(env, a + b).value
    except:
        throw_js_error(env, "add requires two number arguments")
        return NapiValue()

# ---------------------------------------------------------------------------
# isPositive(n) — exposed as addon.isPositive(n)
#
# Takes a JavaScript number argument and returns true if it is > 0, false
# otherwise. Uses CbArgs.get_one for argument extraction.
# ---------------------------------------------------------------------------
fn is_positive_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var arg0 = CbArgs.get_one(env, info)
        var n = JsNumber.from_napi_value(env, arg0)
        return JsBoolean.create(env, n > 0).value
    except:
        throw_js_error(env, "isPositive requires one number argument")
        return NapiValue()

# ---------------------------------------------------------------------------
# Module entry point
#
# Node.js finds "napi_register_module_v1" via dlsym after dlopen-ing our
# .node file. The @export decorator ensures C linkage and the exact symbol
# name Node.js expects.
#
# Each fn_ref var binds the function reference (8 bytes holding the code
# address). The UnsafePointer.bitcast[]()[] pattern reads it as an
# OpaquePointer for the NapiPropertyDescriptor.method field.
# All fn_ref vars are declared before the try block so they remain alive
# through all register_method calls (ASAP destruction safety).
# ---------------------------------------------------------------------------
@export("napi_register_module_v1", ABI="C")
fn register_module(env: NapiEnv, exports: NapiValue) -> NapiValue:
    var hello_ref = hello_fn
    var create_object_ref = create_object_fn
    var make_greeting_ref = make_greeting_fn
    var greet_ref = greet_fn
    var add_ref = add_fn
    var is_positive_ref = is_positive_fn

    try:
        register_method(env, exports, "hello",
            UnsafePointer(to=hello_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "createObject",
            UnsafePointer(to=create_object_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "makeGreeting",
            UnsafePointer(to=make_greeting_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "greet",
            UnsafePointer(to=greet_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "add",
            UnsafePointer(to=add_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "isPositive",
            UnsafePointer(to=is_positive_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
    except:
        pass

    return exports
