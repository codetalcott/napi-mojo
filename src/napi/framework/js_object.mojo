## src/napi/framework/js_object.mojo — ergonomic wrapper for JavaScript object values
##
## JsObject hides the raw pointer operations needed to create and mutate a JS
## object, giving addon authors a clean API:
##
##   var obj = JsObject.create(env)                      # raises on N-API failure
##   var msg = JsString.create(env, "Hello!")
##   var key = String("message")
##   obj.set_named_property(env, key, msg.value)
##   return obj.value
##
## String lifetime: property name strings passed to set_named_property must
## remain alive for the duration of the call. Use named `var` bindings.

from napi.types import NapiEnv, NapiValue
from napi.raw import raw_create_object, raw_set_named_property
from napi.error import check_status

## JsObject — typed wrapper for a JavaScript object napi_value
struct JsObject:
    ## The underlying napi_value handle. Valid within the current handle scope.
    var value: NapiValue

    fn __init__(out self, value: NapiValue):
        self.value = value

    ## create — construct a new empty JavaScript object {}
    ##
    ## Calls napi_create_object and checks the status.
    @staticmethod
    fn create(env: NapiEnv) raises -> JsObject:
        var result: NapiValue = NapiValue()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
        var status = raw_create_object(env, result_ptr)
        check_status(status)
        return JsObject(result)

    ## set_named_property — set a named property on this object
    ##
    ## Calls napi_set_named_property. `name` is borrowed — the caller's String
    ## must remain alive for the duration of this call (use a named `var`).
    fn set_named_property(self, env: NapiEnv, name: String, val: NapiValue) raises:
        var name_ptr: OpaquePointer[ImmutAnyOrigin] = name.unsafe_ptr().bitcast[NoneType]()
        var status = raw_set_named_property(env, self.value, name_ptr, val)
        check_status(status)
