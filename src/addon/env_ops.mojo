## src/addon/env_ops.mojo — instance data, cleanup hooks, UV event loop,
##                           coerce ops

from std.memory import alloc
from napi.types import NapiEnv, NapiValue
from napi.bindings import Bindings, NapiBindings
from napi.error import throw_js_error, check_status
from napi.raw import (
    raw_set_instance_data,
    raw_get_instance_data,
    raw_add_env_cleanup_hook,
    raw_remove_env_cleanup_hook,
    raw_remove_async_cleanup_hook,
)
from napi.framework.js_number import JsNumber
from napi.framework.js_boolean import JsBoolean
from napi.framework.js_null import JsNull
from napi.framework.js_undefined import JsUndefined
from napi.framework.js_bigint import JsBigInt
from napi.framework.js_coerce import (
    js_coerce_to_bool,
    js_coerce_to_number,
    js_coerce_to_string,
    js_coerce_to_object,
)
from napi.framework.args import CbArgs
from napi.framework.js_version import (
    add_async_cleanup_hook,
    remove_async_cleanup_hook,
    get_uv_event_loop,
)
from napi.framework.register import fn_ptr, ModuleBuilder


## NOTE: the actual instance_data_finalize body lives in src/lib.mojo as
## @export("napi_mojo_instance_data_finalize_impl", ABI="C"). The C
## trampoline in src/napi_callbacks.c has its address; we read the
## pointer from b[].instance_data_finalize_ptr instead of using the
## (broken-on-1.0.0b1) `var f = fn; UnsafePointer(to=f)...` extraction.


def set_instance_data_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var n = JsNumber.from_napi_value(b, env, arg0)
        var data_ptr = alloc[Float64](1)
        data_ptr.init_pointee_move(n)
        # DIAGNOSTIC: pass NULL finalize_cb instead of our trampoline, to
        # isolate whether the Linux SIGSEGV in instance_data.test.js is
        # specifically about the finalizer firing at env teardown.
        check_status(
            raw_set_instance_data(
                b,
                env,
                data_ptr.bitcast[NoneType](),
                OpaquePointer[MutAnyOrigin](),  # NULL finalize_cb
                OpaquePointer[MutAnyOrigin](),
            )
        )
        return JsUndefined.create(b, env).value
    except:
        throw_js_error(env, "setInstanceData failed")
        return NapiValue()


def get_instance_data_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var data = OpaquePointer[MutAnyOrigin]()
        check_status(
            raw_get_instance_data(
                b, env, UnsafePointer(to=data).bitcast[NoneType]()
            )
        )
        if Int(data) == 0:
            return JsNull.create(b, env).value
        var ptr = data.bitcast[Float64]()
        return JsNumber.create(b, env, ptr[]).value
    except:
        throw_js_error(env, "getInstanceData failed")
        return NapiValue()


def cleanup_hook_noop(arg: OpaquePointer[MutAnyOrigin]):
    pass


def add_cleanup_hook_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var hook_ref = cleanup_hook_noop
        var hook_ptr = UnsafePointer(to=hook_ref).bitcast[
            OpaquePointer[MutAnyOrigin]
        ]()[]
        var arg_ptr = alloc[Byte](1)
        arg_ptr[0] = Byte(0)
        check_status(
            raw_add_env_cleanup_hook(
                b, env, hook_ptr, arg_ptr.bitcast[NoneType]()
            )
        )
        return JsBoolean.create(b, env, True).value
    except:
        throw_js_error(env, "addCleanupHook failed")
        return NapiValue()


def remove_cleanup_hook_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var hook_ref = cleanup_hook_noop
        var hook_ptr = UnsafePointer(to=hook_ref).bitcast[
            OpaquePointer[MutAnyOrigin]
        ]()[]
        var arg_ptr = alloc[Byte](1)
        arg_ptr[0] = Byte(0)
        check_status(
            raw_add_env_cleanup_hook(
                b, env, hook_ptr, arg_ptr.bitcast[NoneType]()
            )
        )
        check_status(
            raw_remove_env_cleanup_hook(
                b, env, hook_ptr, arg_ptr.bitcast[NoneType]()
            )
        )
        arg_ptr.free()
        return JsBoolean.create(b, env, True).value
    except:
        throw_js_error(env, "removeCleanupHook failed")
        return NapiValue()


