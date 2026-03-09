## examples/hello-addon.mojo — Minimal napi-mojo addon
##
## Shows the simplest possible addon: three functions registered with
## ModuleBuilder and fn_ptr(). This is a reference example — to build it,
## copy into src/ and adjust imports, or use as a pattern for your own addon.
##
## Build:  mojo build --emit shared-lib src/lib.mojo -o build/index.node
## Use:    const m = require('./build/index.node')
##         m.hello()          // "Hello from Mojo!"
##         m.greet("world")   // "Hello, world!"
##         m.add(2.5, 3.7)    // 6.2

from napi.types import NapiEnv, NapiValue, NAPI_TYPE_STRING, NAPI_TYPE_NUMBER
from napi.error import throw_js_error, throw_js_type_error, check_status
from napi.framework.js_string import JsString
from napi.framework.js_number import JsNumber
from napi.framework.args import CbArgs
from napi.framework.js_value import js_typeof
from napi.framework.register import fn_ptr, ModuleBuilder


# Note on API style: this example uses ModuleBuilder(env, exports) without a
# NapiBindings pointer, so callbacks use the no-bindings CbArgs overloads
# (get_one(env, info), get_two(env, info), etc.). This is intentional for a
# minimal example. Production addons should pass NapiBindings through
# ModuleBuilder to enable cached function pointers (zero per-call dlsym).
# See src/lib.mojo and the "Cached NapiBindings" section of CLAUDE.md.

# --- Callbacks ---------------------------------------------------------------
# Each callback has the napi_callback signature: fn(NapiEnv, NapiValue) -> NapiValue
# Wrap the body in try/except — exceptions must never escape into C.

fn hello_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        return JsString.create_literal(env, "Hello from Mojo!").value
    except:
        return NapiValue()

fn greet_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var arg0 = CbArgs.get_one(env, info)
        var t = js_typeof(env, arg0)
        if t != NAPI_TYPE_STRING:
            throw_js_type_error(env, "greet requires a string argument")
            return NapiValue()
        var name = JsString.from_napi_value(env, arg0)
        return JsString.create(env, "Hello, " + name + "!").value
    except:
        return NapiValue()

fn add_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var args = CbArgs.get_two(env, info)
        var a = JsNumber.from_napi_value(env, args[0])
        var b = JsNumber.from_napi_value(env, args[1])
        return JsNumber.create(env, a + b).value
    except:
        return NapiValue()


# --- Module entry point ------------------------------------------------------
# Node.js calls this via dlsym("napi_register_module_v1") when loading the .node file.

@export("napi_register_module_v1", ABI="C")
fn register_module(env: NapiEnv, exports: NapiValue) -> NapiValue:
    # Declare function refs BEFORE the try block — ASAP destruction safety.
    # Each ref must stay alive through all fn_ptr() calls.
    var hello_ref = hello_fn
    var greet_ref = greet_fn
    var add_ref = add_fn

    try:
        var m = ModuleBuilder(env, exports)
        m.method("hello", fn_ptr(hello_ref))
        m.method("greet", fn_ptr(greet_ref))
        m.method("add", fn_ptr(add_ref))
    except:
        pass

    return exports
