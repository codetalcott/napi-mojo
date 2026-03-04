## src/napi/framework/js_external.mojo — external data wrapper
##
## JsExternal wraps napi_create_external / napi_get_value_external.
## Creates a JavaScript value that holds an opaque native pointer with
## an optional GC finalize callback.

from napi.types import NapiEnv, NapiValue
from napi.raw import raw_create_external, raw_get_value_external
from napi.error import check_status

struct JsExternal:
    var value: NapiValue

    fn __init__(out self, value: NapiValue):
        self.value = value

    @staticmethod
    fn create(
        env: NapiEnv,
        data: OpaquePointer[MutAnyOrigin],
        finalize_cb: OpaquePointer[MutAnyOrigin],
    ) raises -> JsExternal:
        """Create an external with a finalize callback (called on GC)."""
        var result = NapiValue()
        check_status(raw_create_external(
            env,
            data,
            finalize_cb,
            OpaquePointer[MutAnyOrigin](),  # finalize_hint = NULL
            UnsafePointer(to=result).bitcast[NoneType](),
        ))
        return JsExternal(result)

    @staticmethod
    fn create_no_release(
        env: NapiEnv,
        data: OpaquePointer[MutAnyOrigin],
    ) raises -> JsExternal:
        """Create an external with no finalize callback."""
        var result = NapiValue()
        check_status(raw_create_external(
            env,
            data,
            OpaquePointer[MutAnyOrigin](),  # finalize_cb = NULL
            OpaquePointer[MutAnyOrigin](),  # finalize_hint = NULL
            UnsafePointer(to=result).bitcast[NoneType](),
        ))
        return JsExternal(result)

    @staticmethod
    fn get_data(env: NapiEnv, val: NapiValue) raises -> OpaquePointer[MutAnyOrigin]:
        """Retrieve the opaque data pointer from an external value."""
        var result = OpaquePointer[MutAnyOrigin]()
        check_status(raw_get_value_external(
            env, val,
            UnsafePointer(to=result).bitcast[NoneType](),
        ))
        return result
