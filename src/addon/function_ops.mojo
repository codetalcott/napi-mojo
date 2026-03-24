## src/addon/function_ops.mojo — function creation, closures, varargs, named fns

from std.memory import alloc
from napi.types import NapiEnv, NapiValue, NAPI_TYPE_NUMBER
from napi.bindings import NapiBindings, Bindings
from napi.error import throw_js_error, throw_js_error_dynamic, check_status
from napi.framework.js_string import JsString
from napi.framework.js_number import JsNumber
from napi.framework.js_function import JsFunction
from napi.framework.args import CbArgs
from napi.framework.js_value import js_typeof, js_type_name, js_get_global
from napi.framework.register import fn_ptr, ModuleBuilder, ClassRegistry

## AdderCapture — closure data for inner_adder_fn (captured n + bindings)
struct AdderCapture(Movable):
    var n: Float64
    var b_raw: OpaquePointer[MutAnyOrigin]

    def __init__(out self, n: Float64, b: Bindings):
        self.n = n
        self.b_raw = b.bitcast[NoneType]()

    def __moveinit__(out self, deinit take: Self):
        self.n = take.n
        self.b_raw = take.b_raw

def inner_callback_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        return JsString.create_literal(b, env, "hello from callback").value
    except:
        return NapiValue()

def create_callback_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var cb_ref = inner_callback_fn
        var cb_ptr = UnsafePointer(to=cb_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
        return JsFunction.create_with_data(b, env, "innerCallback", cb_ptr,
            b.bitcast[NoneType]()).value
    except:
        throw_js_error(env, "createCallback failed")
        return NapiValue()

def inner_adder_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var raw_data = CbArgs.get_data(env, info)
        var cap = raw_data.bitcast[AdderCapture]()
        var b = cap[].b_raw.bitcast[NapiBindings]()
        var arg0 = CbArgs.get_one(b, env, info)
        var x = JsNumber.from_napi_value(b, env, arg0)
        return JsNumber.create(b, env, cap[].n + x).value
    except:
        throw_js_error(env, "adder callback failed")
        return NapiValue()

def create_adder_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var n = JsNumber.from_napi_value(b, env, arg0)
        var cap_ptr = alloc[AdderCapture](1)
        cap_ptr.init_pointee_move(AdderCapture(n, b))
        var cb_ref = inner_adder_fn
        var cb_ptr = UnsafePointer(to=cb_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
        return JsFunction.create_with_data(b,
            env, "adder", cb_ptr, cap_ptr.bitcast[NoneType]()
        ).value
    except:
        throw_js_error(env, "createAdder requires one number argument")
        return NapiValue()

def sum_args_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var count = CbArgs.argc(b, env, info)
        if count == 0:
            return JsNumber.create(b, env, 0.0).value
        var argv = alloc[NapiValue](Int(count))
        CbArgs.get_argv(b, env, info, count, argv)
        var total: Float64 = 0.0
        for i in range(Int(count)):
            var t = js_typeof(b, env, argv[i])
            if t != NAPI_TYPE_NUMBER:
                argv.free()
                throw_js_error_dynamic(b, env, "sumArgs: expected number, got " + js_type_name(t))
                return NapiValue()
            total += JsNumber.from_napi_value(b, env, argv[i])
        argv.free()
        return JsNumber.create(b, env, total).value
    except:
        throw_js_error(env, "sumArgs failed")
        return NapiValue()

def get_global_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        return js_get_global(b, env).value
    except:
        throw_js_error(env, "getGlobal failed")
        return NapiValue()

def create_named_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var cb_ref = inner_callback_fn
        var name = String("myFn")
        var func = JsFunction.create_named(b, env, name, 2, fn_ptr(cb_ref), b.bitcast[NoneType]())
        return func.value
    except:
        throw_js_error(env, "createNamedFn failed")
        return NapiValue()

def new_counter_from_registry_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var registry = b[].registry.bitcast[ClassRegistry]()
        var argv_ptr: OpaquePointer[ImmutAnyOrigin] = UnsafePointer(to=arg0).bitcast[NoneType]()
        return registry[].new_instance(b, env, "Counter", 1, argv_ptr)
    except:
        throw_js_error(env, "newCounterFromRegistry failed")
        return NapiValue()

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
