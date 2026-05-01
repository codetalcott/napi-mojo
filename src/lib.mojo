## src/lib.mojo — napi-mojo module entry point (thin orchestrator)
##
## Allocates NapiBindings, creates ModuleBuilder, then delegates all
## callback registration to per-feature addon modules.
##
## ## Why the actual entry point is in C, not here
##
## Mojo 1.0.0b1 doesn't expose a way to obtain a thin C-ABI function
## pointer to a `def`. The address-of-local-var pattern napi-mojo used at
## every finalizer registration site (`var f = my_def_fn;
## UnsafePointer(to=f).bitcast[OpaquePointer]()[]`) extracts the AnyTrait
## wrapper struct's first 8 bytes — a sentinel/discriminant, not the
## function's code address. When N-API calls that "pointer" at env teardown
## on Linux it lands on unmapped memory (SIGSEGV); on macOS it usually
## lands on benign garbage, hence the platform-skewed CI flake.
##
## The fix (mirrored after wgpu-mojo and other Mojo-as-C-callback projects)
## moves the N-API entry point and the finalizer trampolines into a tiny
## C source file (src/napi_callbacks.c). C takes function addresses
## natively, no DCE issues. C's `napi_register_module_v1` builds a
## `NapiMojoCallbackTable` of trampoline addresses and hands it to
## `napi_mojo_register_module` (the @export'd entry below). We copy the
## addresses into NapiBindings so every callsite reads them via the
## existing `CbArgs.get_bindings(...)` pipeline.
##
## Each finalizer/cleanup-hook BODY lives here as `@export("..._impl",
## ABI="C")`. The C trampoline forwards to it by symbol name.

from std.memory import alloc
from napi.types import NapiEnv, NapiValue, NapiStatus
from napi.bindings import (
    NapiBindings,
    NapiMojoCallbackTable,
    Bindings,
    init_bindings,
)
from napi.raw import (
    raw_create_error,
    raw_fatal_exception,
    raw_remove_async_cleanup_hook,
    raw_resolve_deferred,
    raw_reject_deferred,
    raw_delete_async_work,
)
from napi.framework.js_string import JsString
from napi.framework.js_number import JsNumber
from napi.framework.register import ModuleBuilder
from generated.callbacks import register_generated
from addon.primitives import register_primitives
from addon.collections import register_collections
from addon.async_ops import register_async, AsyncProgressData
from addon.binary_ops import register_binary
from addon.class_counter import register_counter, CounterData
from addon.class_animal import register_animal, AnimalData, DogData
from addon.function_ops import register_functions
from addon.ref_ops import register_refs
from addon.value_types import register_value_types
from addon.externals import register_externals, ExternalData
from addon.env_ops import register_env
from addon.misc_ops import register_misc
from addon.async_context_ops import register_async_context
from addon.convert_ops import register_convert
from addon.typed_helpers_ops import (
    register_typed_helpers,
    TypedPayload,
    InstancePayload,
)


# =============================================================================
# Finalizer / cleanup-hook bodies — exposed as C symbols via @export(ABI="C")
#
# These are the actual finalizer logic. Their bodies match what used to live
# in src/addon/*.mojo before we extracted them. The C trampolines in
# src/napi_callbacks.c forward to these by name.
#
# IMPORTANT: @export(ABI="C") only emits a real symbol when applied to a
# function in the top-level compilation unit (this file). The same
# annotation in addon/* modules silently DCE's. That's why all 13 impls
# have to live here.
# =============================================================================


@export("napi_mojo_instance_data_finalize_impl", ABI="C")
def napi_mojo_instance_data_finalize_impl(
    env: NapiEnv,
    data: OpaquePointer[MutAnyOrigin],
    hint: OpaquePointer[MutAnyOrigin],
):
    """env-teardown free for napi_set_instance_data's heap Float64."""
    var ptr = data.bitcast[Float64]()
    ptr.destroy_pointee()
    ptr.free()


@export("napi_mojo_counter_finalize_impl", ABI="C")
def napi_mojo_counter_finalize_impl(
    env: NapiEnv,
    data: OpaquePointer[MutAnyOrigin],
    hint: OpaquePointer[MutAnyOrigin],
):
    """GC finalizer for Counter class instances."""
    var ptr = data.bitcast[CounterData]()
    ptr.destroy_pointee()
    ptr.free()


