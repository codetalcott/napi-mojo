## examples/counter-addon.mojo — Class-based napi-mojo addon
##
## Shows how to define a JS class backed by native Mojo data: constructor,
## instance methods, getter/setter, static method, and GC finalizer — using
## the type-tagged wrap/unwrap path (wrap_native + the NapiTypeTag-taking
## unwrap overloads), which makes cross-class method borrowing a TypeError
## instead of memory corruption.
##
## Build:  mojo build --emit shared-lib -I src examples/counter-addon.mojo \
##             -o build/counter.node
## Use:    const m = require('./build/counter.node')
##         const c = new m.Counter(10)
##         c.increment()       // c.value === 11
##         c.value = 99        // setter
##         Counter.isCounter(c) // true

from std.memory.alloc import unsafe_alloc
from napi.types import (
    NapiEnv,
    NapiValue,
    NapiTypeTag,
    NAPI_TYPE_NUMBER,
    NAPI_TYPE_OBJECT,
    NAPI_TYPE_FUNCTION,
)
from napi.bindings import NapiBindings, init_bindings
from napi.error import throw_js_error, throw_js_type_error
from napi.framework.js_number import JsNumber
from napi.framework.js_boolean import JsBoolean
from napi.framework.js_undefined import JsUndefined
from napi.framework.args import CbArgs
from napi.framework.js_value import js_typeof
from napi.framework.js_object import JsObject
from napi.framework.js_class import unwrap_native, wrap_native
from napi.framework.register import fn_ptr, ModuleBuilder


# 128-bit type tag stamped on every Counter instance by wrap_native and
# verified by every tagged unwrap. Pick fixed random constants per class.
comptime EXAMPLE_COUNTER_TAG_LOWER: UInt64 = 0x2D9C51E87A3F6B04
comptime EXAMPLE_COUNTER_TAG_UPPER: UInt64 = 0x6E1B08D4C5A2937F


# --- Native data struct ------------------------------------------------------
# Heap-allocated and wrapped onto the JS object via wrap_native.
# Must implement Movable so unsafe_alloc[T] + unsafe_write works.


struct CounterData(Movable):
    var count: Float64
    var initial: Float64

    def __init__(out self, initial: Float64):
        self.count = initial
        self.initial = initial


# --- GC finalizer ------------------------------------------------------------
# Called when the JS object is garbage-collected. Clean up the heap allocation.
# Signature must match: fn(NapiEnv, void* data, void* hint)


def counter_finalize(
    env: NapiEnv,
    data: OpaquePointer[MutAnyOrigin],
    hint: OpaquePointer[MutAnyOrigin],
):
    var ptr = data.unsafe_bitcast[CounterData]()
    ptr.unsafe_deinit_pointee()
    ptr.unsafe_free()


# --- Constructor -------------------------------------------------------------
# Called when JS does `new Counter(n)`.


def counter_constructor_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var this_val = CbArgs.get_this(b, env, info)
        var arg0 = CbArgs.get_one(b, env, info)

        var t = js_typeof(b, env, arg0)
        if t != NAPI_TYPE_NUMBER:
            throw_js_type_error(b, env, "Counter requires a number argument")
            return NapiValue(unsafe_from_address=Int(0))

        var initial = JsNumber.from_napi_value(b, env, arg0)

        # Heap-allocate native data, wrap onto `this`, and stamp the type tag
        var data_ptr = unsafe_alloc[CounterData](1)
        data_ptr.unsafe_write(CounterData(initial))
        var fin_ref = counter_finalize
        try:
            wrap_native(
                b,
                env,
                this_val,
                data_ptr.unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                fn_ptr(fin_ref),
                NapiTypeTag(
                    EXAMPLE_COUNTER_TAG_LOWER, EXAMPLE_COUNTER_TAG_UPPER
                ),
            )
        except e:
            # wrap_native raises with ownership returned to the caller
            data_ptr.unsafe_deinit_pointee()
            data_ptr.unsafe_free()
            raise e^

        return this_val
    except:
        throw_js_error(env, "Counter constructor failed")
        return NapiValue(unsafe_from_address=Int(0))


