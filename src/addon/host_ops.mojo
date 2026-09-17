## src/addon/host_ops.mojo — the Node-as-host surface, exercised at runtime
##
## These callbacks exist so tests/host.test.js can drive NodeHost, call_n,
## call_with, call_method, with_handle_scope and JsPromise.on_settled against a
## live napi_env. The
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
from napi.framework.js_ref import JsRef
from napi.framework.js_arraybuffer import JsArrayBuffer
from napi.framework.js_null import JsNull
from napi.framework.js_promise import JsPromise, Settlement
from napi.framework.js_undefined import JsUndefined
from addon.typed_helpers_ops import TypedPayload, typed_payload_finalize
from napi.framework.js_value import js_get_global
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


def host_console_error_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var host = NodeHost.from_context(b, env, args[0])
        host.console_error(js_to_string(b, env, args[1]))
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
            # Do NOT delete `idx` (or `f` above) — _body reads both, and a
            # legacy closure's reads are easy to mistake for dead stores.
            # These used to warn "assignment never used", which was recorded
            # as a compiler false positive; it was really a symptom of the
            # capture not being tracked, and spelling with_handle_scope's
            # parameter `capturing[_]` silenced it. See docs/toolchain-
            # migrations.md, Mojo 1.1.0.
            var idx = i

            @__parameter
            def _body() raises:
                _ = f.call1(b, env, JsNumber.create_int(b, env, idx).value)

            with_handle_scope[_body](b, env)
        return JsNumber.create_int(b, env, n).value
    except e:
        # No-op when the callee's own exception is already pending.
        throw_js_error_dynamic(env, String(e))
        return NapiValue(unsafe_from_address=Int(0))



# --- Continuation passing ------------------------------------------------
#
# Mojo code cannot wait for a promise: it runs on the JS thread, and a promise
# settles only after the calling callback returns to the event loop. So the
# shape for anything async is a continuation — JsPromise.on_settled attaches
# one, the callback returns, and the continuation fires on a LATER tick.
#
# That later tick is the whole difficulty, and on_settled owns it. The
# napi_values the creating call held are long out of scope, so JS values
# travel as `captures` (bound arguments the GC traces) and native state as
# `data` (freed by a GC finalizer). Nothing is freed when the continuation
# fires, because it may never fire: an earlier version of these callbacks
# freed their payload on the call path and leaked it — and a strongly
# referenced onResult — for every promise that rejected or never settled.


## thenDouble(value, onResult) -> Promise
## Awaits `value`, then calls onResult(null, value * 2) — or onResult(reason)
## if it rejected. Returns the promise .then() made, which rejects if the Mojo
## side fails or onResult throws.
def then_double_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var captures = List[NapiValue]()
        captures.append(args[1])
        var cb_ref = continuation_double_fn
        var derived = JsPromise.on_settled(
            b, env, args[0], fn_ptr(cb_ref), captures^
        )
        _ = cb_ref
        return derived
    except e:
        throw_js_error_dynamic(env, String(e))
        return NapiValue(unsafe_from_address=Int(0))


def continuation_double_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var s = Settlement.read(env, info)
        var on_result = JsFunction(s.captures[0])
        if not s.ok:
            return on_result.call1(s.b, env, s.value)
        var n = JsNumber.from_napi_value(s.b, env, s.value)
        return on_result.call2(
            s.b,
            env,
            JsNull.create(s.b, env).value,
            JsNumber.create(s.b, env, n * 2.0).value,
        )
    except e:
        throw_js_error_dynamic(env, String(e))
        return NapiValue(unsafe_from_address=Int(0))


## thenScaled(value, factor, counter, onResult) -> Promise
## thenDouble with NATIVE state: the factor rides in a heap payload handed to
## on_settled as `data`. The payload is TypedPayload, whose finalizer bumps the
## Int64 in `counter` (an ArrayBuffer(8)) — so tests can observe that the
## payload is freed on every path, including promises that never settle.
def then_scaled_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_four(b, env, info)
        var factor = JsNumber.from_napi_value(b, env, args[1])
        var counter_ptr = JsArrayBuffer(args[2]).data_ptr(b, env).unsafe_bitcast[
            Int64
        ]()
        # Pin the counter's ArrayBuffer until the finalizer has incremented it
        # (typed_payload_finalize releases this ref afterwards).
        var ab_ref = JsRef.create(b, env, args[2], 1)
        var payload = unsafe_alloc[TypedPayload](1)
        payload.unsafe_write(
            TypedPayload(factor, counter_ptr, ab_ref.handle, Int(b))
        )

        var captures = List[NapiValue]()
        captures.append(args[3])
        var cb_ref = continuation_scaled_fn
        var fin_ref = typed_payload_finalize
        var derived = JsPromise.on_settled(
            b,
            env,
            args[0],
            fn_ptr(cb_ref),
            captures^,
            payload.unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            fn_ptr(fin_ref),
        )
        _ = cb_ref
        _ = fin_ref
        return derived
    except e:
        throw_js_error_dynamic(env, String(e))
        return NapiValue(unsafe_from_address=Int(0))


