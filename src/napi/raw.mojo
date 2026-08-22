## src/napi/raw.mojo — raw N-API FFI bindings via host process symbol lookup
##
## This is the ONLY file in the project allowed to use OwnedDLHandle directly.
## All other code must go through these raw_* wrapper functions.
##
## N-API symbols (napi_create_string_utf8, napi_define_properties, etc.) are
## not in libc — they live in the Node.js host process. When Node.js dlopen()s
## our .node file, those symbols are already in the process address space.
##
## Nearly every wrapper here takes `b: Bindings` and calls through the cached
## function pointer resolved once at module init (see bindings.mojo) — no
## per-call dlsym. Exactly FIVE wrappers keep a per-call OwnedDLHandle()
## (dlopen(NULL) + dlsym) path and are marked `raises` for the resolution
## failure:
##   - raw_get_cb_info: the per-callback bootstrap that fetches the bindings
##     pointer from callback data — by definition it runs before bindings
##     are available.
##   - raw_throw_error / raw_throw_type_error / raw_throw_range_error /
##     raw_throw_syntax_error: the except-block fallback surface (error.mojo's
##     env-only throw helpers), used when bindings retrieval itself failed.
## The env-only overload surface that used to duplicate every wrapper was
## deleted once TSFN context, finalize hints, and async data structs all
## carried the bindings pointer (see CLAUDE.md, "Cached NapiBindings").

from std.ffi import OwnedDLHandle
from napi.global_cache import cached_cb_info_addr, cache_cb_info_addr
from napi.types import (
    NapiEnv,
    NapiValue,
    NapiStatus,
    NapiAsyncContext,
    NapiAsyncWork,
    NapiCallbackScope,
    NapiDeferred,
    NapiEscapableHandleScope,
    NapiHandleScope,
    NapiRef,
    NapiThreadsafeFunction,
)
from napi.bindings import NapiBindings, Bindings


## _sym — resolve a host-process symbol as a callable C function pointer.
##
## This is the ONLY place the address-reinterpret is spelled. Do not inline it
## at call sites: `get_symbol` returns the symbol's ADDRESS AS A VALUE, so the
## machine word holding that address is what must be reinterpreted —
##
##     Pointer(to=addr).unsafe_bitcast[F]()[]   # correct
##     addr.unsafe_bitcast[F]()[]                     # WRONG: loads the function's
##                                             # first 8 bytes of machine code
##                                             # and calls THAT as a pointer
##
## Both compile, and the wrong one fails as a jump to garbage with no compiler
## signal. Keeping it in one function is what makes 130 call sites safe.
##
## `F` must be a `thin abi("C")` function type: `thin` makes it a bare pointer
## (satisfying TrivialRegisterPassable), `abi("C")` makes argument passing
## correct. Validated end-to-end in spike/ffi_probe.mojo.
##
## Replaces `OwnedDLHandle.get_function`, whose parameter became the return
## type and whose result is an origin-carrying callable that cannot be stored
## in a NapiBindings field.
@always_inline
def _sym[F: TrivialRegisterPassable](
    ref h: OwnedDLHandle, name: StaticString
) raises -> F:
    var opt = h.get_symbol[NoneType](name)
    if opt is None:
        raise Error("napi-mojo: symbol not found: ", name)
    var addr = opt.value()
    return Pointer(to=addr).unsafe_bitcast[F]()[]


def raw_create_string_utf8(
    b: Bindings,
    env: NapiEnv,
    str_ptr: OpaquePointer[ImmutAnyOrigin],
    length: UInt,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].create_string_utf8).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[ImmutAnyOrigin],
            UInt,
            OpaquePointer[MutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), str_ptr, length, result)


def raw_create_object(
    b: Bindings,
    env: NapiEnv,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].create_object).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), result)


def raw_set_named_property(
    b: Bindings,
    env: NapiEnv,
    object: NapiValue,
    utf8name: OpaquePointer[ImmutAnyOrigin],
    value: NapiValue,
) -> NapiStatus:
    var f = Pointer(to=b[].set_named_property).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[ImmutAnyOrigin], OpaquePointer[MutAnyOrigin]
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), object.as_unsafe_any_origin(), utf8name, value.as_unsafe_any_origin())


## raw_get_cb_info — wraps napi_get_cb_info
##
## Extracts callback arguments and this-value from a napi_callback_info handle.
## `argc`:     in/out — pass max args wanted; receives actual args available
## `argv`:     out — pointer to an array of napi_value (caller allocates)
## `this_arg`: out — pointer to receive the this value (pass NULL to ignore)
## `data`:     out — pointer to receive callback data (pass NULL to ignore)
comptime _GetCbInfoFn = def(
    OpaquePointer[MutAnyOrigin],
    OpaquePointer[MutAnyOrigin],
    OpaquePointer[MutAnyOrigin],
    OpaquePointer[MutAnyOrigin],
    OpaquePointer[MutAnyOrigin],
    OpaquePointer[MutAnyOrigin],
) thin abi("C") -> NapiStatus


def raw_get_cb_info(
    env: NapiEnv,
    info: NapiValue,
    argc: OpaquePointer[MutAnyOrigin],
    argv: OpaquePointer[MutAnyOrigin],
    this_arg: OpaquePointer[MutAnyOrigin],
    data: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    # The per-callback bootstrap. This ran OwnedDLHandle()+dlsym on EVERY call
    # (~346 ns) because the pointer that would let it skip that is the very
    # thing it is fetching. napi/global_cache.mojo breaks the cycle with a
    # module-private data-segment slot; see that file for why this caches only
    # the symbol ADDRESS and never the per-env Bindings.
    var addr = cached_cb_info_addr()
    if addr == 0:
        var h = OwnedDLHandle()
        var opt = h.get_symbol[NoneType]("napi_get_cb_info")
        if opt is None:
            raise Error("napi-mojo: symbol not found: napi_get_cb_info")
        addr = Int(opt.value())
        # A zero slot means "not cached"; if the global is ever non-functional
        # this simply re-resolves every call, which is the old behaviour.
        cache_cb_info_addr(addr)
    # Reinterpret the WORD HOLDING the address, exactly as _sym does. Spelling
    # this as `addr.unsafe_bitcast[...]` would call the function's first eight
    # bytes of machine code as a pointer, and would still compile.
    var f = Pointer(to=addr).unsafe_bitcast[_GetCbInfoFn]()[]
    return f(env.as_unsafe_any_origin(), info.as_unsafe_any_origin(), argc, argv, this_arg, data)


def raw_get_cb_info(
    b: Bindings,
    env: NapiEnv,
    info: NapiValue,
    argc: OpaquePointer[MutAnyOrigin],
    argv: OpaquePointer[MutAnyOrigin],
    this_arg: OpaquePointer[MutAnyOrigin],
    data: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].get_cb_info).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), info.as_unsafe_any_origin(), argc, argv, this_arg, data)