# --- Instance methods --------------------------------------------------------
# unwrap_native[T](b, env, info, tag) verifies the tag before casting, so a
# Counter method borrowed onto a foreign object throws a TypeError.


def counter_increment_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var ptr = unwrap_native[CounterData](
            b, env, info,
            NapiTypeTag(EXAMPLE_COUNTER_TAG_LOWER, EXAMPLE_COUNTER_TAG_UPPER),
        )
        ptr[].count += 1.0
        return JsUndefined.create(b, env).value
    except:
        throw_js_error(env, "Counter.increment failed")
        return NapiValue(unsafe_from_address=Int(0))


# --- Getter / Setter ---------------------------------------------------------


def counter_get_value_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var ptr = unwrap_native[CounterData](
            b, env, info,
            NapiTypeTag(EXAMPLE_COUNTER_TAG_LOWER, EXAMPLE_COUNTER_TAG_UPPER),
        )
        return JsNumber.create(b, env, ptr[].count).value
    except:
        throw_js_error(env, "Counter.value getter failed")
        return NapiValue(unsafe_from_address=Int(0))


def counter_set_value_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var ptr = unwrap_native[CounterData](
            b, env, info,
            NapiTypeTag(EXAMPLE_COUNTER_TAG_LOWER, EXAMPLE_COUNTER_TAG_UPPER),
        )
        var arg0 = CbArgs.get_one(b, env, info)
        ptr[].count = JsNumber.from_napi_value(b, env, arg0)
        return JsUndefined.create(b, env).value
    except:
        throw_js_error(env, "Counter.value setter failed")
        return NapiValue(unsafe_from_address=Int(0))


# --- Static method -----------------------------------------------------------


def counter_is_counter_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var this_val = CbArgs.get_this(
            b, env, info
        )  # `this` = Counter constructor
        var arg0 = CbArgs.get_one(b, env, info)

        var t = js_typeof(b, env, arg0)
        if t != NAPI_TYPE_OBJECT and t != NAPI_TYPE_FUNCTION:
            return JsBoolean.create(b, env, False).value

        var result = JsObject(arg0).instance_of(b, env, this_val)
        return JsBoolean.create(b, env, result).value
    except:
        throw_js_error(env, "Counter.isCounter failed")
        return NapiValue(unsafe_from_address=Int(0))


# --- Module entry point ------------------------------------------------------


@export("napi_register_module_v1")
def register_module(env: NapiEnv, exports: NapiValue) abi("C") -> NapiValue:
    var bindings_ptr = unsafe_alloc[NapiBindings](1)
    try:
        var bindings = NapiBindings()
        init_bindings(bindings)
        bindings_ptr.unsafe_write(bindings^)
    except:
        bindings_ptr.unsafe_free()
        throw_js_error(env, "counter-addon: failed to resolve N-API symbols")
        return exports
    var cb_data = bindings_ptr.unsafe_bitcast[NoneType]().as_unsafe_any_origin()

    # All function refs declared before try block (ASAP destruction safety)
    var ctor_ref = counter_constructor_fn
    var inc_ref = counter_increment_fn
    var get_val_ref = counter_get_value_fn
    var set_val_ref = counter_set_value_fn
    var is_counter_ref = counter_is_counter_fn

    try:
        var m = ModuleBuilder(env, exports, cb_data)

        # Define the Counter class and register its members
        var counter = m.class_def("Counter", fn_ptr(ctor_ref))
        counter.instance_method("increment", fn_ptr(inc_ref))
        counter.getter_setter("value", fn_ptr(get_val_ref), fn_ptr(set_val_ref))
        counter.static_method("isCounter", fn_ptr(is_counter_ref))
        m.flush()
    except:
        pass

    return exports
