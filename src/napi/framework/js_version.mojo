## src/napi/framework/js_version.mojo — N-API and Node.js version detection
##
## Provides runtime version queries:
##   - get_napi_version(): highest N-API version supported
##   - get_node_version_fields(): Node.js major/minor/patch read directly
##
## Usage:
##   var napi_ver = get_napi_version(env)  # e.g., 9

from napi.types import NapiEnv, NapiNodeVersion
from napi.bindings import Bindings
from napi.raw import raw_get_version, raw_get_node_version, raw_add_async_cleanup_hook, raw_remove_async_cleanup_hook, raw_get_uv_event_loop
from napi.error import check_status

## get_napi_version — return the highest N-API version supported by this runtime
fn get_napi_version(env: NapiEnv) raises -> UInt32:
    var result: UInt32 = 0
    var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
    check_status(raw_get_version(env, result_ptr))
    return result

## get_node_version_ptr — return a pointer to the static NapiNodeVersion struct
##
## napi_get_node_version writes a const napi_node_version* into our out-param.
## Returns the raw pointer; caller reads fields via UnsafePointer offsets.
fn get_node_version_ptr(env: NapiEnv) raises -> UnsafePointer[UInt32, MutAnyOrigin]:
    # The API writes a pointer-to-struct into our out variable
    var ptr_val = OpaquePointer[MutAnyOrigin]()
    var out_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=ptr_val).bitcast[NoneType]()
    check_status(raw_get_node_version(env, out_ptr))
    # The struct starts with three UInt32 fields (major, minor, patch)
    # Cast to UInt32* for direct field access
    return ptr_val.bitcast[UInt32]()

# --- Bindings-aware overloads ---

fn get_napi_version(b: Bindings, env: NapiEnv) raises -> UInt32:
    var result: UInt32 = 0
    var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
    check_status(raw_get_version(b, env, result_ptr))
    return result

fn get_node_version_ptr(b: Bindings, env: NapiEnv) raises -> UnsafePointer[UInt32, MutAnyOrigin]:
    var ptr_val = OpaquePointer[MutAnyOrigin]()
    var out_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=ptr_val).bitcast[NoneType]()
    check_status(raw_get_node_version(b, env, out_ptr))
    return ptr_val.bitcast[UInt32]()

## add_async_cleanup_hook — register an async cleanup hook (N-API v8)
##
## The hook fires after the event loop drains on environment teardown.
## Returns an opaque handle that can be passed to remove_async_cleanup_hook.
## hook_cb: fn(handle, arg) — called with the handle and the arg pointer.
fn add_async_cleanup_hook(
    b: Bindings,
    env: NapiEnv,
    hook_cb: OpaquePointer[MutAnyOrigin],
    arg: OpaquePointer[MutAnyOrigin],
) raises -> OpaquePointer[MutAnyOrigin]:
    var handle = OpaquePointer[MutAnyOrigin]()
    var handle_out: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=handle).bitcast[NoneType]()
    check_status(raw_add_async_cleanup_hook(b, env, hook_cb, arg, handle_out))
    return handle

## remove_async_cleanup_hook — unregister an async cleanup hook (N-API v8)
##
## Uses the handle returned by add_async_cleanup_hook. No env needed.
fn remove_async_cleanup_hook(
    b: Bindings,
    handle: OpaquePointer[MutAnyOrigin],
) raises:
    check_status(raw_remove_async_cleanup_hook(b, handle))

## get_uv_event_loop — return the libuv event loop for the environment (N-API v2)
##
## Returns the uv_loop_t* as an opaque pointer. Useful for addons that
## integrate directly with libuv timers or I/O. Valid for env lifetime.
fn get_uv_event_loop(
    b: Bindings,
    env: NapiEnv,
) raises -> OpaquePointer[MutAnyOrigin]:
    var loop_ptr = OpaquePointer[MutAnyOrigin]()
    var out_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=loop_ptr).bitcast[NoneType]()
    check_status(raw_get_uv_event_loop(b, env, out_ptr))
    return loop_ptr
