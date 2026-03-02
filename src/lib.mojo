## src/lib.mojo — napi-mojo module entry point
##
## Exports: hello, createObject, makeGreeting, greet, add, isPositive,
##          getNull, getUndefined, sumArray
##
## Module structure:
##   src/napi/types.mojo                — NapiEnv, NapiValue, NapiStatus, NapiPropertyDescriptor
##   src/napi/raw.mojo                  — sole OwnedDLHandle user; raw_* bindings
##   src/napi/error.mojo                — check_status(), throw_js_error()
##   src/napi/module.mojo               — define_property(), register_method()
##   src/napi/framework/js_string.mojo  — JsString.create(), create_literal(), from_napi_value(), read_arg_0()
##   src/napi/framework/js_object.mojo  — JsObject.create(), set_property(), set_named_property()
##   src/napi/framework/js_number.mojo  — JsNumber.create(), from_napi_value()
##   src/napi/framework/js_boolean.mojo — JsBoolean.create(), from_napi_value()
##   src/napi/framework/args.mojo       — CbArgs.get_one(), get_two()
##   src/napi/framework/js_value.mojo   — js_typeof(), js_type_name()
##   src/napi/framework/js_null.mojo    — JsNull.create()
##   src/napi/framework/js_undefined.mojo — JsUndefined.create()
##   src/napi/framework/js_array.mojo   — JsArray.create_with_length(), set(), get(), length()
##
## This file contains only:
##   1. Imports from the napi/ package
##   2. The napi_callback implementations
##   3. The @export entry point (register_module)

from napi.types import NapiEnv, NapiValue, NAPI_TYPE_STRING
from napi.module import register_method
from napi.framework.js_string import JsString
from napi.framework.js_object import JsObject
from napi.framework.js_number import JsNumber
from napi.framework.js_boolean import JsBoolean
from napi.framework.js_null import JsNull
from napi.framework.js_undefined import JsUndefined
from napi.framework.js_array import JsArray
from napi.framework.args import CbArgs
from napi.framework.js_value import js_typeof, js_type_name
from napi.error import throw_js_error, throw_js_error_dynamic

# ---------------------------------------------------------------------------
# hello() — exposed as addon.hello()
#
# Returns the JavaScript string "Hello from Mojo!".
# Signature matches napi_callback: fn(NapiEnv, NapiValue) -> NapiValue.
# Cannot be `raises` — Node.js calls this directly via C function pointer.
# ---------------------------------------------------------------------------
fn hello_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        return JsString.create_literal(env, "Hello from Mojo!").value
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
# Demonstrates JsObject.set_property (StringLiteral key) with a JsString value.
# ---------------------------------------------------------------------------
fn make_greeting_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var obj = JsObject.create(env)
        var msg = JsString.create_literal(env, "Hello!")
        obj.set_property(env, "message", msg.value)
        return obj.value
    except:
        return NapiValue()

# ---------------------------------------------------------------------------
# greet(name) — exposed as addon.greet(name)
#
# Takes a JavaScript string argument and returns "Hello, <name>!".
# Uses js_typeof to validate the argument type before reading, enabling
# a descriptive error message that names the actual received type.
# ---------------------------------------------------------------------------
fn greet_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var arg0 = CbArgs.get_one(env, info)
        var t = js_typeof(env, arg0)
        if t != NAPI_TYPE_STRING:
            throw_js_error_dynamic(env, "greet: expected string, got " + js_type_name(t))
            return NapiValue()
        var name = JsString.from_napi_value(env, arg0)
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
# getNull() — exposed as addon.getNull()
#
# Returns the JavaScript null singleton. Demonstrates JsNull.create().
# ---------------------------------------------------------------------------
fn get_null_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        return JsNull.create(env).value
    except:
        return NapiValue()

# ---------------------------------------------------------------------------
# getUndefined() — exposed as addon.getUndefined()
#
# Returns the JavaScript undefined singleton. Demonstrates JsUndefined.create().
# ---------------------------------------------------------------------------
fn get_undefined_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        return JsUndefined.create(env).value
    except:
        return NapiValue()

# ---------------------------------------------------------------------------
# sumArray(arr) — exposed as addon.sumArray(arr)
#
# Takes a JavaScript array of numbers and returns their sum as a JS number.
# Demonstrates JsArray.length(), JsArray.get(), and JsNumber.from_napi_value().
# ---------------------------------------------------------------------------
fn sum_array_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var arg0 = CbArgs.get_one(env, info)
        var arr = JsArray(arg0)
        var len = arr.length(env)
        var total: Float64 = 0.0
        for i in range(Int(len)):
            var elem = arr.get(env, UInt32(i))
            total += JsNumber.from_napi_value(env, elem)
        return JsNumber.create(env, total).value
    except:
        throw_js_error(env, "sumArray requires one array argument")
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
    var get_null_ref = get_null_fn
    var get_undefined_ref = get_undefined_fn
    var sum_array_ref = sum_array_fn

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
        register_method(env, exports, "getNull",
            UnsafePointer(to=get_null_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "getUndefined",
            UnsafePointer(to=get_undefined_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "sumArray",
            UnsafePointer(to=sum_array_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
    except:
        pass

    return exports