def raw_get_value_string_utf8(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    buf: OpaquePointer[MutAnyOrigin],
    bufsize: UInt,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].get_value_string_utf8).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            UInt,
            OpaquePointer[MutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), value.as_unsafe_any_origin(), buf, bufsize, result)


def raw_define_properties(
    b: Bindings,
    env: NapiEnv,
    object: NapiValue,
    property_count: UInt,
    properties: OpaquePointer[ImmutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].define_properties).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], UInt, OpaquePointer[ImmutAnyOrigin]
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), object.as_unsafe_any_origin(), property_count, properties)


def raw_get_value_double(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].get_value_double).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), value.as_unsafe_any_origin(), result)


def raw_create_double(
    b: Bindings,
    env: NapiEnv,
    value: Float64,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].create_double).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], Float64, OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), value, result)


## raw_throw_error — wraps napi_throw_error
##
## Sets a pending JavaScript Error exception in the current environment.
## `code`: optional error code string (pass OpaquePointer[ImmutAnyOrigin](unsafe_from_address=Int(0)) for none)
## `msg`:  UTF-8 error message (must remain alive until this returns)
##
## After calling this, the callback must return immediately with NapiValue(unsafe_from_address=Int(0)).
## Node.js will propagate the pending exception when the callback returns.
def raw_throw_error(
    env: NapiEnv,
    code: OpaquePointer[ImmutAnyOrigin],
    msg: OpaquePointer[ImmutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = _sym[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[ImmutAnyOrigin],
            OpaquePointer[ImmutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ](h, "napi_throw_error")
    return f(env.as_unsafe_any_origin(), code, msg)


def raw_throw_error(
    b: Bindings,
    env: NapiEnv,
    code: OpaquePointer[ImmutAnyOrigin],
    msg: OpaquePointer[ImmutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].throw_error).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[ImmutAnyOrigin],
            OpaquePointer[ImmutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), code, msg)


def raw_get_boolean(
    b: Bindings,
    env: NapiEnv,
    value: Bool,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].get_boolean).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], Bool, OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), value, result)


def raw_get_value_bool(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].get_value_bool).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), value.as_unsafe_any_origin(), result)


def raw_typeof(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].typeof_).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), value.as_unsafe_any_origin(), result)


def raw_get_null(
    b: Bindings,
    env: NapiEnv,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].get_null).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), result)


def raw_get_undefined(
    b: Bindings,
    env: NapiEnv,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].get_undefined).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), result)


def raw_create_array_with_length(
    b: Bindings,
    env: NapiEnv,
    length: UInt,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].create_array_with_length).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], UInt, OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), length, result)


def raw_set_element(
    b: Bindings,
    env: NapiEnv,
    object: NapiValue,
    index: UInt32,
    value: NapiValue,
) -> NapiStatus:
    var f = Pointer(to=b[].set_element).unsafe_bitcast[
        def(OpaquePointer[MutUntrackedOrigin], OpaquePointer[MutUntrackedOrigin], UInt32, OpaquePointer[MutUntrackedOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env, object, index, value)


def raw_get_element(
    b: Bindings,
    env: NapiEnv,
    object: NapiValue,
    index: UInt32,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].get_element).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], UInt32, OpaquePointer[MutAnyOrigin]
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), object.as_unsafe_any_origin(), index, result)


def raw_get_array_length(
    b: Bindings,
    env: NapiEnv,
    object: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].get_array_length).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), object.as_unsafe_any_origin(), result)


def raw_get_property(
    b: Bindings,
    env: NapiEnv,
    object: NapiValue,
    key: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].get_property).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), object.as_unsafe_any_origin(), key.as_unsafe_any_origin(), result)


def raw_is_array(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].is_array).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), value.as_unsafe_any_origin(), result)


def raw_get_named_property(
    b: Bindings,
    env: NapiEnv,
    object: NapiValue,
    utf8name: OpaquePointer[ImmutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].get_named_property).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[ImmutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), object.as_unsafe_any_origin(), utf8name, result)


def raw_has_named_property(
    b: Bindings,
    env: NapiEnv,
    object: NapiValue,
    utf8name: OpaquePointer[ImmutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].has_named_property).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[ImmutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), object.as_unsafe_any_origin(), utf8name, result)


def raw_call_function(
    b: Bindings,
    env: NapiEnv,
    recv: NapiValue,
    func: NapiValue,
    argc: UInt,
    argv: OpaquePointer[ImmutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].call_function).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            UInt,
            OpaquePointer[ImmutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), recv.as_unsafe_any_origin(), func.as_unsafe_any_origin(), argc, argv, result)


def raw_open_handle_scope(
    b: Bindings,
    env: NapiEnv,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].open_handle_scope).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), result)


def raw_close_handle_scope(
    b: Bindings,
    env: NapiEnv,
    scope: NapiHandleScope,
) -> NapiStatus:
    var f = Pointer(to=b[].close_handle_scope).unsafe_bitcast[
        def(OpaquePointer[MutUntrackedOrigin], OpaquePointer[MutUntrackedOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env, scope)


def raw_create_promise(
    b: Bindings,
    env: NapiEnv,
    # Both of these are OUTPUT SLOTS (napi_deferred* / napi_value*), not
    # handles: the caller passes Pointer(to=<local>)…as_unsafe_any_origin(),
    # which is population B, where the AnyOrigin widening keeps the local's
    # spill slot alive across the FFI call. Do not "tidy" `deferred` into
    # NapiDeferred — see docs/plan-origin-migration.md.
    deferred: OpaquePointer[MutAnyOrigin],
    promise: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].create_promise).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), deferred, promise)