@export("napi_mojo_animal_finalize_impl", ABI="C")
def napi_mojo_animal_finalize_impl(
    env: NapiEnv,
    data: OpaquePointer[MutAnyOrigin],
    hint: OpaquePointer[MutAnyOrigin],
):
    """GC finalizer for Animal class instances (frees the name buffer)."""
    var ptr = data.bitcast[AnimalData]()
    ptr[].name_ptr.bitcast[Byte]().free()
    ptr.destroy_pointee()
    ptr.free()


@export("napi_mojo_dog_finalize_impl", ABI="C")
def napi_mojo_dog_finalize_impl(
    env: NapiEnv,
    data: OpaquePointer[MutAnyOrigin],
    hint: OpaquePointer[MutAnyOrigin],
):
    """GC finalizer for Dog class instances (frees name + breed buffers)."""
    var ptr = data.bitcast[DogData]()
    ptr[].name_ptr.bitcast[Byte]().free()
    ptr[].breed_ptr.bitcast[Byte]().free()
    ptr.destroy_pointee()
    ptr.free()


@export("napi_mojo_external_finalize_impl", ABI="C")
def napi_mojo_external_finalize_impl(
    env: NapiEnv,
    data: OpaquePointer[MutAnyOrigin],
    hint: OpaquePointer[MutAnyOrigin],
):
    """GC finalizer for createExternal-wrapped ExternalData."""
    var ptr = data.bitcast[ExternalData]()
    ptr.destroy_pointee()
    ptr.free()


@export("napi_mojo_external_ab_finalize_impl", ABI="C")
def napi_mojo_external_ab_finalize_impl(
    env: NapiEnv,
    data: OpaquePointer[MutAnyOrigin],
    hint: OpaquePointer[MutAnyOrigin],
):
    """GC finalizer for createExternalArrayBuffer's heap byte buffer."""
    var ptr = data.bitcast[Byte]()
    ptr.free()


@export("napi_mojo_noop_finalize_impl", ABI="C")
def napi_mojo_noop_finalize_impl(
    env: NapiEnv,
    data: OpaquePointer[MutAnyOrigin],
    hint: OpaquePointer[MutAnyOrigin],
):
    """GC finalizer for attachFinalizer's dummy 1-byte allocation."""
    var ptr = data.bitcast[Byte]()
    ptr.free()


@export("napi_mojo_external_string_finalize_impl", ABI="C")
def napi_mojo_external_string_finalize_impl(
    env: NapiEnv,
    data: OpaquePointer[MutAnyOrigin],
    hint: OpaquePointer[MutAnyOrigin],
):
    """GC finalizer for createExternalString's Latin-1 byte buffer."""
    var ptr = data.bitcast[UInt8]()
    ptr.free()


@export("napi_mojo_progress_finalize_impl", ABI="C")
def napi_mojo_progress_finalize_impl(
    env: NapiEnv,
    finalize_data: OpaquePointer[MutAnyOrigin],
    finalize_hint: OpaquePointer[MutAnyOrigin],
):
    """TSFN finalize callback for async_progress — resolves/rejects the
    promise and frees the data struct after all queued progress calls
    have fired. NAPI_OK==0 is hardcoded to avoid an extra import here."""
    var ptr = finalize_data.bitcast[AsyncProgressData]()
    if Int(env) != 0:
        try:
            if ptr[].status == NapiStatus(0):  # NAPI_OK
                var result_val = JsNumber.create(env, Float64(ptr[].count))
                _ = raw_resolve_deferred(
                    env, ptr[].deferred, result_val.value
                )
            else:
                var msg = JsString.create_literal(
                    env, "async progress work failed"
                )
                var null_code = NapiValue()
                var error_val = NapiValue()
                var error_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
                    to=error_val
                ).bitcast[NoneType]()
                _ = raw_create_error(env, null_code, msg.value, error_ptr)
                _ = raw_reject_deferred(env, ptr[].deferred, error_val)
            _ = raw_delete_async_work(env, ptr[].work)
        except:
            pass
    ptr.destroy_pointee()
    ptr.free()


@export("napi_mojo_typed_payload_finalize_impl", ABI="C")
def napi_mojo_typed_payload_finalize_impl(
    env: NapiEnv,
    data: OpaquePointer[MutAnyOrigin],
    hint: OpaquePointer[MutAnyOrigin],
):
    """GC finalizer for createTypedPayload (TypedPayload is the napi-mojo
    test instantiation of `JsExternal.create_typed[T]`)."""
    var ptr = data.bitcast[TypedPayload]()
    ptr.destroy_pointee()
    ptr.free()


