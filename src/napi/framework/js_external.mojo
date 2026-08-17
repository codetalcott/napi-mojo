## src/napi/framework/js_external.mojo — external data wrapper
##
## JsExternal wraps napi_create_external / napi_get_value_external.
## Creates a JavaScript value that holds an opaque native pointer with
## an optional GC finalize callback.

from std.memory.alloc import unsafe_alloc
from napi.types import NapiEnv, NapiValue, NAPI_TYPE_EXTERNAL
from napi.bindings import Bindings
from napi.raw import raw_create_external, raw_get_value_external
from napi.error import check_status, throw_js_type_error_dynamic
from napi.framework.js_value import js_typeof, js_type_name


struct JsExternal:
    @__allow_legacy_any_origin_fields
    var value: NapiValue

    def __init__(out self, value: NapiValue):
        self.value = value

    @staticmethod
    def create(
        b: Bindings,
        env: NapiEnv,
        data: OpaquePointer[MutAnyOrigin],
        finalize_cb: OpaquePointer[MutAnyOrigin],
    ) raises -> JsExternal:
        """Create an external with a finalize callback (called on GC)."""
        var result = NapiValue(unsafe_from_address=Int(0))
        check_status(
            raw_create_external(
                b,
                env,
                data,
                finalize_cb,
                OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0)),  # finalize_hint = NULL
                Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        return JsExternal(result)

    @staticmethod
    def create_no_release(
        b: Bindings,
        env: NapiEnv,
        data: OpaquePointer[MutAnyOrigin],
    ) raises -> JsExternal:
        """Create an external with no finalize callback."""
        var result = NapiValue(unsafe_from_address=Int(0))
        check_status(
            raw_create_external(
                b,
                env,
                data,
                OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0)),  # finalize_cb = NULL
                OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0)),  # finalize_hint = NULL
                Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        return JsExternal(result)

    @staticmethod
    def get_data(
        b: Bindings, env: NapiEnv, val: NapiValue
    ) raises -> OpaquePointer[MutAnyOrigin]:
        """Retrieve the opaque data pointer from an external value."""
        var result = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        check_status(
            raw_get_value_external(
                b,
                env,
                val,
                Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        return result

    @staticmethod
    def create_typed[T: Movable & Deinitable](
        b: Bindings, env: NapiEnv, var value: T
    ) raises -> JsExternal:
        """Heap-allocate `value`, wrap in an External with a GC finalizer.

        The finalizer destroys the pointee and frees the heap slot. Consumers
        avoid writing per-type alloc/init/finalize plumbing.
        """
        var data_ptr = unsafe_alloc[T](1)
        data_ptr.unsafe_write(value^)
        var fin_ref = _typed_external_finalize[T]
        var fin_ptr = Pointer(to=fin_ref).unsafe_bitcast[
            OpaquePointer[MutAnyOrigin]
        ]()[]
        return JsExternal.create(
            b, env, data_ptr.unsafe_bitcast[NoneType]().as_unsafe_any_origin(), fin_ptr
        )

    @staticmethod
    def get_typed[T: AnyType](
        b: Bindings, env: NapiEnv, val: NapiValue, context: String
    ) raises -> Pointer[T, MutAnyOrigin]:
        """Type-check + get_data + bitcast[T] in one call.

        Raises a TypeError whose message begins with `context` when `val` is
        not a JS External handle.
        """
        var t = js_typeof(b, env, val)
        if t != NAPI_TYPE_EXTERNAL:
            throw_js_type_error_dynamic(
                b, env, context + ": expected external, got " + js_type_name(t)
            )
            raise Error("not an external")
        var data = JsExternal.get_data(b, env, val)
        return data.unsafe_bitcast[T]()


## Generic finalizer for JsExternal.create_typed
##
## Monomorphized per T; its address is taken via the standard fn-ptr bitcast.
## Not declared `abi("C")` — matches the convention used by every other
## finalizer in src/addon/ (external_finalize, progress_finalize_cb, etc.).
def _typed_external_finalize[T: Movable & Deinitable](
    env: NapiEnv,
    data: OpaquePointer[MutAnyOrigin],
    hint: OpaquePointer[MutAnyOrigin],
):
    var ptr = data.unsafe_bitcast[T]()
    ptr.unsafe_deinit_pointee()
    ptr.unsafe_free()