def raw_resolve_deferred(
    b: Bindings,
    env: NapiEnv,
    deferred: NapiDeferred,
    resolution: NapiValue,
) -> NapiStatus:
    var f = Pointer(to=b[].resolve_deferred).unsafe_bitcast[
        def(OpaquePointer[MutUntrackedOrigin], OpaquePointer[MutUntrackedOrigin], OpaquePointer[MutUntrackedOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env, deferred, resolution)


def raw_reject_deferred(
    b: Bindings,
    env: NapiEnv,
    deferred: NapiDeferred,
    rejection: NapiValue,
) -> NapiStatus:
    var f = Pointer(to=b[].reject_deferred).unsafe_bitcast[
        def(OpaquePointer[MutUntrackedOrigin], OpaquePointer[MutUntrackedOrigin], OpaquePointer[MutUntrackedOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env, deferred, rejection)


def raw_create_error(
    b: Bindings,
    env: NapiEnv,
    code: NapiValue,
    msg: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].create_error).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), code.as_unsafe_any_origin(), msg.as_unsafe_any_origin(), result)


def raw_create_async_work(
    b: Bindings,
    env: NapiEnv,
    async_resource: NapiValue,
    async_resource_name: NapiValue,
    execute: OpaquePointer[MutAnyOrigin],
    complete: OpaquePointer[MutAnyOrigin],
    data: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].create_async_work).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(
        env.as_unsafe_any_origin(),
        async_resource.as_unsafe_any_origin(),
        async_resource_name.as_unsafe_any_origin(),
        execute,
        complete,
        data,
        result,
    )


def raw_queue_async_work(
    b: Bindings,
    env: NapiEnv,
    work: NapiAsyncWork,
) -> NapiStatus:
    var f = Pointer(to=b[].queue_async_work).unsafe_bitcast[
        def(OpaquePointer[MutUntrackedOrigin], OpaquePointer[MutUntrackedOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env, work)


def raw_delete_async_work(
    b: Bindings,
    env: NapiEnv,
    work: NapiAsyncWork,
) -> NapiStatus:
    var f = Pointer(to=b[].delete_async_work).unsafe_bitcast[
        def(OpaquePointer[MutUntrackedOrigin], OpaquePointer[MutUntrackedOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env, work)


def raw_create_int32(
    b: Bindings,
    env: NapiEnv,
    value: Int32,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].create_int32).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], Int32, OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), value, result)


def raw_get_value_int32(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].get_value_int32).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), value.as_unsafe_any_origin(), result)


def raw_create_uint32(
    b: Bindings,
    env: NapiEnv,
    value: UInt32,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].create_uint32).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], UInt32, OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), value, result)


def raw_get_value_uint32(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].get_value_uint32).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), value.as_unsafe_any_origin(), result)


def raw_create_int64(
    b: Bindings,
    env: NapiEnv,
    value: Int64,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].create_int64).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], Int64, OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), value, result)


def raw_get_value_int64(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].get_value_int64).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), value.as_unsafe_any_origin(), result)


## raw_throw_type_error — wraps napi_throw_type_error
##
## Sets a pending JavaScript TypeError exception.
def raw_throw_type_error(
    env: NapiEnv,
    code: OpaquePointer[ImmutAnyOrigin],
    msg: OpaquePointer[ImmutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = _sym[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[ImmutAnyOrigin],
            OpaquePointer[ImmutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ](h, "napi_throw_type_error")
    return f(env.as_unsafe_any_origin(), code, msg)


def raw_throw_type_error(
    b: Bindings,
    env: NapiEnv,
    code: OpaquePointer[ImmutAnyOrigin],
    msg: OpaquePointer[ImmutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].throw_type_error).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[ImmutAnyOrigin],
            OpaquePointer[ImmutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), code, msg)


## raw_throw_range_error — wraps napi_throw_range_error
##
## Sets a pending JavaScript RangeError exception.
def raw_throw_range_error(
    env: NapiEnv,
    code: OpaquePointer[ImmutAnyOrigin],
    msg: OpaquePointer[ImmutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = _sym[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[ImmutAnyOrigin],
            OpaquePointer[ImmutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ](h, "napi_throw_range_error")
    return f(env.as_unsafe_any_origin(), code, msg)


def raw_throw_range_error(
    b: Bindings,
    env: NapiEnv,
    code: OpaquePointer[ImmutAnyOrigin],
    msg: OpaquePointer[ImmutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].throw_range_error).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[ImmutAnyOrigin],
            OpaquePointer[ImmutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), code, msg)


def raw_create_type_error(
    b: Bindings,
    env: NapiEnv,
    code: NapiValue,
    msg: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].create_type_error).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), code.as_unsafe_any_origin(), msg.as_unsafe_any_origin(), result)


def raw_create_range_error(
    b: Bindings,
    env: NapiEnv,
    code: NapiValue,
    msg: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].create_range_error).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), code.as_unsafe_any_origin(), msg.as_unsafe_any_origin(), result)


def raw_create_arraybuffer(
    b: Bindings,
    env: NapiEnv,
    byte_length: UInt,
    data_ptr: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].create_arraybuffer).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            UInt,
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), byte_length, data_ptr, result)


def raw_get_arraybuffer_info(
    b: Bindings,
    env: NapiEnv,
    arraybuffer: NapiValue,
    data_ptr: OpaquePointer[MutAnyOrigin],
    byte_length: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].get_arraybuffer_info).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), arraybuffer.as_unsafe_any_origin(), data_ptr, byte_length)


def raw_is_arraybuffer(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].is_arraybuffer).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), value.as_unsafe_any_origin(), result)


