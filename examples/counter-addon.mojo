## examples/counter-addon.mojo — Class-based napi-mojo addon
##
## Shows how to define a JS class backed by native Mojo data: constructor,
## instance methods, getter/setter, static method, and GC finalizer.
##
## Build:  mojo build --emit shared-lib src/lib.mojo -o build/index.node
## Use:    const m = require('./build/index.node')
##         const c = new m.Counter(10)
##         c.increment()       // c.value === 11
##         c.value = 99        // setter
##         Counter.isCounter(c) // true

from std.memory import alloc
from napi.types import NapiEnv, NapiValue, NAPI_TYPE_NUMBER, NAPI_TYPE_OBJECT, NAPI_TYPE_FUNCTION
from napi.error import throw_js_error, throw_js_type_error, check_status
from napi.raw import raw_wrap
from napi.framework.js_number import JsNumber
from napi.framework.js_boolean import JsBoolean
from napi.framework.js_undefined import JsUndefined
from napi.framework.args import CbArgs
from napi.framework.js_value import js_typeof
from napi.framework.js_object import JsObject
from napi.framework.js_class import unwrap_native
from napi.framework.register import fn_ptr, ModuleBuilder


# Note on API style: this example uses ModuleBuilder(env, exports) without a
# NapiBindings pointer, so callbacks use the no-bindings CbArgs overloads
# (get_one(env, info), get_two(env, info), etc.). This is intentional for a
# minimal example. Production addons should pass NapiBindings through
# ModuleBuilder to enable cached function pointers (zero per-call dlsym).
# See src/lib.mojo and the "Cached NapiBindings" section of CLAUDE.md.

# --- Native data struct ------------------------------------------------------
# Heap-allocated and wrapped onto the JS object via napi_wrap.
# Must implement Movable so alloc[T] + init_pointee_move works.

struct CounterData(Movable):
    var count: Float64
    var initial: Float64

    def __init__(out self, initial: Float64):
        self.count = initial
        self.initial = initial

    def __moveinit__(out self, deinit take: Self):
        self.count = take.count
        self.initial = take.initial


# --- GC finalizer ------------------------------------------------------------
# Called when the JS object is garbage-collected. Clean up the heap allocation.
# Signature must match: fn(NapiEnv, void* data, void* hint)

def counter_finalize(
    env: NapiEnv,
    data: OpaquePointer[MutAnyOrigin],
    hint: OpaquePointer[MutAnyOrigin],
):
    var ptr = data.bitcast[CounterData]()
    ptr.destroy_pointee()
    ptr.free()


# --- Constructor -------------------------------------------------------------
# Called when JS does `new Counter(n)`.

def counter_constructor_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var this_val = CbArgs.get_this(env, info)
        var arg0 = CbArgs.get_one(env, info)

        var t = js_typeof(env, arg0)
        if t != NAPI_TYPE_NUMBER:
            throw_js_type_error(env, "Counter requires a number argument")
            return NapiValue()

        var initial = JsNumber.from_napi_value(env, arg0)

        # Heap-allocate native data and wrap onto `this`
        var data_ptr = alloc[CounterData](1)
        data_ptr.init_pointee_move(CounterData(initial))

        var fin_ref = counter_finalize
        var fin_ptr = UnsafePointer(to=fin_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]

        check_status(raw_wrap(
            env,
            this_val,
            data_ptr.bitcast[NoneType](),          # native_object
            fin_ptr,                                # finalize_cb
            OpaquePointer[MutAnyOrigin](),          # finalize_hint (NULL)
            OpaquePointer[MutAnyOrigin](),          # result ref (NULL)
        ))

        return this_val
    except:
        throw_js_error(env, "Counter constructor failed")
        return NapiValue()


# --- Instance methods --------------------------------------------------------
# Use unwrap_native[T](env, info) to retrieve the native data pointer from `this`.

def counter_increment_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var ptr = unwrap_native[CounterData](env, info)
        ptr[].count += 1.0
        return JsUndefined.create(env).value
    except:
        throw_js_error(env, "Counter.increment failed")
        return NapiValue()


# --- Getter / Setter ---------------------------------------------------------

def counter_get_value_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var ptr = unwrap_native[CounterData](env, info)
        return JsNumber.create(env, ptr[].count).value
    except:
        throw_js_error(env, "Counter.value getter failed")
        return NapiValue()

def counter_set_value_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var ptr = unwrap_native[CounterData](env, info)
        var arg0 = CbArgs.get_one(env, info)
        ptr[].count = JsNumber.from_napi_value(env, arg0)
        return JsUndefined.create(env).value
    except:
        throw_js_error(env, "Counter.value setter failed")
        return NapiValue()


# --- Static method -----------------------------------------------------------

def counter_is_counter_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var this_val = CbArgs.get_this(env, info)  # `this` = Counter constructor
        var arg0 = CbArgs.get_one(env, info)

        var t = js_typeof(env, arg0)
        if t != NAPI_TYPE_OBJECT and t != NAPI_TYPE_FUNCTION:
            return JsBoolean.create(env, False).value

        var result = JsObject(arg0).instance_of(env, this_val)
        return JsBoolean.create(env, result).value
    except:
        throw_js_error(env, "Counter.isCounter failed")
        return NapiValue()


# --- Module entry point ------------------------------------------------------

@export("napi_register_module_v1", ABI="C")
def register_module(env: NapiEnv, exports: NapiValue) -> NapiValue:
    # All function refs declared before try block (ASAP destruction safety)
    var ctor_ref = counter_constructor_fn
    var inc_ref = counter_increment_fn
    var get_val_ref = counter_get_value_fn
    var set_val_ref = counter_set_value_fn
    var is_counter_ref = counter_is_counter_fn

    try:
        var m = ModuleBuilder(env, exports)

        # Define the Counter class and register its members
        var counter = m.class_def("Counter", fn_ptr(ctor_ref))
        counter.instance_method("increment", fn_ptr(inc_ref))
        counter.getter_setter("value", fn_ptr(get_val_ref), fn_ptr(set_val_ref))
        counter.static_method("isCounter", fn_ptr(is_counter_ref))
    except:
        pass

    return exports