@export("napi_mojo_typed_instance_data_finalize_impl", ABI="C")
def napi_mojo_typed_instance_data_finalize_impl(
    env: NapiEnv,
    data: OpaquePointer[MutAnyOrigin],
    hint: OpaquePointer[MutAnyOrigin],
):
    """env-teardown free for setTypedInstanceData (InstancePayload is the
    napi-mojo test instantiation of `set_instance_data[T]`)."""
    var ptr = data.bitcast[InstancePayload]()
    ptr.destroy_pointee()
    ptr.free()


@export("napi_mojo_cleanup_hook_impl", ABI="C")
def napi_mojo_cleanup_hook_impl(arg: OpaquePointer[MutAnyOrigin]):
    """env-teardown sync cleanup hook — does nothing (matches the prior
    no-op behavior of cleanup_hook_noop)."""
    pass


@export("napi_mojo_async_cleanup_hook_impl", ABI="C")
def napi_mojo_async_cleanup_hook_impl(
    handle: OpaquePointer[MutAnyOrigin], arg: OpaquePointer[MutAnyOrigin]
):
    """env-teardown async cleanup hook. N-API contract: must call
    napi_remove_async_cleanup_hook(handle), or env teardown blocks
    indefinitely. The `arg` we registered is our NapiBindings pointer
    (set in addon/env_ops.mojo) so we can use the bindings-aware overload
    and avoid an env-teardown dlsym."""
    var b = arg.bitcast[NapiBindings]()
    _ = raw_remove_async_cleanup_hook(b, handle)


# =============================================================================
# napi_mojo_register_module — Mojo's view of the entry point
#
# C's napi_register_module_v1 (in src/napi_callbacks.c) builds a
# NapiMojoCallbackTable of trampoline addresses and hands it here.
# We copy the addresses into NapiBindings so every addon callsite can
# read the appropriate finalizer pointer via b[].xxx_finalize_ptr.
# =============================================================================


@export("napi_mojo_register_module", ABI="C")
def napi_mojo_register_module(
    env: NapiEnv,
    exports: NapiValue,
    cb_table: UnsafePointer[NapiMojoCallbackTable, ImmutAnyOrigin],
) -> NapiValue:
    var bindings_ptr = alloc[NapiBindings](1)
    try:
        var bindings = NapiBindings()
        init_bindings(bindings)
        # Copy the C-supplied trampoline pointers into NapiBindings so
        # everything downstream can reach them via the existing pipeline.
        bindings.instance_data_finalize_ptr = (
            cb_table[].instance_data_finalize
        )
        bindings.counter_finalize_ptr = cb_table[].counter_finalize
        bindings.animal_finalize_ptr = cb_table[].animal_finalize
        bindings.dog_finalize_ptr = cb_table[].dog_finalize
        bindings.external_finalize_ptr = cb_table[].external_finalize
        bindings.external_ab_finalize_ptr = cb_table[].external_ab_finalize
        bindings.noop_finalize_ptr = cb_table[].noop_finalize
        bindings.external_string_finalize_ptr = (
            cb_table[].external_string_finalize
        )
        bindings.progress_finalize_ptr = cb_table[].progress_finalize
        bindings.typed_payload_finalize_ptr = cb_table[].typed_payload_finalize
        bindings.typed_instance_data_finalize_ptr = (
            cb_table[].typed_instance_data_finalize
        )
        bindings.cleanup_hook_ptr = cb_table[].cleanup_hook
        bindings.async_cleanup_hook_ptr = cb_table[].async_cleanup_hook
        bindings_ptr.init_pointee_move(bindings^)
    except:
        bindings_ptr.free()
        return exports
    var cb_data = bindings_ptr.bitcast[NoneType]()

    try:
        var m = ModuleBuilder(env, exports, cb_data)
        register_generated(m)
        register_primitives(m)
        register_collections(m)
        register_async(m)
        register_binary(m)
        register_counter(m, bindings_ptr)
        register_animal(m)
        register_functions(m)
        register_refs(m)
        register_value_types(m)
        register_externals(m)
        register_env(m)
        register_misc(m)
        register_async_context(m)
        register_convert(m)
        register_typed_helpers(m)
        m.flush()
    except:
        try:
            var null_code = NapiValue()
            var err_msg = JsString.create_literal(
                env, "napi-mojo: register_module failed"
            )
            var err_val = NapiValue()
            var err_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
                to=err_val
            ).bitcast[NoneType]()
            _ = raw_create_error(env, null_code, err_msg.value, err_ptr)
            _ = raw_fatal_exception(env, err_val)
        except:
            pass

    return exports