def raw_detach_arraybuffer(
    b: Bindings,
    env: NapiEnv,
    arraybuffer: NapiValue,
) -> NapiStatus:
    var f = Pointer(to=b[].detach_arraybuffer).unsafe_bitcast[
        def(OpaquePointer[MutUntrackedOrigin], OpaquePointer[MutUntrackedOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env, arraybuffer)


def raw_create_buffer(
    b: Bindings,
    env: NapiEnv,
    length: UInt,
    data_ptr: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].create_buffer).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            UInt,
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), length, data_ptr, result)


def raw_create_buffer_copy(
    b: Bindings,
    env: NapiEnv,
    length: UInt,
    data: OpaquePointer[ImmutAnyOrigin],
    data_ptr: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].create_buffer_copy).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            UInt,
            OpaquePointer[ImmutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), length, data, data_ptr, result)


def raw_get_buffer_info(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    data_ptr: OpaquePointer[MutAnyOrigin],
    length: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].get_buffer_info).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), value.as_unsafe_any_origin(), data_ptr, length)


def raw_is_buffer(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].is_buffer).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), value.as_unsafe_any_origin(), result)


def raw_create_typedarray(
    b: Bindings,
    env: NapiEnv,
    array_type: Int32,
    length: UInt,
    arraybuffer: NapiValue,
    byte_offset: UInt,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].create_typedarray).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin], Int32, UInt, OpaquePointer[MutAnyOrigin], UInt, OpaquePointer[MutAnyOrigin]
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), array_type, length, arraybuffer.as_unsafe_any_origin(), byte_offset, result)


def raw_get_typedarray_info(
    b: Bindings,
    env: NapiEnv,
    typedarray: NapiValue,
    array_type: OpaquePointer[MutAnyOrigin],
    length: OpaquePointer[MutAnyOrigin],
    data: OpaquePointer[MutAnyOrigin],
    arraybuffer: OpaquePointer[MutAnyOrigin],
    byte_offset: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].get_typedarray_info).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(
        env.as_unsafe_any_origin(), typedarray.as_unsafe_any_origin(), array_type, length, data, arraybuffer, byte_offset
    )


def raw_is_typedarray(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].is_typedarray).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), value.as_unsafe_any_origin(), result)


def raw_define_class(
    b: Bindings,
    env: NapiEnv,
    utf8name: OpaquePointer[ImmutAnyOrigin],
    length: UInt,
    constructor: OpaquePointer[MutAnyOrigin],
    data: OpaquePointer[MutAnyOrigin],
    property_count: UInt,
    properties: OpaquePointer[ImmutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].define_class).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[ImmutAnyOrigin],
            UInt,
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            UInt,
            OpaquePointer[ImmutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(
        env.as_unsafe_any_origin(),
        utf8name,
        length,
        constructor,
        data,
        property_count,
        properties,
        result,
    )


def raw_wrap(
    b: Bindings,
    env: NapiEnv,
    js_object: NapiValue,
    native_object: OpaquePointer[MutAnyOrigin],
    finalize_cb: OpaquePointer[MutAnyOrigin],
    finalize_hint: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].wrap).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), js_object.as_unsafe_any_origin(), native_object, finalize_cb, finalize_hint, result)


def raw_unwrap(
    b: Bindings,
    env: NapiEnv,
    js_object: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].unwrap).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), js_object.as_unsafe_any_origin(), result)


def raw_remove_wrap(
    b: Bindings,
    env: NapiEnv,
    js_object: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].remove_wrap).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), js_object.as_unsafe_any_origin(), result)


def raw_new_instance(
    b: Bindings,
    env: NapiEnv,
    constructor: NapiValue,
    argc: UInt,
    argv: OpaquePointer[ImmutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].new_instance).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            UInt,
            OpaquePointer[ImmutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), constructor.as_unsafe_any_origin(), argc, argv, result)


def raw_create_function(
    b: Bindings,
    env: NapiEnv,
    utf8name: OpaquePointer[ImmutAnyOrigin],
    length: UInt,
    cb: OpaquePointer[MutAnyOrigin],
    data: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].create_function).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[ImmutAnyOrigin],
            UInt,
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), utf8name, length, cb, data, result)


def raw_get_new_target(
    b: Bindings,
    env: NapiEnv,
    info: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].get_new_target).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), info.as_unsafe_any_origin(), result)


def raw_get_global(
    b: Bindings,
    env: NapiEnv,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].get_global).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), result)


def raw_create_reference(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    initial_refcount: UInt32,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].create_reference).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], UInt32, OpaquePointer[MutAnyOrigin]
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), value.as_unsafe_any_origin(), initial_refcount, result)


def raw_delete_reference(
    b: Bindings,
    env: NapiEnv,
    napi_ref: NapiRef,
) -> NapiStatus:
    var f = Pointer(to=b[].delete_reference).unsafe_bitcast[
        def(OpaquePointer[MutUntrackedOrigin], OpaquePointer[MutUntrackedOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env, napi_ref)


def raw_reference_ref(
    b: Bindings,
    env: NapiEnv,
    napi_ref: NapiRef,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].reference_ref).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), napi_ref.as_unsafe_any_origin(), result)


def raw_reference_unref(
    b: Bindings,
    env: NapiEnv,
    napi_ref: NapiRef,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].reference_unref).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), napi_ref.as_unsafe_any_origin(), result)


def raw_get_reference_value(
    b: Bindings,
    env: NapiEnv,
    napi_ref: NapiRef,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].get_reference_value).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), napi_ref.as_unsafe_any_origin(), result)


def raw_open_escapable_handle_scope(
    b: Bindings,
    env: NapiEnv,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].open_escapable_handle_scope).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), result)


def raw_close_escapable_handle_scope(
    b: Bindings,
    env: NapiEnv,
    scope: NapiEscapableHandleScope,
) -> NapiStatus:
    var f = Pointer(to=b[].close_escapable_handle_scope).unsafe_bitcast[
        def(OpaquePointer[MutUntrackedOrigin], OpaquePointer[MutUntrackedOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env, scope)


def raw_escape_handle(
    b: Bindings,
    env: NapiEnv,
    scope: NapiEscapableHandleScope,
    escapee: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].escape_handle).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), scope.as_unsafe_any_origin(), escapee.as_unsafe_any_origin(), result)


