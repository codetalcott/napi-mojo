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

from napi.types import NapiEnv, NapiValue, NapiPropertyDescriptor
from napi.bindings import Bindings
from napi.raw import raw_call_function, raw_get_undefined, raw_create_function
from napi.error import check_status
from napi.module import define_property
from napi.framework.js_number import JsNumber


## JsFunction — typed wrapper for a JavaScript function napi_value
struct JsFunction:
    ## The underlying napi_value handle. Valid within the current handle scope.
    @__allow_legacy_any_origin_fields
    var value: NapiValue

    def __init__(out self, value: NapiValue):
        self.value = value

    # --- Bindings-aware overloads ---

    def call0(self, b: Bindings, env: NapiEnv) raises -> NapiValue:
        var recv: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var recv_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=recv
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        check_status(raw_get_undefined(b, env, recv_ptr))
        var result: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var null_argv = OpaquePointer[ImmutAnyOrigin](unsafe_from_address=Int(0))
        var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=result
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        check_status(
            raw_call_function(
                b, env, recv, self.value, 0, null_argv, result_ptr
            )
        )
        return result

    def call1(
        self, b: Bindings, env: NapiEnv, arg0: NapiValue
    ) raises -> NapiValue:
        var recv: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var recv_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=recv
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        check_status(raw_get_undefined(b, env, recv_ptr))
        var result: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var argv_ptr: OpaquePointer[ImmutAnyOrigin] = Pointer(
            to=arg0
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=result
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        check_status(
            raw_call_function(b, env, recv, self.value, 1, argv_ptr, result_ptr)
        )
        return result

    def call2(
        self, b: Bindings, env: NapiEnv, arg0: NapiValue, arg1: NapiValue
    ) raises -> NapiValue:
        var recv: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var recv_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=recv
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        check_status(raw_get_undefined(b, env, recv_ptr))
        var args = Array[NapiValue, 2](fill=NapiValue(unsafe_from_address=Int(0)))
        args[0] = arg0
        args[1] = arg1
        var result: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var argv_ptr: OpaquePointer[ImmutAnyOrigin] = Pointer(
            to=args[0]
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=result
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        check_status(
            raw_call_function(b, env, recv, self.value, 2, argv_ptr, result_ptr)
        )
        return result

    @staticmethod
    def create(
        b: Bindings,
        env: NapiEnv,
        name: StringLiteral,
        cb_ptr: OpaquePointer[MutAnyOrigin],
    ) raises -> JsFunction:
        var result = NapiValue(unsafe_from_address=Int(0))
        var auto_length: UInt = ~UInt(0)
        check_status(
            raw_create_function(
                b,
                env,
                name.unsafe_ptr().unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                auto_length,
                cb_ptr,
                OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0)),
                Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        return JsFunction(result)

    @staticmethod
    def create_with_data(
        b: Bindings,
        env: NapiEnv,
        name: StringLiteral,
        cb_ptr: OpaquePointer[MutAnyOrigin],
        data: OpaquePointer[MutAnyOrigin],
    ) raises -> JsFunction:
        var result = NapiValue(unsafe_from_address=Int(0))
        var auto_length: UInt = ~UInt(0)
        check_status(
            raw_create_function(
                b,
                env,
                name.unsafe_ptr().unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                auto_length,
                cb_ptr,
                data,
                Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        return JsFunction(result)

    @staticmethod
    def create_named(
        b: Bindings,
        env: NapiEnv,
        name: String,
        length: Int,
        cb_ptr: OpaquePointer[MutAnyOrigin],
    ) raises -> JsFunction:
        return JsFunction.create_named(
            b, env, name, length, cb_ptr, OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        )

    @staticmethod
    def create_named(
        b: Bindings,
        env: NapiEnv,
        name: String,
        length: Int,
        cb_ptr: OpaquePointer[MutAnyOrigin],
        data_ptr: OpaquePointer[MutAnyOrigin],
    ) raises -> JsFunction:
        var result = NapiValue(unsafe_from_address=Int(0))
        # Explicit byte length: a heap String has no guaranteed NUL
        # terminator, so NAPI_AUTO_LENGTH (strlen) would read out of bounds.
        var name_ptr: OpaquePointer[ImmutAnyOrigin] = name.unsafe_ptr().unsafe_bitcast[
            NoneType
        ]().as_unsafe_any_origin()
        check_status(
            raw_create_function(
                b,
                env,
                name_ptr,
                UInt(name.byte_length()),
                cb_ptr,
                data_ptr,
                Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        _ = name  # keep name alive past FFI call (ASAP safety)
        # Set fn.length = length via napi_define_properties
        var len_val = JsNumber.create_int(b, env, length).value
        var desc = NapiPropertyDescriptor()
        desc.utf8name = "length".unsafe_ptr().unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        desc.method = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        desc.value = len_val
        desc.attributes = 4  # napi_configurable
        desc.data = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        define_property(b, env, result, desc)
        return JsFunction(result)