def continuation_scaled_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var s = Settlement.read(env, info)
        var on_result = JsFunction(s.captures[0])
        if not s.ok:
            return on_result.call1(s.b, env, s.value)
        var payload = s.user_data().unsafe_bitcast[TypedPayload]()
        var n = JsNumber.from_napi_value(s.b, env, s.value)
        return on_result.call2(
            s.b,
            env,
            JsNull.create(s.b, env).value,
            JsNumber.create(s.b, env, n * payload[].value).value,
        )
    except e:
        throw_js_error_dynamic(env, String(e))
        return NapiValue(unsafe_from_address=Int(0))


## deferredRequire(ctx, onResult) -> Promise
## Captures `require`, then uses it from a later tick to load `path` and calls
## onResult(null, path.sep). Proves a host program can reach npm after the
## call that received ctx has returned — with no napi_ref in sight.
def deferred_require_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        _ = NodeHost.from_context(b, env, args[0])  # validate the ctx shape

        var captures = List[NapiValue]()
        captures.append(JsObject(args[0]).get_named_property(b, env, "require"))
        captures.append(args[1])
        # Settling `undefined` is the smallest way to reach a later tick.
        var cb_ref = continuation_require_fn
        var derived = JsPromise.on_settled(
            b, env, JsUndefined.create(b, env).value, fn_ptr(cb_ref), captures^
        )
        _ = cb_ref
        return derived
    except e:
        throw_js_error_dynamic(env, String(e))
        return NapiValue(unsafe_from_address=Int(0))


def continuation_require_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var s = Settlement.read(env, info)
        var on_result = JsFunction(s.captures[1])
        if not s.ok:
            return on_result.call1(s.b, env, s.value)
        var req = JsFunction(s.captures[0])
        var mod = JsObject(
            req.call1(s.b, env, JsString.create(s.b, env, "path").value)
        )
        var sep = mod.get_named_property(s.b, env, "sep")
        return on_result.call2(s.b, env, JsNull.create(s.b, env).value, sep)
    except e:
        throw_js_error_dynamic(env, String(e))
        return NapiValue(unsafe_from_address=Int(0))


def register_host_ops(mut m: ModuleBuilder) raises:
    var host_require_ref = host_require_fn
    var host_argv_ref = host_argv_fn
    var host_console_log_ref = host_console_log_fn
    var host_console_error_ref = host_console_error_fn
    var host_global_ref = host_global_fn
    var call_method_ref = call_method_fn
    var call_n_ref = call_n_fn
    var scoped_call_ref = scoped_call_fn
    var then_double_ref = then_double_fn
    var deferred_require_ref = deferred_require_fn
    var then_scaled_ref = then_scaled_fn

    m.method("hostRequire", fn_ptr(host_require_ref))
    m.method("hostArgv", fn_ptr(host_argv_ref))
    m.method("hostConsoleLog", fn_ptr(host_console_log_ref))
    m.method("hostConsoleError", fn_ptr(host_console_error_ref))
    m.method("hostGlobal", fn_ptr(host_global_ref))
    m.method("callMethod", fn_ptr(call_method_ref))
    m.method("callN", fn_ptr(call_n_ref))
    m.method("scopedCall", fn_ptr(scoped_call_ref))
    m.method("thenDouble", fn_ptr(then_double_ref))
    m.method("deferredRequire", fn_ptr(deferred_require_ref))
    m.method("thenScaled", fn_ptr(then_scaled_ref))

    _ = host_require_ref
    _ = host_argv_ref
    _ = host_console_log_ref
    _ = host_console_error_ref
    _ = host_global_ref
    _ = call_method_ref
    _ = call_n_ref
    _ = scoped_call_ref
    _ = then_double_ref
    _ = deferred_require_ref
    _ = then_scaled_ref