def raw_create_bigint_int64(
    b: Bindings,
    env: NapiEnv,
    value: Int64,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].create_bigint_int64).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], Int64, OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), value, result)


def raw_create_bigint_uint64(
    b: Bindings,
    env: NapiEnv,
    value: UInt64,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].create_bigint_uint64).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], UInt64, OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), value, result)


def raw_get_value_bigint_int64(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
    lossless: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].get_value_bigint_int64).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), value.as_unsafe_any_origin(), result, lossless)


def raw_get_value_bigint_uint64(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
    lossless: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].get_value_bigint_uint64).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), value.as_unsafe_any_origin(), result, lossless)


def raw_create_date(
    b: Bindings,
    env: NapiEnv,
    time: Float64,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].create_date).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], Float64, OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), time, result)


def raw_get_date_value(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].get_date_value).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), value.as_unsafe_any_origin(), result)


def raw_is_date(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].is_date).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), value.as_unsafe_any_origin(), result)


def raw_create_symbol(
    b: Bindings,
    env: NapiEnv,
    description: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].create_symbol).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), description.as_unsafe_any_origin(), result)


def raw_symbol_for(
    b: Bindings,
    env: NapiEnv,
    description: OpaquePointer[ImmutAnyOrigin],
    length: UInt,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].symbol_for).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[ImmutAnyOrigin],
            UInt,
            OpaquePointer[MutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), description, length, result)


def raw_get_property_names(
    b: Bindings,
    env: NapiEnv,
    object: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].get_property_names).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), object.as_unsafe_any_origin(), result)


def raw_get_all_property_names(
    b: Bindings,
    env: NapiEnv,
    object: NapiValue,
    key_mode: Int32,
    key_filter: Int32,
    key_conversion: Int32,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].get_all_property_names).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], Int32, Int32, Int32, OpaquePointer[MutAnyOrigin]
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), object.as_unsafe_any_origin(), key_mode, key_filter, key_conversion, result)


def raw_has_own_property(
    b: Bindings,
    env: NapiEnv,
    object: NapiValue,
    key: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].has_own_property).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), object.as_unsafe_any_origin(), key.as_unsafe_any_origin(), result)


def raw_delete_property(
    b: Bindings,
    env: NapiEnv,
    object: NapiValue,
    key: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].delete_property).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), object.as_unsafe_any_origin(), key.as_unsafe_any_origin(), result)


def raw_strict_equals(
    b: Bindings,
    env: NapiEnv,
    lhs: NapiValue,
    rhs: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].strict_equals).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), lhs.as_unsafe_any_origin(), rhs.as_unsafe_any_origin(), result)


def raw_instanceof(
    b: Bindings,
    env: NapiEnv,
    object: NapiValue,
    constructor: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].instanceof_).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), object.as_unsafe_any_origin(), constructor.as_unsafe_any_origin(), result)


def raw_object_freeze(
    b: Bindings,
    env: NapiEnv,
    object: NapiValue,
) -> NapiStatus:
    # PILOT of the population-B signature flip (docs/handoff-argv-origin-migration.md).
    # Every argument here is a V8-owned handle whose storage alias is already
    # MutUntrackedOrigin, and nothing in this wrapper forms a pointer to a Mojo
    # local — so there is no lifetime for AnyOrigin to have been extending, and
    # the widening calls were pure ceremony.
    var f = Pointer(to=b[].object_freeze).unsafe_bitcast[
        def(
            OpaquePointer[MutUntrackedOrigin], OpaquePointer[MutUntrackedOrigin]
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env, object)


def raw_object_seal(
    b: Bindings,
    env: NapiEnv,
    object: NapiValue,
) -> NapiStatus:
    var f = Pointer(to=b[].object_seal).unsafe_bitcast[
        def(OpaquePointer[MutUntrackedOrigin], OpaquePointer[MutUntrackedOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env, object)


def raw_has_element(
    b: Bindings,
    env: NapiEnv,
    object: NapiValue,
    index: UInt32,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].has_element).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], UInt32, OpaquePointer[MutAnyOrigin]
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), object.as_unsafe_any_origin(), index, result)


def raw_delete_element(
    b: Bindings,
    env: NapiEnv,
    object: NapiValue,
    index: UInt32,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].delete_element).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], UInt32, OpaquePointer[MutAnyOrigin]
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), object.as_unsafe_any_origin(), index, result)


def raw_get_prototype(
    b: Bindings,
    env: NapiEnv,
    object: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].get_prototype).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), object.as_unsafe_any_origin(), result)


def raw_create_threadsafe_function(
    b: Bindings,
    env: NapiEnv,
    func: NapiValue,
    async_resource: NapiValue,
    async_resource_name: NapiValue,
    max_queue_size: UInt,
    initial_thread_count: UInt,
    thread_finalize_data: OpaquePointer[MutAnyOrigin],
    thread_finalize_cb: OpaquePointer[MutAnyOrigin],
    context: OpaquePointer[MutAnyOrigin],
    call_js_cb: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].create_threadsafe_function).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            UInt,
            UInt,
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(
        env.as_unsafe_any_origin(),
        func.as_unsafe_any_origin(),
        async_resource.as_unsafe_any_origin(),
        async_resource_name.as_unsafe_any_origin(),
        max_queue_size,
        initial_thread_count,
        thread_finalize_data,
        thread_finalize_cb,
        context,
        call_js_cb,
        result,
    )


def raw_call_threadsafe_function(
    b: Bindings,
    func: NapiThreadsafeFunction,
    data: OpaquePointer[MutAnyOrigin],
    is_blocking: Int32,
) -> NapiStatus:
    var f = Pointer(to=b[].call_threadsafe_function).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], Int32
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(func.as_unsafe_any_origin(), data, is_blocking)


