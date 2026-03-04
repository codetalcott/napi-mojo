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
from napi.raw import (
    raw_create_reference, raw_delete_reference,
    raw_reference_ref, raw_reference_unref,
    raw_get_reference_value,
)
from napi.error import check_status

struct JsRef:
    var handle: NapiRef

    fn __init__(out self, handle: NapiRef):
        self.handle = handle

    @staticmethod
    fn create(env: NapiEnv, value: NapiValue, initial_refcount: UInt32) raises -> JsRef:
        var result = NapiRef()
        check_status(raw_create_reference(env, value, initial_refcount,
            UnsafePointer(to=result).bitcast[NoneType]()))
        return JsRef(result)

    fn delete(self, env: NapiEnv) raises:
        check_status(raw_delete_reference(env, self.handle))

    fn inc(self, env: NapiEnv) raises -> UInt32:
        var count: UInt32 = 0
        check_status(raw_reference_ref(env, self.handle,
            UnsafePointer(to=count).bitcast[NoneType]()))
        return count

    fn dec(self, env: NapiEnv) raises -> UInt32:
        var count: UInt32 = 0
        check_status(raw_reference_unref(env, self.handle,
            UnsafePointer(to=count).bitcast[NoneType]()))
        return count

    fn get(self, env: NapiEnv) raises -> NapiValue:
        var result = NapiValue()
        check_status(raw_get_reference_value(env, self.handle,
            UnsafePointer(to=result).bitcast[NoneType]()))
        return result
