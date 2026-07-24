## src/napi/framework/js_boolean.mojo — ergonomic wrapper for JavaScript boolean values
##
## JsBoolean hides the raw pointer operations needed to create and read JS booleans:
##
##   # Create a JS boolean from a Mojo Bool:
##   var b = JsBoolean.create(env, True)
##   return b.value
##
##   # Read a NapiValue as a Mojo Bool:
##   var flag = JsBoolean.from_napi_value(env, napi_val)
##
## N-API note: JavaScript has true/false singletons, so napi_get_boolean returns
## the pre-existing singleton rather than allocating a new value.

from napi.types import NapiEnv, NapiValue
from napi.raw import raw_get_boolean, raw_get_value_bool
from napi.error import check_status
from napi.bindings import Bindings


## JsBoolean — typed wrapper for a JavaScript boolean napi_value
struct JsBoolean:
    ## The underlying napi_value handle. Valid within the current handle scope.
    @__allow_legacy_any_origin_fields
    var value: NapiValue

    def __init__(out self, value: NapiValue):
        self.value = value

    ## create — construct a JsBoolean from a Mojo Bool
    ##
    ## Calls napi_get_boolean (returns the JS true/false singleton) and checks
    ## the status.

    ## env-only: required by callbacks that have no NapiBindings pointer —
    ## e.g. addons built with ModuleBuilder(env, exports). Not deprecated.
    @staticmethod
    def create(env: NapiEnv, bval: Bool) raises -> JsBoolean:
        var result: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
            to=result
        ).bitcast[NoneType]().as_unsafe_any_origin()
        check_status(raw_get_boolean(env, bval, result_ptr))
        return JsBoolean(result)

    @staticmethod
    def create(b: Bindings, env: NapiEnv, bval: Bool) raises -> JsBoolean:
        var result: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
            to=result
        ).bitcast[NoneType]().as_unsafe_any_origin()
        var status = raw_get_boolean(b, env, bval, result_ptr)
        check_status(status)
        return JsBoolean(result)

    ## from_napi_value — read a NapiValue as a Mojo Bool
    ##
    ## Calls napi_get_value_bool and checks the status.
    ## The NapiValue must hold a JS boolean; raises `napi_boolean_expected`
    ## otherwise.

    ## env-only: required by convert.mojo's JsBool.from_js(env), which serves
    ## callbacks that cannot reach cached bindings.
    @staticmethod
    def from_napi_value(env: NapiEnv, val: NapiValue) raises -> Bool:
        var bval: Bool = False
        var b_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=bval).bitcast[
            NoneType
        ]().as_unsafe_any_origin()
        var status = raw_get_value_bool(env, val, b_ptr)
        check_status(status)
        return bval

    @staticmethod
    def from_napi_value(
        b: Bindings, env: NapiEnv, val: NapiValue
    ) raises -> Bool:
        var bval: Bool = False
        var b_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=bval).bitcast[
            NoneType
        ]().as_unsafe_any_origin()
        var status = raw_get_value_bool(b, env, val, b_ptr)
        check_status(status)
        return bval