def raw_acquire_threadsafe_function(
    b: Bindings,
    func: NapiThreadsafeFunction,
) -> NapiStatus:
    var f = Pointer(to=b[].acquire_threadsafe_function).unsafe_bitcast[
        def(OpaquePointer[MutUntrackedOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(func)


def raw_release_threadsafe_function(
    b: Bindings,
    func: NapiThreadsafeFunction,
    mode: Int32,
) -> NapiStatus:
    var f = Pointer(to=b[].release_threadsafe_function).unsafe_bitcast[
        def(OpaquePointer[MutUntrackedOrigin], Int32) thin abi("C") -> NapiStatus
    ]()[]
    return f(func, mode)


# ---------------------------------------------------------------------------
# External data
# ---------------------------------------------------------------------------


def raw_create_external(
    b: Bindings,
    env: NapiEnv,
    data: OpaquePointer[MutAnyOrigin],
    finalize_cb: OpaquePointer[MutAnyOrigin],
    finalize_hint: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].create_external).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), data, finalize_cb, finalize_hint, result)


def raw_get_value_external(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].get_value_external).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), value.as_unsafe_any_origin(), result)


# ---------------------------------------------------------------------------
# Type coercion
# ---------------------------------------------------------------------------


def raw_get_version(
    b: Bindings,
    env: NapiEnv,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].get_version).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), result)


def raw_get_node_version(
    b: Bindings,
    env: NapiEnv,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].get_node_version).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), result)


def raw_set_property(
    b: Bindings,
    env: NapiEnv,
    object: NapiValue,
    key: NapiValue,
    value: NapiValue,
) -> NapiStatus:
    var f = Pointer(to=b[].set_property).unsafe_bitcast[
        def(OpaquePointer[MutUntrackedOrigin], OpaquePointer[MutUntrackedOrigin], OpaquePointer[MutUntrackedOrigin], OpaquePointer[MutUntrackedOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env, object, key, value)


def raw_has_property(
    b: Bindings,
    env: NapiEnv,
    object: NapiValue,
    key: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].has_property).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), object.as_unsafe_any_origin(), key.as_unsafe_any_origin(), result)


def raw_throw(
    b: Bindings,
    env: NapiEnv,
    error: NapiValue,
) -> NapiStatus:
    var f = Pointer(to=b[].throw_).unsafe_bitcast[
        def(OpaquePointer[MutUntrackedOrigin], OpaquePointer[MutUntrackedOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env, error)


def raw_is_exception_pending(
    b: Bindings,
    env: NapiEnv,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].is_exception_pending).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), result)


def raw_get_and_clear_last_exception(
    b: Bindings,
    env: NapiEnv,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].get_and_clear_last_exception).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), result)


def raw_coerce_to_bool(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].coerce_to_bool).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), value.as_unsafe_any_origin(), result)


def raw_coerce_to_number(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].coerce_to_number).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), value.as_unsafe_any_origin(), result)


def raw_coerce_to_string(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].coerce_to_string).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), value.as_unsafe_any_origin(), result)


def raw_coerce_to_object(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].coerce_to_object).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), value.as_unsafe_any_origin(), result)


def raw_create_dataview(
    b: Bindings,
    env: NapiEnv,
    byte_length: UInt,
    arraybuffer: NapiValue,
    byte_offset: UInt,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].create_dataview).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin], UInt, OpaquePointer[MutAnyOrigin], UInt, OpaquePointer[MutAnyOrigin]
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), byte_length, arraybuffer.as_unsafe_any_origin(), byte_offset, result)


def raw_get_dataview_info(
    b: Bindings,
    env: NapiEnv,
    dataview: NapiValue,
    byte_length: OpaquePointer[MutAnyOrigin],
    data: OpaquePointer[MutAnyOrigin],
    arraybuffer: OpaquePointer[MutAnyOrigin],
    byte_offset: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].get_dataview_info).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), dataview.as_unsafe_any_origin(), byte_length, data, arraybuffer, byte_offset)


def raw_is_dataview(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].is_dataview).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), value.as_unsafe_any_origin(), result)


def raw_create_bigint_words(
    b: Bindings,
    env: NapiEnv,
    sign_bit: Int32,
    word_count: UInt,
    words: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].create_bigint_words).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            Int32,
            UInt,
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), sign_bit, word_count, words, result)


def raw_get_value_bigint_words(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    sign_bit: OpaquePointer[MutAnyOrigin],
    word_count: OpaquePointer[MutAnyOrigin],
    words: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].get_value_bigint_words).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), value.as_unsafe_any_origin(), sign_bit, word_count, words)


def raw_add_finalizer(
    b: Bindings,
    env: NapiEnv,
    js_object: NapiValue,
    native_object: OpaquePointer[MutAnyOrigin],
    finalize_cb: OpaquePointer[MutAnyOrigin],
    finalize_hint: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].add_finalizer).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), js_object.as_unsafe_any_origin(), native_object, finalize_cb, finalize_hint, result)


def raw_create_external_arraybuffer(
    b: Bindings,
    env: NapiEnv,
    external_data: OpaquePointer[MutAnyOrigin],
    byte_length: UInt,
    finalize_cb: OpaquePointer[MutAnyOrigin],
    finalize_hint: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].create_external_arraybuffer).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            UInt,
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(
        env.as_unsafe_any_origin(), external_data, byte_length, finalize_cb, finalize_hint, result
    )


def raw_set_instance_data(
    b: Bindings,
    env: NapiEnv,
    data: OpaquePointer[MutAnyOrigin],
    finalize_cb: OpaquePointer[MutAnyOrigin],
    finalize_hint: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].set_instance_data).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), data, finalize_cb, finalize_hint)


def raw_get_instance_data(
    b: Bindings,
    env: NapiEnv,
    data: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].get_instance_data).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), data)


def raw_add_env_cleanup_hook(
    b: Bindings,
    env: NapiEnv,
    fun: OpaquePointer[MutAnyOrigin],
    arg: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].add_env_cleanup_hook).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), fun, arg)


def raw_remove_env_cleanup_hook(
    b: Bindings,
    env: NapiEnv,
    fun: OpaquePointer[MutAnyOrigin],
    arg: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].remove_env_cleanup_hook).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), fun, arg)


