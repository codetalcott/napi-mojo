## src/napi/framework/js_function.mojo — ergonomic wrapper for JavaScript function values
##
## JsFunction wraps the calling convention for JS functions:
##
##   var func = JsFunction(napi_val)
##   var result = func.call0(env)               # no args
##   var result = func.call1(env, arg0)          # one arg
##   var result = func.call2(env, arg0, arg1)    # two args
##
## All call variants use `undefined` as the `this` value. The function must
## already be a valid JS function napi_value (check with js_typeof first).

from napi.types import NapiEnv, NapiValue
from napi.bindings import Bindings
from napi.raw import raw_call_function, raw_get_undefined, raw_create_function
from napi.error import check_status

## JsFunction — typed wrapper for a JavaScript function napi_value
struct JsFunction:
    ## The underlying napi_value handle. Valid within the current handle scope.
    var value: NapiValue

    fn __init__(out self, value: NapiValue):
        self.value = value

    ## call0 — call with no arguments, undefined as `this`
    fn call0(self, env: NapiEnv) raises -> NapiValue:
        var recv: NapiValue = NapiValue()
        var recv_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=recv).bitcast[NoneType]()
        check_status(raw_get_undefined(env, recv_ptr))
        var result: NapiValue = NapiValue()
        var null_argv = OpaquePointer[ImmutAnyOrigin]()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
        check_status(raw_call_function(env, recv, self.value, 0, null_argv, result_ptr))
        return result

    ## call1 — call with one argument, undefined as `this`
    fn call1(self, env: NapiEnv, arg0: NapiValue) raises -> NapiValue:
        var recv: NapiValue = NapiValue()
        var recv_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=recv).bitcast[NoneType]()
        check_status(raw_get_undefined(env, recv_ptr))
        var result: NapiValue = NapiValue()
        var argv_ptr: OpaquePointer[ImmutAnyOrigin] = UnsafePointer(to=arg0).bitcast[NoneType]()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
        check_status(raw_call_function(env, recv, self.value, 1, argv_ptr, result_ptr))
        return result

    ## call2 — call with two arguments, undefined as `this`
    fn call2(self, env: NapiEnv, arg0: NapiValue, arg1: NapiValue) raises -> NapiValue:
        var recv: NapiValue = NapiValue()
        var recv_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=recv).bitcast[NoneType]()
        check_status(raw_get_undefined(env, recv_ptr))
        var args = InlineArray[NapiValue, 2](fill=NapiValue())
        args[0] = arg0
        args[1] = arg1
        var result: NapiValue = NapiValue()
        var argv_ptr: OpaquePointer[ImmutAnyOrigin] = UnsafePointer(to=args[0]).bitcast[NoneType]()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
        check_status(raw_call_function(env, recv, self.value, 2, argv_ptr, result_ptr))
        return result

    ## create — create a new JavaScript function from a napi_callback
    @staticmethod
    fn create(env: NapiEnv, name: StringLiteral,
              cb_ptr: OpaquePointer[MutAnyOrigin]) raises -> JsFunction:
        var result = NapiValue()
        var auto_length: UInt = ~UInt(0)
        check_status(raw_create_function(env,
            name.unsafe_ptr().bitcast[NoneType](),
            auto_length,
            cb_ptr,
            OpaquePointer[MutAnyOrigin](),
            UnsafePointer(to=result).bitcast[NoneType]()))
        return JsFunction(result)

    ## create_with_data — create a JS function with an associated data pointer
    ##
    ## The data pointer is passed to the callback via napi_get_cb_info.
    @staticmethod
    fn create_with_data(env: NapiEnv, name: StringLiteral,
                        cb_ptr: OpaquePointer[MutAnyOrigin],
                        data: OpaquePointer[MutAnyOrigin]) raises -> JsFunction:
        var result = NapiValue()
        var auto_length: UInt = ~UInt(0)
        check_status(raw_create_function(env,
            name.unsafe_ptr().bitcast[NoneType](),
            auto_length,
            cb_ptr,
            data,
            UnsafePointer(to=result).bitcast[NoneType]()))
        return JsFunction(result)

    # --- Bindings-aware overloads ---

    fn call0(self, b: Bindings, env: NapiEnv) raises -> NapiValue:
        var recv: NapiValue = NapiValue()
        var recv_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=recv).bitcast[NoneType]()
        check_status(raw_get_undefined(b, env, recv_ptr))
        var result: NapiValue = NapiValue()
        var null_argv = OpaquePointer[ImmutAnyOrigin]()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
        check_status(raw_call_function(b, env, recv, self.value, 0, null_argv, result_ptr))
        return result

    fn call1(self, b: Bindings, env: NapiEnv, arg0: NapiValue) raises -> NapiValue:
        var recv: NapiValue = NapiValue()
        var recv_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=recv).bitcast[NoneType]()
        check_status(raw_get_undefined(b, env, recv_ptr))
        var result: NapiValue = NapiValue()
        var argv_ptr: OpaquePointer[ImmutAnyOrigin] = UnsafePointer(to=arg0).bitcast[NoneType]()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
        check_status(raw_call_function(b, env, recv, self.value, 1, argv_ptr, result_ptr))
        return result

    fn call2(self, b: Bindings, env: NapiEnv, arg0: NapiValue, arg1: NapiValue) raises -> NapiValue:
        var recv: NapiValue = NapiValue()
        var recv_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=recv).bitcast[NoneType]()
        check_status(raw_get_undefined(b, env, recv_ptr))
        var args = InlineArray[NapiValue, 2](fill=NapiValue())
        args[0] = arg0
        args[1] = arg1
        var result: NapiValue = NapiValue()
        var argv_ptr: OpaquePointer[ImmutAnyOrigin] = UnsafePointer(to=args[0]).bitcast[NoneType]()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
        check_status(raw_call_function(b, env, recv, self.value, 2, argv_ptr, result_ptr))
        return result

    @staticmethod
    fn create(b: Bindings, env: NapiEnv, name: StringLiteral,
              cb_ptr: OpaquePointer[MutAnyOrigin]) raises -> JsFunction:
        var result = NapiValue()
        var auto_length: UInt = ~UInt(0)
        check_status(raw_create_function(b, env,
            name.unsafe_ptr().bitcast[NoneType](),
            auto_length,
            cb_ptr,
            OpaquePointer[MutAnyOrigin](),
            UnsafePointer(to=result).bitcast[NoneType]()))
        return JsFunction(result)

    @staticmethod
    fn create_with_data(b: Bindings, env: NapiEnv, name: StringLiteral,
                        cb_ptr: OpaquePointer[MutAnyOrigin],
                        data: OpaquePointer[MutAnyOrigin]) raises -> JsFunction:
        var result = NapiValue()
        var auto_length: UInt = ~UInt(0)
        check_status(raw_create_function(b, env,
            name.unsafe_ptr().bitcast[NoneType](),
            auto_length,
            cb_ptr,
            data,
            UnsafePointer(to=result).bitcast[NoneType]()))
        return JsFunction(result)
