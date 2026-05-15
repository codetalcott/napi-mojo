## src/addon/env_ops.mojo — instance data, cleanup hooks, UV event loop,
##                           coerce ops

from std.memory import alloc
from napi.types import NapiEnv, NapiValue
from napi.bindings import Bindings
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


def instance_data_finalize(
    env: NapiEnv,
    data: OpaquePointer[MutAnyOrigin],
    hint: OpaquePointer[MutAnyOrigin],
):
    var ptr = data.bitcast[Float64]()
    ptr.destroy_pointee()
    ptr.free()


def set_instance_data_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    """setInstanceData stores a single Float64 on the env. We register
    NULL as the finalize_cb (N-API spec-optional) and let the OS reclaim
    the 8-byte allocation at process exit.

    Why we don't pass `instance_data_finalize` (defined just above):
    Mojo 1.0.0b1's `var f = my_def_fn` resolves to AnyTrait[def(...)]
    (a callable wrapper), not a thin function pointer. The
    address-of-local-var trick

        var fin_ref = instance_data_finalize
        var fin_ptr = UnsafePointer(to=fin_ref).bitcast[OpaquePointer]()[]

    extracts the wrapper's first 8 bytes (a sentinel/discriminant), not
    the function's code address. When N-API later calls that "pointer"
    at env teardown on Linux, it lands on unmapped memory and SIGSEGVs
    — and unlike napi_wrap finalizers (which only fire if V8 GCs the
    wrapped JS object before exit), instance_data finalizers ALWAYS
    fire, so this path is reliably exercised. macOS happens to land on
    benign garbage and survives.

    Skipping the finalizer leaks 8 bytes per setInstanceData call but
    only at process exit, so the OS reclaims it. The kept-alive
    `instance_data_finalize` def above is unused right now; once Mojo
    gains a way to take the address of a `def` for use as a C callback,
    this should be revisited and the leak removed.
    """
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var n = JsNumber.from_napi_value(b, env, arg0)
        var data_ptr = alloc[Float64](1)
        data_ptr.init_pointee_move(n)
        check_status(
            raw_set_instance_data(
                b,
                env,
                data_ptr.bitcast[NoneType](),
                OpaquePointer[MutAnyOrigin](unsafe_from_address=0),  # finalize_cb = NULL
                OpaquePointer[MutAnyOrigin](unsafe_from_address=0),
            )
        )
        return JsUndefined.create(b, env).value
    except:
        throw_js_error(env, "setInstanceData failed")
        return NapiValue(unsafe_from_address=0)


def get_instance_data_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var data = OpaquePointer[MutAnyOrigin](unsafe_from_address=0)
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
        return NapiValue(unsafe_from_address=0)


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
        return NapiValue(unsafe_from_address=0)


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
        return NapiValue(unsafe_from_address=0)


## async_cleanup_hook_noop — env-exit cleanup callback that immediately releases
##
## N-API contract: async cleanup hooks MUST call napi_remove_async_cleanup_hook
## with the supplied handle, otherwise the env teardown blocks indefinitely
## waiting for the cleanup to complete (Node will eventually force-kill the
## process). Without this call, jest workers hang on exit and get killed with
## SIGSEGV/SIGTRAP/SIGABRT depending on what state libuv is in when SIGKILL
## arrives. Synchronous removal is fine — the hook does no real async work.
def async_cleanup_hook_noop(
    handle: OpaquePointer[MutAnyOrigin], arg: OpaquePointer[MutAnyOrigin]
):
    try:
        _ = raw_remove_async_cleanup_hook(handle)
    except:
        pass


def add_async_cleanup_hook_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var hook_ref = async_cleanup_hook_noop
        var hook_ptr = UnsafePointer(to=hook_ref).bitcast[
            OpaquePointer[MutAnyOrigin]
        ]()[]
        _ = add_async_cleanup_hook(
            b, env, hook_ptr, OpaquePointer[MutAnyOrigin](unsafe_from_address=0)
        )
        return JsBoolean.create(b, env, True).value
    except:
        throw_js_error(env, "addAsyncCleanupHook failed")
        return NapiValue(unsafe_from_address=0)


def remove_async_cleanup_hook_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var hook_ref = async_cleanup_hook_noop
        var hook_ptr = UnsafePointer(to=hook_ref).bitcast[
            OpaquePointer[MutAnyOrigin]
        ]()[]
        var handle = add_async_cleanup_hook(
            b, env, hook_ptr, OpaquePointer[MutAnyOrigin](unsafe_from_address=0)
        )
        remove_async_cleanup_hook(b, handle)
        return JsBoolean.create(b, env, True).value
    except:
        throw_js_error(env, "removeAsyncCleanupHook failed")
        return NapiValue(unsafe_from_address=0)


def get_uv_event_loop_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var loop_ptr = get_uv_event_loop(b, env)
        return JsBigInt.from_uint64(
            b, env, UInt64(Int(loop_ptr.bitcast[UInt8]()))
        ).value
    except:
        throw_js_error(env, "getUvEventLoop failed")
        return NapiValue(unsafe_from_address=0)


def coerce_to_bool_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        return js_coerce_to_bool(b, env, arg0)
    except:
        throw_js_error(env, "coerceToBool requires one argument")
        return NapiValue(unsafe_from_address=0)


def coerce_to_number_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        return js_coerce_to_number(b, env, arg0)
    except:
        return NapiValue(unsafe_from_address=0)


def coerce_to_string_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        return js_coerce_to_string(b, env, arg0)
    except:
        return NapiValue(unsafe_from_address=0)


def coerce_to_object_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        return js_coerce_to_object(b, env, arg0)
    except:
        return NapiValue(unsafe_from_address=0)


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