def raw_cancel_async_work(
    b: Bindings,
    env: NapiEnv,
    work: NapiAsyncWork,
) -> NapiStatus:
    var f = Pointer(to=b[].cancel_async_work).unsafe_bitcast[
        def(OpaquePointer[MutUntrackedOrigin], OpaquePointer[MutUntrackedOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env, work)


def raw_is_error(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].is_error).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), value.as_unsafe_any_origin(), result)


def raw_adjust_external_memory(
    b: Bindings,
    env: NapiEnv,
    change_in_bytes: Int64,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].adjust_external_memory).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], Int64, OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), change_in_bytes, result)


def raw_run_script(
    b: Bindings,
    env: NapiEnv,
    script: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].run_script).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), script.as_unsafe_any_origin(), result)


## raw_throw_syntax_error — wraps node_api_throw_syntax_error (N-API v9)
##
## Sets a pending JavaScript SyntaxError exception.
## Note: uses node_api_ prefix (not napi_).
def raw_throw_syntax_error(
    env: NapiEnv,
    code: OpaquePointer[ImmutAnyOrigin],
    msg: OpaquePointer[ImmutAnyOrigin],
) raises -> NapiStatus:
    var h = OwnedDLHandle()
    var f = _sym[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[ImmutAnyOrigin],
            OpaquePointer[ImmutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ](h, "node_api_throw_syntax_error")
    return f(env.as_unsafe_any_origin(), code, msg)


def raw_throw_syntax_error(
    b: Bindings,
    env: NapiEnv,
    code: OpaquePointer[ImmutAnyOrigin],
    msg: OpaquePointer[ImmutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].throw_syntax_error).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[ImmutAnyOrigin],
            OpaquePointer[ImmutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), code, msg)


def raw_create_syntax_error(
    b: Bindings,
    env: NapiEnv,
    code: NapiValue,
    msg: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].create_syntax_error).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), code.as_unsafe_any_origin(), msg.as_unsafe_any_origin(), result)


def raw_is_detached_arraybuffer(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].is_detached_arraybuffer).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), value.as_unsafe_any_origin(), result)


def raw_fatal_exception(
    b: Bindings,
    env: NapiEnv,
    err: NapiValue,
) -> NapiStatus:
    var f = Pointer(to=b[].fatal_exception).unsafe_bitcast[
        def(OpaquePointer[MutUntrackedOrigin], OpaquePointer[MutUntrackedOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env, err)


def raw_type_tag_object(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    type_tag: OpaquePointer[ImmutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].type_tag_object).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[ImmutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), value.as_unsafe_any_origin(), type_tag)


def raw_check_object_type_tag(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    type_tag: OpaquePointer[ImmutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].check_object_type_tag).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[ImmutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), value.as_unsafe_any_origin(), type_tag, result)


def raw_add_async_cleanup_hook(
    b: Bindings,
    env: NapiEnv,
    hook_cb: OpaquePointer[MutAnyOrigin],
    arg: OpaquePointer[MutAnyOrigin],
    remove_handle: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].add_async_cleanup_hook).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), hook_cb, arg, remove_handle)


def raw_remove_async_cleanup_hook(
    b: Bindings,
    handle: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].remove_async_cleanup_hook).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(handle)


def raw_get_uv_event_loop(
    b: Bindings,
    env: NapiEnv,
    loop_out: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].get_uv_event_loop).unsafe_bitcast[
        def(OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), loop_out)


## raw_async_init — wraps napi_async_init (N-API v1)
##
## Creates an async context for async_hooks tracking.
## async_resource: JS object representing the resource (pass undefined for none)
## async_resource_name: string napi_value naming the resource type
## result: out-pointer; receives the napi_async_context handle
def raw_async_init(
    b: Bindings,
    env: NapiEnv,
    async_resource: NapiValue,
    async_resource_name: NapiValue,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].async_init).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), async_resource.as_unsafe_any_origin(), async_resource_name.as_unsafe_any_origin(), result)


## raw_async_destroy — wraps napi_async_destroy (N-API v1)
##
## Destroys an async context previously created with napi_async_init.
def raw_async_destroy(
    b: Bindings,
    env: NapiEnv,
    async_context: NapiAsyncContext,
) -> NapiStatus:
    var f = Pointer(to=b[].async_destroy).unsafe_bitcast[
        def(OpaquePointer[MutUntrackedOrigin], OpaquePointer[MutUntrackedOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env, async_context)


## raw_make_callback — wraps napi_make_callback (N-API v1)
##
## Calls a JS function in the given async context. Unlike napi_call_function,
## this correctly triggers async_hooks before/after callbacks and propagates
## AsyncLocalStorage context established by the given async_context.
## recv:   the `this` value for the call
## func:   the JS function napi_value to invoke
## argc:   number of arguments
## argv:   pointer to argc consecutive napi_value arguments (immutable)
## result: out-pointer; receives the return value
def raw_make_callback(
    b: Bindings,
    env: NapiEnv,
    async_context: NapiAsyncContext,
    recv: NapiValue,
    func: NapiValue,
    argc: UInt,
    argv: OpaquePointer[ImmutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].make_callback).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            UInt,
            OpaquePointer[ImmutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), async_context.as_unsafe_any_origin(), recv.as_unsafe_any_origin(), func.as_unsafe_any_origin(), argc, argv, result)


## raw_open_callback_scope — wraps napi_open_callback_scope (N-API v3)
##
## Opens a callback scope that sets up the async context for subsequent
## N-API calls. Required for correct async_hooks integration when making
## synchronous calls from within an async operation.
## resource_object: JS object for async tracking (or undefined)
## context:         async context from napi_async_init
## result:          out-pointer; receives the napi_callback_scope handle
def raw_open_callback_scope(
    b: Bindings,
    env: NapiEnv,
    resource_object: NapiValue,
    context: NapiAsyncContext,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].open_callback_scope).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), resource_object.as_unsafe_any_origin(), context.as_unsafe_any_origin(), result)


## raw_close_callback_scope — wraps napi_close_callback_scope (N-API v3)
##
## Closes a callback scope previously opened with napi_open_callback_scope.
def raw_close_callback_scope(
    b: Bindings,
    env: NapiEnv,
    scope: NapiCallbackScope,
) -> NapiStatus:
    var f = Pointer(to=b[].close_callback_scope).unsafe_bitcast[
        def(OpaquePointer[MutUntrackedOrigin], OpaquePointer[MutUntrackedOrigin]) thin abi("C") -> NapiStatus
    ]()[]
    return f(env, scope)


