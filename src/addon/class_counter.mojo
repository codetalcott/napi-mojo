## src/addon/class_counter.mojo — Counter class (constructor + methods + ClassRegistry)

from memory import alloc
from napi.types import NapiEnv, NapiValue, NAPI_TYPE_NUMBER, NAPI_TYPE_OBJECT, NAPI_TYPE_FUNCTION
from napi.bindings import NapiBindings, Bindings
from napi.error import throw_js_error, throw_js_type_error, check_status
from napi.raw import raw_wrap, raw_new_instance
from napi.framework.js_number import JsNumber
from napi.framework.js_boolean import JsBoolean
from napi.framework.js_undefined import JsUndefined
from napi.framework.js_object import JsObject
from napi.framework.js_class import unwrap_native, unwrap_native_from_this
from napi.framework.args import CbArgs
from napi.framework.js_value import js_typeof
from napi.framework.register import fn_ptr, ModuleBuilder, ClassRegistry

struct CounterData(Movable):
    var count: Float64
    var initial: Float64

    fn __init__(out self, initial: Float64):
        self.count = initial
        self.initial = initial

    fn __moveinit__(out self, deinit take: Self):
        self.count = take.count
        self.initial = take.initial

fn counter_finalize(env: NapiEnv, data: OpaquePointer[MutAnyOrigin], hint: OpaquePointer[MutAnyOrigin]):
    var ptr = data.bitcast[CounterData]()
    ptr.destroy_pointee()
    ptr.free()

fn counter_constructor_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var this_val = CbArgs.get_this(b, env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var t = js_typeof(b, env, arg0)
        if t != NAPI_TYPE_NUMBER:
            throw_js_type_error(b, env, "Counter constructor requires a number argument")
            return NapiValue()
        var initial = JsNumber.from_napi_value(b, env, arg0)
        var data_ptr = alloc[CounterData](1)
        data_ptr.init_pointee_move(CounterData(initial))
        var fin_ref = counter_finalize
        var fin_ptr = UnsafePointer(to=fin_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
        check_status(raw_wrap(b,
            env,
            this_val,
            data_ptr.bitcast[NoneType](),
            fin_ptr,
            OpaquePointer[MutAnyOrigin](),
            OpaquePointer[MutAnyOrigin](),
        ))
        return this_val
    except:
        throw_js_error(env, "Counter constructor failed")
        return NapiValue()

fn counter_get_value_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var a = CbArgs.get_bindings_and_this(env, info)
        var ptr = unwrap_native_from_this[CounterData](a.b, env, a.this_val)
        return JsNumber.create(a.b, env, ptr[].count).value
    except:
        throw_js_error(env, "Counter.value getter failed")
        return NapiValue()

fn counter_set_value_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var a = CbArgs.get_bindings_this_and_one(env, info)
        var t = js_typeof(a.b, env, a.arg0)
        if t != NAPI_TYPE_NUMBER:
            throw_js_type_error(a.b, env, "Counter.value setter requires a number")
            return NapiValue()
        var new_val = JsNumber.from_napi_value(a.b, env, a.arg0)
        var ptr = unwrap_native_from_this[CounterData](a.b, env, a.this_val)
        ptr[].count = new_val
        return JsUndefined.create(a.b, env).value
    except:
        throw_js_error(env, "Counter.value setter failed")
        return NapiValue()

fn counter_increment_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var a = CbArgs.get_bindings_and_this(env, info)
        var ptr = unwrap_native_from_this[CounterData](a.b, env, a.this_val)
        ptr[].count += 1.0
        return JsUndefined.create(a.b, env).value
    except:
        throw_js_error(env, "Counter.increment failed")
        return NapiValue()

fn counter_reset_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var a = CbArgs.get_bindings_and_this(env, info)
        var ptr = unwrap_native_from_this[CounterData](a.b, env, a.this_val)
        ptr[].count = ptr[].initial
        return JsUndefined.create(a.b, env).value
    except:
        throw_js_error(env, "Counter.reset failed")
        return NapiValue()

fn counter_is_counter_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var this_val = CbArgs.get_this(b, env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var t = js_typeof(b, env, arg0)
        if t != NAPI_TYPE_OBJECT and t != NAPI_TYPE_FUNCTION:
            return JsBoolean.create(b, env, False).value
        var result = JsObject(arg0).instance_of(b, env, this_val)
        return JsBoolean.create(b, env, result).value
    except:
        throw_js_error(env, "Counter.isCounter failed")
        return NapiValue()

fn counter_from_value_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var this_val = CbArgs.get_this(b, env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var t = js_typeof(b, env, arg0)
        if t != NAPI_TYPE_NUMBER:
            throw_js_type_error(b, env, "Counter.fromValue requires a number argument")
            return NapiValue()
        var result = NapiValue()
        var argv_ptr: OpaquePointer[ImmutAnyOrigin] = UnsafePointer(to=arg0).bitcast[NoneType]()
        check_status(raw_new_instance(b,
            env,
            this_val,
            1,
            argv_ptr,
            UnsafePointer(to=result).bitcast[NoneType](),
        ))
        return result
    except:
        throw_js_error(env, "Counter.fromValue failed")
        return NapiValue()

fn register_counter(mut m: ModuleBuilder, b: Bindings) raises:
    var counter_constructor_ref = counter_constructor_fn
    var counter_get_value_ref = counter_get_value_fn
    var counter_set_value_ref = counter_set_value_fn
    var counter_increment_ref = counter_increment_fn
    var counter_reset_ref = counter_reset_fn
    var counter_is_counter_ref = counter_is_counter_fn
    var counter_from_value_ref = counter_from_value_fn
    var counter = m.class_def("Counter", fn_ptr(counter_constructor_ref))
    counter.instance_method("increment", fn_ptr(counter_increment_ref))
    counter.instance_method("reset", fn_ptr(counter_reset_ref))
    counter.getter_setter("value", fn_ptr(counter_get_value_ref), fn_ptr(counter_set_value_ref))
    counter.static_method("isCounter", fn_ptr(counter_is_counter_ref))
    counter.static_method("fromValue", fn_ptr(counter_from_value_ref))
    # Set up ClassRegistry so new_instance("Counter", ...) works
    var registry = ClassRegistry()
    registry.register(b, counter.env, "Counter", counter.ctor)
    var registry_ptr = alloc[ClassRegistry](1)
    registry_ptr.init_pointee_move(registry^)
    b[].registry = registry_ptr.bitcast[NoneType]()
