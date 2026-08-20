## src/addon/host_ops.mojo — the Node-as-host surface, exercised at runtime
##
## These callbacks exist so tests/host.test.js can drive NodeHost, call_n,
## call_with, call_method and with_handle_scope against a live napi_env. The
## `ctx` object every host_* function takes is the same shape the
## `napi-mojo run` bootstrap builds: { require, argv, cwd }. Jest constructs
## it by hand, which is exactly the contract — the host never scavenges for
## `require`, it is always handed in.

from std.memory.alloc import unsafe_alloc
from napi.types import NapiEnv, NapiValue
from napi.bindings import Bindings
from napi.error import throw_js_error, throw_js_error_dynamic
from napi.framework.args import CbArgs
from napi.framework.handle_scope import with_handle_scope
from napi.framework.js_array import JsArray
from napi.framework.js_function import JsFunction
from napi.framework.js_host import NodeHost
from napi.framework.js_number import JsNumber
from napi.framework.js_object import JsObject
from napi.framework.js_string import JsString, js_to_string
from napi.framework.js_value import js_is_array
from napi.framework.convert import to_js_array_str
from napi.framework.register import fn_ptr, ModuleBuilder


## Read a JS array into a List[NapiValue] for the call_n / call_with argv.
def _args_from_js(
    b: Bindings, env: NapiEnv, arr_val: NapiValue
) raises -> List[NapiValue]:
    var out = List[NapiValue]()
    if not js_is_array(b, env, arr_val):
        return out^
    var arr = JsArray(arr_val)
    var n = arr.length(b, env)
    for i in range(Int(n)):
        out.append(arr.get(b, env, UInt32(i)))
    return out^


def host_require_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var host = NodeHost.from_context(b, env, args[0])
        return host.require(js_to_string(b, env, args[1])).value
    except e:
        # Unconditional throw is correct in BOTH directions. If require()
        # itself failed, Node's MODULE_NOT_FOUND is already pending and
        # napi_throw_error is a documented no-op, so the original error
        # reaches the caller intact. If the failure was Mojo-side (a ctx with
        # no `require`), nothing is pending and this is the only thing that
        # stops a bogus null being handed back to JS.
        throw_js_error_dynamic(env, String(e))
        return NapiValue(unsafe_from_address=Int(0))


def host_argv_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var ctx = CbArgs.get_one(b, env, info)
        var host = NodeHost.from_context(b, env, ctx)
        return to_js_array_str(b, env, host.argv())
    except e:
        throw_js_error_dynamic(env, String(e))
        return NapiValue(unsafe_from_address=Int(0))


def host_console_log_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var host = NodeHost.from_context(b, env, args[0])
        host.console_log(js_to_string(b, env, args[1]))
    except e:
        throw_js_error_dynamic(env, String(e))
    return NapiValue(unsafe_from_address=Int(0))


def host_global_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var ctx = CbArgs.get_one(b, env, info)
        var host = NodeHost.from_context(b, env, ctx)
        return host.global_object().value
    except e:
        throw_js_error_dynamic(env, String(e))
        return NapiValue(unsafe_from_address=Int(0))


## callMethod(obj, name, argsArray) — JsObject.call_method with `this` bound.
def call_method_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var argc = CbArgs.argc(b, env, info)
        if argc < 3:
            throw_js_error(env, "callMethod requires (object, name, args)")
            return NapiValue(unsafe_from_address=Int(0))
        var argv = unsafe_alloc[NapiValue](Int(argc))
        _ = CbArgs.get_argv(b, env, info, argc, argv.as_unsafe_any_origin())
        var obj = JsObject(argv[unsafe_offset=0])
        var name = js_to_string(b, env, argv[unsafe_offset=1])
        var call_args = _args_from_js(b, env, argv[unsafe_offset=2])
        argv.unsafe_free()
        return obj.call_method(b, env, name, call_args)
    except e:
        # No-op when the callee's own exception is already pending.
        throw_js_error_dynamic(env, String(e))
        return NapiValue(unsafe_from_address=Int(0))


## callN(fn, argsArray) — JsFunction.call_n, `this` is undefined.
def call_n_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var f = JsFunction(args[0])
        return f.call_n(b, env, _args_from_js(b, env, args[1]))
    except e:
        # No-op when the callee's own exception is already pending.
        throw_js_error_dynamic(env, String(e))
        return NapiValue(unsafe_from_address=Int(0))


## scopedCall(n, fn) — a Mojo-driven loop that calls JS n times, each
## iteration in its own handle scope. Returns n. The point is that handles do
## not accumulate across iterations; a large n must not exhaust the scope.
def scoped_call_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var n = JsNumber.to_int(b, env, args[0])
        var f = JsFunction(args[1])
        for i in range(n):
            # `f` and `idx` warn "assignment never used" — the documented
            # false positive for vars read only inside a `capturing` closure.
            # Do NOT delete them; _body reads both.
            var idx = i

            @parameter
            def _body() raises:
                _ = f.call1(b, env, JsNumber.create_int(b, env, idx).value)

            with_handle_scope[_body](b, env)
        return JsNumber.create_int(b, env, n).value
    except e:
        # No-op when the callee's own exception is already pending.
        throw_js_error_dynamic(env, String(e))
        return NapiValue(unsafe_from_address=Int(0))


def register_host_ops(mut m: ModuleBuilder) raises:
    var host_require_ref = host_require_fn
    var host_argv_ref = host_argv_fn
    var host_console_log_ref = host_console_log_fn
    var host_global_ref = host_global_fn
    var call_method_ref = call_method_fn
    var call_n_ref = call_n_fn
    var scoped_call_ref = scoped_call_fn

    m.method("hostRequire", fn_ptr(host_require_ref))
    m.method("hostArgv", fn_ptr(host_argv_ref))
    m.method("hostConsoleLog", fn_ptr(host_console_log_ref))
    m.method("hostGlobal", fn_ptr(host_global_ref))
    m.method("callMethod", fn_ptr(call_method_ref))
    m.method("callN", fn_ptr(call_n_ref))
    m.method("scopedCall", fn_ptr(scoped_call_ref))

    _ = host_require_ref
    _ = host_argv_ref
    _ = host_console_log_ref
    _ = host_global_ref
    _ = call_method_ref
    _ = call_n_ref
    _ = scoped_call_ref
