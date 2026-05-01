## src/napi/framework/js_external.mojo — external data wrapper
##
## JsExternal wraps napi_create_external / napi_get_value_external.
## Creates a JavaScript value that holds an opaque native pointer with
## an optional GC finalize callback.

from std.memory import alloc
from napi.types import NapiEnv, NapiValue, NAPI_TYPE_EXTERNAL
from napi.bindings import Bindings
from napi.raw import raw_create_external, raw_get_value_external
from napi.error import check_status, throw_js_type_error_dynamic
from napi.framework.js_value import js_typeof, js_type_name


struct JsExternal:
    var value: NapiValue

    def __init__(out self, value: NapiValue):
        self.value = value

    @staticmethod
    def create(
        env: NapiEnv,
        data: OpaquePointer[MutAnyOrigin],
        finalize_cb: OpaquePointer[MutAnyOrigin],
    ) raises -> JsExternal:
        """Create an external with a finalize callback (called on GC)."""
        var result = NapiValue()
        check_status(
            raw_create_external(
                env,
                data,
                finalize_cb,
                OpaquePointer[MutAnyOrigin](),  # finalize_hint = NULL
                UnsafePointer(to=result).bitcast[NoneType](),
            )
        )
        return JsExternal(result)

    @staticmethod
    def create(
        b: Bindings,
        env: NapiEnv,
        data: OpaquePointer[MutAnyOrigin],
        finalize_cb: OpaquePointer[MutAnyOrigin],
    ) raises -> JsExternal:
        """Create an external with a finalize callback (called on GC)."""
        var result = NapiValue()
        check_status(
            raw_create_external(
                b,
                env,
                data,
                finalize_cb,
                OpaquePointer[MutAnyOrigin](),  # finalize_hint = NULL
                UnsafePointer(to=result).bitcast[NoneType](),
            )
        )
        return JsExternal(result)

    @staticmethod
    def create_no_release(
        env: NapiEnv,
        data: OpaquePointer[MutAnyOrigin],
    ) raises -> JsExternal:
        """Create an external with no finalize callback."""
        var result = NapiValue()
        check_status(
            raw_create_external(
                env,
                data,
                OpaquePointer[MutAnyOrigin](),  # finalize_cb = NULL
                OpaquePointer[MutAnyOrigin](),  # finalize_hint = NULL
                UnsafePointer(to=result).bitcast[NoneType](),
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
        var result = NapiValue()
        check_status(
            raw_create_external(
                b,
                env,
                data,
                OpaquePointer[MutAnyOrigin](),  # finalize_cb = NULL
                OpaquePointer[MutAnyOrigin](),  # finalize_hint = NULL
                UnsafePointer(to=result).bitcast[NoneType](),
            )
        )
        return JsExternal(result)

    @staticmethod
    def get_data(
        env: NapiEnv, val: NapiValue
    ) raises -> OpaquePointer[MutAnyOrigin]:
        """Retrieve the opaque data pointer from an external value."""
        var result = OpaquePointer[MutAnyOrigin]()
        check_status(
            raw_get_value_external(
                env,
                val,
                UnsafePointer(to=result).bitcast[NoneType](),
            )
        )
        return result

    @staticmethod
    def get_data(
        b: Bindings, env: NapiEnv, val: NapiValue
    ) raises -> OpaquePointer[MutAnyOrigin]:
        """Retrieve the opaque data pointer from an external value."""
        var result = OpaquePointer[MutAnyOrigin]()
        check_status(
            raw_get_value_external(
                b,
                env,
                val,
                UnsafePointer(to=result).bitcast[NoneType](),
            )
        )
        return result

    @staticmethod
    def create_typed[T: Movable & ImplicitlyDestructible](
        b: Bindings,
        env: NapiEnv,
        var value: T,
        fin_ptr: OpaquePointer[MutAnyOrigin],
    ) raises -> JsExternal:
        """Heap-allocate `value`, wrap in an External with a GC finalizer.

        `fin_ptr` is a C-callable finalizer with the signature
        `void(*)(napi_env, void*, void*)` that destroys the heap pointee
        and frees the slot. See `napi/framework/instance_data.mojo` for why
        the caller supplies this rather than the helper deriving it from T.
        """
        var data_ptr = alloc[T](1)
        data_ptr.init_pointee_move(value^)
        return JsExternal.create(
            b, env, data_ptr.bitcast[NoneType](), fin_ptr
        )

    @staticmethod
    def get_typed[T: AnyType](
        b: Bindings, env: NapiEnv, val: NapiValue, context: String
    ) raises -> UnsafePointer[T, MutAnyOrigin]:
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
        return data.bitcast[T]()


## See create_typed's docstring — caller supplies the finalizer pointer.
## (The old `_typed_external_finalize[T]` helper was removed because the
## Mojo address-of pattern doesn't yield a callable C-ABI fn pointer in
## 1.0.0b1.)
