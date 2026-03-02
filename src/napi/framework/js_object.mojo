## src/napi/framework/js_object.mojo — ergonomic wrapper for JavaScript object values
##
## JsObject hides the raw pointer operations needed to create and mutate a JS
## object, giving addon authors a clean API:
##
##   var obj = JsObject.create(env)
##   var msg = JsString.create_literal(env, "Hello!")
##   obj.set_property(env, "message", msg.value)     # StringLiteral key (preferred)
##   return obj.value
##
##   # Heap String key (use when key is computed at runtime):
##   var key = String("message")
##   obj.set_named_property(env, key, msg.value)
##
## String lifetime: property name strings passed to set_named_property must
## remain alive for the duration of the call. Use named `var` bindings.
## set_property takes a StringLiteral (static lifetime), so no lifetime
## management is needed on the caller side.

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

    ## set_property — set a named property using a StringLiteral key
    ##
    ## Preferred overload for compile-time-known property names. Uses the
    ## literal's static (.rodata) pointer directly — no heap allocation,
    ## no ASAP lifetime concern.
    fn set_property(self, env: NapiEnv, key: StringLiteral, val: NapiValue) raises:
        var key_ptr: OpaquePointer[ImmutAnyOrigin] = key.unsafe_ptr().bitcast[NoneType]()
        var status = raw_set_named_property(env, self.value, key_ptr, val)
        check_status(status)

    ## set_named_property — set a named property using a heap String key
    ##
    ## Use when the property name is computed at runtime. `name` is borrowed —
    ## the caller's String must remain alive for the duration of this call
    ## (use a named `var`).
    fn set_named_property(self, env: NapiEnv, name: String, val: NapiValue) raises:
        var name_ptr: OpaquePointer[ImmutAnyOrigin] = name.unsafe_ptr().bitcast[NoneType]()
        var status = raw_set_named_property(env, self.value, name_ptr, val)
        check_status(status)
