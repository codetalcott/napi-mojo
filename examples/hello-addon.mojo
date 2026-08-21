## examples/hello-addon.mojo — Minimal napi-mojo addon
##
## Shows the simplest possible addon: allocate NapiBindings once at module
## init, register three functions with ModuleBuilder and fn_ptr(), and fetch
## cached bindings in each callback with CbArgs.get_bindings(env, info).
##
## Build:  mojo build --emit shared-lib -I src examples/hello-addon.mojo \
##             -o build/hello.node
## Use:    const m = require('./build/hello.node')
##         m.hello()          // "Hello from Mojo!"
##         m.greet("world")   // "Hello, world!"
##         m.add(2.5, 3.7)    // 6.2

from std.memory.alloc import unsafe_alloc
from napi.types import NapiEnv, NapiValue, NAPI_TYPE_STRING, NAPI_TYPE_NUMBER
from napi.bindings import NapiBindings, init_bindings
from napi.error import throw_js_error, throw_js_type_error
from napi.framework.js_string import JsString
from napi.framework.js_number import JsNumber
from napi.framework.args import CbArgs
from napi.framework.js_value import js_typeof
from napi.framework.register import fn_ptr, ModuleBuilder


# --- Callbacks ---------------------------------------------------------------
# Each callback has the napi_callback signature: fn(NapiEnv, NapiValue) -> NapiValue
# Wrap the body in try/except — exceptions must never escape into C. The first
# line fetches the cached bindings pointer that ModuleBuilder attached as
# callback data; every subsequent N-API call runs on cached function pointers.
#
# The except block must THROW before it returns. Returning a null napi_value
# with no pending exception is not "returning an error" — N-API reads it as
# `undefined`, so the Mojo Error vanishes and JS sees a successful call that
# quietly produced nothing. `napi_throw_error` is a documented no-op while an
# exception is already pending, so throwing unconditionally is also correct on
# the path where the callback already threw (greet_fn's type check below):
# the original error keeps its identity.


def hello_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        return JsString.create_literal(b, env, "Hello from Mojo!").value
    except:
        throw_js_error(env, "hello failed")
        return NapiValue(unsafe_from_address=Int(0))


def greet_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var t = js_typeof(b, env, arg0)
        if t != NAPI_TYPE_STRING:
            throw_js_type_error(b, env, "greet requires a string argument")
            return NapiValue(unsafe_from_address=Int(0))
        var name = JsString.from_napi_value(b, env, arg0)
        return JsString.create(b, env, "Hello, " + name + "!").value
    except:
        throw_js_error(env, "greet failed")
        return NapiValue(unsafe_from_address=Int(0))


def add_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var a = JsNumber.from_napi_value(b, env, args[0])
        var n = JsNumber.from_napi_value(b, env, args[1])
        return JsNumber.create(b, env, a + n).value
    except:
        throw_js_error(env, "add failed")
        return NapiValue(unsafe_from_address=Int(0))


# --- Module entry point ------------------------------------------------------
# Node.js calls this via dlsym("napi_register_module_v1") when loading the
# .node file. Resolve all N-API symbols ONCE into a heap NapiBindings and pass
# the pointer to ModuleBuilder — it rides as callback data to every callback.


@export("napi_register_module_v1")
def register_module(env: NapiEnv, exports: NapiValue) abi("C") -> NapiValue:
    var bindings_ptr = unsafe_alloc[NapiBindings](1)
    try:
        var bindings = NapiBindings()
        init_bindings(bindings)
        bindings_ptr.unsafe_write(bindings^)
    except:
        bindings_ptr.unsafe_free()
        throw_js_error(env, "hello-addon: failed to resolve N-API symbols")
        return exports
    var cb_data = bindings_ptr.unsafe_bitcast[NoneType]().as_unsafe_any_origin()

    # Declare function refs BEFORE the try block — ASAP destruction safety.
    # Each ref must stay alive through all fn_ptr() calls.
    var hello_ref = hello_fn
    var greet_ref = greet_fn
    var add_ref = add_fn

    try:
        var m = ModuleBuilder(env, exports, cb_data)
        m.method("hello", fn_ptr(hello_ref))
        m.method("greet", fn_ptr(greet_ref))
        m.method("add", fn_ptr(add_ref))
        m.flush()
    except:
        # Same rule as the callbacks: a silent failure here would hand JS a
        # half-populated exports object, and the first missing function would
        # surface as "m.add is not a function" with no clue why.
        throw_js_error(env, "hello-addon: failed to register exports")

    return exports
