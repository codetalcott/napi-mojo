## src/addon/function_ops.mojo — function creation, closures, varargs, named fns

from std.memory.alloc import unsafe_alloc
from napi.types import NapiEnv, NapiValue, NapiStore, NAPI_TYPE_NUMBER
from napi.bindings import NapiBindings, Bindings
from napi.error import throw_js_error, throw_js_error_dynamic, check_status
from napi.framework.js_string import JsString
from napi.framework.js_number import JsNumber
from napi.framework.js_function import JsFunction
from napi.framework.args import CbArgs
from napi.framework.js_value import js_typeof, js_type_name, js_get_global
from napi.framework.register import fn_ptr, ModuleBuilder, ClassRegistry
from napi.keepalive import pin_across_ffi


## AdderCapture — closure data for inner_adder_fn (captured n + bindings)
struct AdderCapture(Movable):
    var n: Float64
    var b_raw: NapiStore

    def __init__(out self, n: Float64, b: Bindings):
        self.n = n
        self.b_raw = b.unsafe_bitcast[NoneType]()

    def __moveinit__(out self, deinit take: Self):
        self.n = take.n
        self.b_raw = take.b_raw


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
        var raw_data = CbArgs.get_data(env, info)
        var cap = raw_data.unsafe_bitcast[AdderCapture]()
        var b = cap[].b_raw.unsafe_bitcast[NapiBindings]()
        var arg0 = CbArgs.get_one(b, env, info)
        var x = JsNumber.from_napi_value(b, env, arg0)
        return JsNumber.create(b, env, cap[].n + x).value
    except:
        throw_js_error(env, "adder callback failed")
        return NapiValue(unsafe_from_address=Int(0))


def create_adder_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var n = JsNumber.from_napi_value(b, env, arg0)
        var cap_ptr = unsafe_alloc[AdderCapture](1)
        cap_ptr.unsafe_write(AdderCapture(n, b))
        var cb_ref = inner_adder_fn
        var cb_ptr = Pointer(to=cb_ref).unsafe_bitcast[
            OpaquePointer[MutAnyOrigin]
        ]()[]
        return JsFunction.create_with_data(
            b, env, "adder", cb_ptr, cap_ptr.unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        ).value
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
