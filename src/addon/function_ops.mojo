## src/addon/function_ops.mojo — function creation, closures, varargs, named fns

from std.memory.alloc import unsafe_alloc
from napi.types import NapiEnv, NapiValue, NapiRef, NAPI_TYPE_NUMBER
from napi.bindings import Bindings
from napi.error import throw_js_error, throw_js_error_dynamic, check_status
from napi.framework.js_string import JsString
from napi.framework.js_number import JsNumber
from napi.framework.js_function import JsFunction
from napi.framework.args import CbArgs
from napi.framework.js_arraybuffer import JsArrayBuffer
from napi.framework.js_ref import JsRef
from addon.typed_helpers_ops import TypedPayload, typed_payload_finalize
from napi.framework.js_value import js_typeof, js_type_name, js_get_global
from napi.framework.register import fn_ptr, ModuleBuilder, ClassRegistry
from napi.keepalive import pin_across_ffi


def inner_callback_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        return JsString.create_literal(b, env, "hello from callback").value
    except:
        return NapiValue(unsafe_from_address=Int(0))


def create_callback_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var cb_ref = inner_callback_fn
        var cb_ptr = Pointer(to=cb_ref).unsafe_bitcast[
            OpaquePointer[MutAnyOrigin]
        ]()[]
        return JsFunction.create_with_data(
            b, env, "innerCallback", cb_ptr, b.unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        ).value
    except:
        throw_js_error(env, "createCallback failed")
        return NapiValue(unsafe_from_address=Int(0))


def inner_adder_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var payload = CbArgs.get_data(env, info).unsafe_bitcast[TypedPayload]()
        var b = Bindings(unsafe_from_address=payload[].bindings_addr)
        var arg0 = CbArgs.get_one(b, env, info)
        var x = JsNumber.from_napi_value(b, env, arg0)
        return JsNumber.create(b, env, payload[].value + x).value
    except:
        throw_js_error(env, "adder callback failed")
        return NapiValue(unsafe_from_address=Int(0))


## createAdder(n, counter?) — the closure pattern: a function carrying heap data.
## The capture (n plus the bindings address) is freed by the collector through
## JsFunction.create_with_data's finalize_cb overload, never on the call path —
## an adder may be called many times or never. `counter` is optional: tests pass
## an ArrayBuffer(8) whose Int64 the capture's finalizer increments (the
## TypedPayload pattern), which is how a leak here becomes a failing test.
def create_adder_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var n: Float64
        var counter_ptr = Pointer[Int64, MutAnyOrigin](unsafe_from_address=Int(0))
        var counter_ref = NapiRef(unsafe_from_address=Int(0))
        if CbArgs.argc(b, env, info) >= 2:
            var args = CbArgs.get_two(b, env, info)
            n = JsNumber.from_napi_value(b, env, args[0])
            counter_ptr = JsArrayBuffer(args[1]).data_ptr(b, env).unsafe_bitcast[
                Int64
            ]()
            # Pin the counter's ArrayBuffer until the finalizer has incremented
            # it; typed_payload_finalize releases this ref afterwards.
            counter_ref = JsRef.create(b, env, args[1], 1).handle
        else:
            n = JsNumber.from_napi_value(b, env, CbArgs.get_one(b, env, info))

        var payload = unsafe_alloc[TypedPayload](1)
        payload.unsafe_write(TypedPayload(n, counter_ptr, counter_ref, Int(b)))
        var cb_ref = inner_adder_fn
        var fin_ref = typed_payload_finalize
        var adder = JsFunction.create_with_data(
            b,
            env,
            "adder",
            fn_ptr(cb_ref),
            payload.unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            fn_ptr(fin_ref),
        )
        _ = cb_ref
        _ = fin_ref
        return adder.value
    except:
        throw_js_error(env, "createAdder requires one number argument")
        return NapiValue(unsafe_from_address=Int(0))


def sum_args_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var count = CbArgs.argc(b, env, info)
        if count == 0:
            return JsNumber.create(b, env, 0.0).value
        var argv = unsafe_alloc[NapiValue](Int(count))
        _ = CbArgs.get_argv(b, env, info, count, argv.as_unsafe_any_origin())
        var total: Float64 = 0.0
        for i in range(Int(count)):
            var t = js_typeof(b, env, argv[unsafe_offset=i])
            if t != NAPI_TYPE_NUMBER:
                argv.unsafe_free()
                throw_js_error_dynamic(
                    b, env, "sumArgs: expected number, got " + js_type_name(t)
                )
                return NapiValue(unsafe_from_address=Int(0))
            total += JsNumber.from_napi_value(b, env, argv[unsafe_offset=i])
        argv.unsafe_free()
        return JsNumber.create(b, env, total).value
    except:
        throw_js_error(env, "sumArgs failed")
        return NapiValue(unsafe_from_address=Int(0))


def get_global_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        return js_get_global(b, env).value
    except:
        throw_js_error(env, "getGlobal failed")
        return NapiValue(unsafe_from_address=Int(0))


def create_named_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var cb_ref = inner_callback_fn
        var name = String("myFn")
        var func = JsFunction.create_named(
            b, env, name, 2, fn_ptr(cb_ref), b.unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        )
        return func.value
    except:
        throw_js_error(env, "createNamedFn failed")
        return NapiValue(unsafe_from_address=Int(0))


def new_counter_from_registry_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        # The registry slot is written by register_counter (see lib.mojo's
        # registration order) — dereferencing it unchecked would segfault
        # Node if that order ever changed. Fail as a JS error instead.
        if Int(b[].registry) == 0:
            throw_js_error(
                env, "newCounterFromRegistry: ClassRegistry not initialized"
            )
            return NapiValue(unsafe_from_address=Int(0))
        var registry = b[].registry.unsafe_bitcast[ClassRegistry]()
        var argv_ptr: OpaquePointer[ImmutAnyOrigin] = Pointer(
            to=arg0
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var instance = registry[].new_instance(b, env, "Counter", 1, argv_ptr)
        pin_across_ffi(arg0)  # napi reads argv during the nested call
        return instance
    except:
        throw_js_error(env, "newCounterFromRegistry failed")
        return NapiValue(unsafe_from_address=Int(0))


def register_functions(mut m: ModuleBuilder) raises:
    var sum_args_ref = sum_args_fn
    var create_callback_ref = create_callback_fn
    var create_adder_ref = create_adder_fn
    var get_global_ref = get_global_fn
    var create_named_fn_ref = create_named_fn
    var new_counter_from_registry_ref = new_counter_from_registry_fn
    m.method("sumArgs", fn_ptr(sum_args_ref))
    m.method("createCallback", fn_ptr(create_callback_ref))
    m.method("createAdder", fn_ptr(create_adder_ref))
    m.method("getGlobal", fn_ptr(get_global_ref))
    m.method("createNamedFn", fn_ptr(create_named_fn_ref))
    m.method("newCounterFromRegistry", fn_ptr(new_counter_from_registry_ref))