## async_cleanup_hook_noop — env-exit cleanup callback that immediately releases
##
## N-API contract: async cleanup hooks MUST call napi_remove_async_cleanup_hook
## with the supplied handle, otherwise env teardown blocks indefinitely.
## We pass our own NapiBindings pointer as `arg` (set by the registering
## callback below) so we can use the bindings-aware overload and avoid
## an env-teardown dlsym (which intermittently fails on Linux).
def async_cleanup_hook_noop(
    handle: OpaquePointer[MutAnyOrigin], arg: OpaquePointer[MutAnyOrigin]
):
    var b = arg.bitcast[NapiBindings]()
    _ = raw_remove_async_cleanup_hook(b, handle)


def add_async_cleanup_hook_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var hook_ref = async_cleanup_hook_noop
        var hook_ptr = UnsafePointer(to=hook_ref).bitcast[
            OpaquePointer[MutAnyOrigin]
        ]()[]
        _ = add_async_cleanup_hook(b, env, hook_ptr, b.bitcast[NoneType]())
        return JsBoolean.create(b, env, True).value
    except:
        throw_js_error(env, "addAsyncCleanupHook failed")
        return NapiValue()


def remove_async_cleanup_hook_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var hook_ref = async_cleanup_hook_noop
        var hook_ptr = UnsafePointer(to=hook_ref).bitcast[
            OpaquePointer[MutAnyOrigin]
        ]()[]
        var handle = add_async_cleanup_hook(
            b, env, hook_ptr, b.bitcast[NoneType]()
        )
        remove_async_cleanup_hook(b, handle)
        return JsBoolean.create(b, env, True).value
    except:
        throw_js_error(env, "removeAsyncCleanupHook failed")
        return NapiValue()


def get_uv_event_loop_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var loop_ptr = get_uv_event_loop(b, env)
        return JsBigInt.from_uint64(
            b, env, UInt64(Int(loop_ptr.bitcast[UInt8]()))
        ).value
    except:
        throw_js_error(env, "getUvEventLoop failed")
        return NapiValue()


def coerce_to_bool_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        return js_coerce_to_bool(b, env, arg0)
    except:
        throw_js_error(env, "coerceToBool requires one argument")
        return NapiValue()


def coerce_to_number_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        return js_coerce_to_number(b, env, arg0)
    except:
        return NapiValue()


def coerce_to_string_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        return js_coerce_to_string(b, env, arg0)
    except:
        return NapiValue()


def coerce_to_object_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        return js_coerce_to_object(b, env, arg0)
    except:
        return NapiValue()


def register_env(mut m: ModuleBuilder) raises:
    var set_instance_data_ref = set_instance_data_fn
    var get_instance_data_ref = get_instance_data_fn
    var add_cleanup_hook_ref = add_cleanup_hook_fn
    var remove_cleanup_hook_ref = remove_cleanup_hook_fn
    var add_async_cleanup_hook_fn_ref = add_async_cleanup_hook_fn
    var remove_async_cleanup_hook_fn_ref = remove_async_cleanup_hook_fn
    var get_uv_event_loop_fn_ref = get_uv_event_loop_fn
    var coerce_to_bool_ref = coerce_to_bool_fn
    var coerce_to_number_ref = coerce_to_number_fn
    var coerce_to_string_ref = coerce_to_string_fn
    var coerce_to_object_ref = coerce_to_object_fn
    m.method("setInstanceData", fn_ptr(set_instance_data_ref))
    m.method("getInstanceData", fn_ptr(get_instance_data_ref))
    m.method("addCleanupHook", fn_ptr(add_cleanup_hook_ref))
    m.method("removeCleanupHook", fn_ptr(remove_cleanup_hook_ref))
    m.method("addAsyncCleanupHook", fn_ptr(add_async_cleanup_hook_fn_ref))
    m.method("removeAsyncCleanupHook", fn_ptr(remove_async_cleanup_hook_fn_ref))
    m.method("getUvEventLoop", fn_ptr(get_uv_event_loop_fn_ref))
    m.method("coerceToBool", fn_ptr(coerce_to_bool_ref))
    m.method("coerceToNumber", fn_ptr(coerce_to_number_ref))
    m.method("coerceToString", fn_ptr(coerce_to_string_ref))
    m.method("coerceToObject", fn_ptr(coerce_to_object_ref))