## raw_get_value_string_latin1 — wraps napi_get_value_string_latin1 (N-API v1)
##
## Reads a JavaScript string value into a Latin-1 (ISO-8859-1) byte buffer.
## Same calling convention as raw_get_value_string_utf8:
##   - buf=null + bufsize=0: writes required byte count into result (excl. null)
##   - buf!=null: writes Latin-1 bytes + null terminator, result = bytes written
## Each JS character that fits in Latin-1 produces one byte. Characters outside
## the Latin-1 range (U+0100+) are replaced with '?' by the engine.
def raw_get_value_string_latin1(
    b: Bindings,
    env: NapiEnv,
    value: NapiValue,
    buf: OpaquePointer[MutAnyOrigin],
    bufsize: UInt,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].get_value_string_latin1).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            UInt,
            OpaquePointer[MutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), value.as_unsafe_any_origin(), buf, bufsize, result)


## N-API v10 additions (136-141)


## raw_create_external_string_latin1 — wraps node_api_create_external_string_latin1 (N-API v10)
##
## Creates a JS string backed by a native Latin-1 buffer without copying.
## finalize_cb: called when the string is GC'd (may be NULL)
## finalize_hint: opaque pointer passed to finalize_cb
## result: out-pointer; receives the new JS string napi_value
## copied_out: out-pointer to Bool; set to True if the engine was forced to copy
def raw_create_external_string_latin1(
    b: Bindings,
    env: NapiEnv,
    str_ptr: OpaquePointer[ImmutAnyOrigin],
    length: UInt,
    finalize_cb: OpaquePointer[MutAnyOrigin],
    finalize_hint: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
    copied_out: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].create_external_string_latin1).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[ImmutAnyOrigin],
            UInt,
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(
        env.as_unsafe_any_origin(), str_ptr, length, finalize_cb, finalize_hint, result, copied_out
    )


## raw_create_external_string_utf16 — wraps node_api_create_external_string_utf16 (N-API v10)
##
## Creates a JS string backed by a native UTF-16LE buffer without copying.
## str_ptr: pointer to char16_t[] data (as opaque pointer)
## length: number of char16_t code units (not bytes)
## finalize_cb: called when the string is GC'd (may be NULL)
## finalize_hint: opaque pointer passed to finalize_cb
## result: out-pointer; receives the new JS string napi_value
## copied_out: out-pointer to Bool; set to True if the engine was forced to copy
def raw_create_external_string_utf16(
    b: Bindings,
    env: NapiEnv,
    str_ptr: OpaquePointer[ImmutAnyOrigin],
    length: UInt,
    finalize_cb: OpaquePointer[MutAnyOrigin],
    finalize_hint: OpaquePointer[MutAnyOrigin],
    result: OpaquePointer[MutAnyOrigin],
    copied_out: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].create_external_string_utf16).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[ImmutAnyOrigin],
            UInt,
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(
        env.as_unsafe_any_origin(), str_ptr, length, finalize_cb, finalize_hint, result, copied_out
    )


## raw_create_property_key_utf8 — wraps node_api_create_property_key_utf8 (N-API v10)
##
## Creates an engine-internalized string from UTF-8 for use as a property key.
## Repeated calls with the same data may return the same interned value,
## making subsequent napi_get/set_property calls faster than with regular strings.
def raw_create_property_key_utf8(
    b: Bindings,
    env: NapiEnv,
    str_ptr: OpaquePointer[ImmutAnyOrigin],
    length: UInt,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].create_property_key_utf8).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[ImmutAnyOrigin],
            UInt,
            OpaquePointer[MutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), str_ptr, length, result)


## raw_create_property_key_latin1 — wraps node_api_create_property_key_latin1 (N-API v10)
##
## Creates an engine-internalized string from Latin-1 for use as a property key.
def raw_create_property_key_latin1(
    b: Bindings,
    env: NapiEnv,
    str_ptr: OpaquePointer[ImmutAnyOrigin],
    length: UInt,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].create_property_key_latin1).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[ImmutAnyOrigin],
            UInt,
            OpaquePointer[MutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), str_ptr, length, result)


## raw_create_property_key_utf16 — wraps node_api_create_property_key_utf16 (N-API v10)
##
## Creates an engine-internalized string from UTF-16LE for use as a property key.
## str_ptr: pointer to char16_t[] data (as opaque pointer)
## length: number of char16_t code units (not bytes)
def raw_create_property_key_utf16(
    b: Bindings,
    env: NapiEnv,
    str_ptr: OpaquePointer[ImmutAnyOrigin],
    length: UInt,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].create_property_key_utf16).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[ImmutAnyOrigin],
            UInt,
            OpaquePointer[MutAnyOrigin],
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), str_ptr, length, result)


## raw_create_buffer_from_arraybuffer — wraps node_api_create_buffer_from_arraybuffer (N-API v10)
##
## Creates a zero-copy Node.js Buffer view into a slice of an existing ArrayBuffer.
## arraybuffer: the source napi_value ArrayBuffer
## byte_offset: start of the slice in bytes
## byte_length: length of the slice in bytes
## result: out-pointer; receives the new Buffer napi_value
## Raises RangeError at the JS level if offset+length exceeds the ArrayBuffer bounds.
def raw_create_buffer_from_arraybuffer(
    b: Bindings,
    env: NapiEnv,
    arraybuffer: NapiValue,
    byte_offset: UInt,
    byte_length: UInt,
    result: OpaquePointer[MutAnyOrigin],
) -> NapiStatus:
    var f = Pointer(to=b[].create_buffer_from_arraybuffer).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], UInt, UInt, OpaquePointer[MutAnyOrigin]
        ) thin abi("C") -> NapiStatus
    ]()[]
    return f(env.as_unsafe_any_origin(), arraybuffer.as_unsafe_any_origin(), byte_offset, byte_length, result)
