## src/napi/framework/js_ref.mojo — persistent reference wrapper
##
## JsRef wraps napi_ref for preventing GC of a napi_value. Create with
## an initial refcount, retrieve the value, and delete when done.
##
## Usage:
##   var ref = JsRef.create(env, some_value, 1)
##   var val = ref.get(env)
##   ref.delete(env)

from napi.types import NapiEnv, NapiValue, NapiRef
from napi.bindings import Bindings
from napi.raw import (
    raw_create_reference,
    raw_delete_reference,
    raw_reference_ref,
    raw_reference_unref,
    raw_get_reference_value,
)
from napi.error import check_status


struct JsRef:
    @__allow_legacy_any_origin_fields
    var handle: NapiRef

    def __init__(out self, handle: NapiRef):
        self.handle = handle

    # --- Bindings-aware overloads ---

    # --- Bindings-aware overloads ---

    @staticmethod
    def create(
        b: Bindings, env: NapiEnv, value: NapiValue, initial_refcount: UInt32
    ) raises -> JsRef:
        var result = NapiRef(unsafe_from_address=Int(0))
        check_status(
            raw_create_reference(
                b,
                env,
                value,
                initial_refcount,
                Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        return JsRef(result)

    def delete(self, b: Bindings, env: NapiEnv) raises:
        check_status(raw_delete_reference(b, env, self.handle))

    def inc(self, b: Bindings, env: NapiEnv) raises -> UInt32:
        var count: UInt32 = 0
        check_status(
            raw_reference_ref(
                b,
                env,
                self.handle,
                Pointer(to=count).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        return count

    def dec(self, b: Bindings, env: NapiEnv) raises -> UInt32:
        var count: UInt32 = 0
        check_status(
            raw_reference_unref(
                b,
                env,
                self.handle,
                Pointer(to=count).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        return count

    def get(self, b: Bindings, env: NapiEnv) raises -> NapiValue:
        var result = NapiValue(unsafe_from_address=Int(0))
        check_status(
            raw_get_reference_value(
                b,
                env,
                self.handle,
                Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        return result

    @staticmethod
    def create_weak(
        b: Bindings, env: NapiEnv, value: NapiValue
    ) raises -> JsRef:
        return JsRef.create(b, env, value, 0)
