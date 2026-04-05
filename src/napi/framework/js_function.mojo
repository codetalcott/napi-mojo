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
    var value: NapiValue

    def __init__(out self, value: NapiValue):
        self.value = value

    ## call0 — call with no arguments, undefined as `this`
    def call0(self, env: NapiEnv) raises -> NapiValue:
        var recv: NapiValue = NapiValue()
        var recv_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
            to=recv
        ).bitcast[NoneType]()
        check_status(raw_get_undefined(env, recv_ptr))
        var result: NapiValue = NapiValue()
        var null_argv = OpaquePointer[ImmutAnyOrigin]()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
            to=result
        ).bitcast[NoneType]()
        check_status(
            raw_call_function(env, recv, self.value, 0, null_argv, result_ptr)
        )
        return result

    ## call1 — call with one argument, undefined as `this`
    ## bootstrap-safe: retained for TSFN call_js_cb which lacks an `info`
    ## parameter. Use call1(b, env, arg0) in all hot-path callbacks.
    def call1(self, env: NapiEnv, arg0: NapiValue) raises -> NapiValue:
        var recv: NapiValue = NapiValue()
        var recv_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
            to=recv
        ).bitcast[NoneType]()
        check_status(raw_get_undefined(env, recv_ptr))
        var result: NapiValue = NapiValue()
        var argv_ptr: OpaquePointer[ImmutAnyOrigin] = UnsafePointer(
            to=arg0
        ).bitcast[NoneType]()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
            to=result
        ).bitcast[NoneType]()
        check_status(
            raw_call_function(env, recv, self.value, 1, argv_ptr, result_ptr)
        )
        return result

    ## call2 — call with two arguments, undefined as `this`
    def call2(
        self, env: NapiEnv, arg0: NapiValue, arg1: NapiValue
    ) raises -> NapiValue:
        var recv: NapiValue = NapiValue()
        var recv_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
            to=recv
        ).bitcast[NoneType]()
        check_status(raw_get_undefined(env, recv_ptr))
        var args = InlineArray[NapiValue, 2](fill=NapiValue())
        args[0] = arg0
        args[1] = arg1
        var result: NapiValue = NapiValue()
        var argv_ptr: OpaquePointer[ImmutAnyOrigin] = UnsafePointer(
            to=args[0]
        ).bitcast[NoneType]()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
            to=result
        ).bitcast[NoneType]()
        check_status(
            raw_call_function(env, recv, self.value, 2, argv_ptr, result_ptr)
        )
        return result

    ## create — create a new JavaScript function from a napi_callback
    @staticmethod
    def create(
        env: NapiEnv, name: StringLiteral, cb_ptr: OpaquePointer[MutAnyOrigin]
    ) raises -> JsFunction:
        var result = NapiValue()
        var auto_length: UInt = ~UInt(0)
        check_status(
            raw_create_function(
                env,
                name.unsafe_ptr().bitcast[NoneType](),
                auto_length,
                cb_ptr,
                OpaquePointer[MutAnyOrigin](),
                UnsafePointer(to=result).bitcast[NoneType](),
            )
        )
        return JsFunction(result)

    ## create_with_data — create a JS function with an associated data pointer
    ##
    ## The data pointer is passed to the callback via napi_get_cb_info.
    @staticmethod
    def create_with_data(
        env: NapiEnv,
        name: StringLiteral,
        cb_ptr: OpaquePointer[MutAnyOrigin],
        data: OpaquePointer[MutAnyOrigin],
    ) raises -> JsFunction:
        var result = NapiValue()
        var auto_length: UInt = ~UInt(0)
        check_status(
            raw_create_function(
                env,
                name.unsafe_ptr().bitcast[NoneType](),
                auto_length,
                cb_ptr,
                data,
                UnsafePointer(to=result).bitcast[NoneType](),
            )
        )
        return JsFunction(result)

    # --- Bindings-aware overloads ---

    def call0(self, b: Bindings, env: NapiEnv) raises -> NapiValue:
        var recv: NapiValue = NapiValue()
        var recv_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
            to=recv
        ).bitcast[NoneType]()
        check_status(raw_get_undefined(b, env, recv_ptr))
        var result: NapiValue = NapiValue()
        var null_argv = OpaquePointer[ImmutAnyOrigin]()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
            to=result
        ).bitcast[NoneType]()
        check_status(
            raw_call_function(
                b, env, recv, self.value, 0, null_argv, result_ptr
            )
        )
        return result

    def call1(
        self, b: Bindings, env: NapiEnv, arg0: NapiValue
    ) raises -> NapiValue:
        var recv: NapiValue = NapiValue()
        var recv_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
            to=recv
        ).bitcast[NoneType]()
        check_status(raw_get_undefined(b, env, recv_ptr))
        var result: NapiValue = NapiValue()
        var argv_ptr: OpaquePointer[ImmutAnyOrigin] = UnsafePointer(
            to=arg0
        ).bitcast[NoneType]()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
            to=result
        ).bitcast[NoneType]()
        check_status(
            raw_call_function(b, env, recv, self.value, 1, argv_ptr, result_ptr)
        )
        return result

    def call2(
        self, b: Bindings, env: NapiEnv, arg0: NapiValue, arg1: NapiValue
    ) raises -> NapiValue:
        var recv: NapiValue = NapiValue()
        var recv_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
            to=recv
        ).bitcast[NoneType]()
        check_status(raw_get_undefined(b, env, recv_ptr))
        var args = InlineArray[NapiValue, 2](fill=NapiValue())
        args[0] = arg0
        args[1] = arg1
        var result: NapiValue = NapiValue()
        var argv_ptr: OpaquePointer[ImmutAnyOrigin] = UnsafePointer(
            to=args[0]
        ).bitcast[NoneType]()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
            to=result
        ).bitcast[NoneType]()
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
        var result = NapiValue()
        var auto_length: UInt = ~UInt(0)
        check_status(
            raw_create_function(
                b,
                env,
                name.unsafe_ptr().bitcast[NoneType](),
                auto_length,
                cb_ptr,
                OpaquePointer[MutAnyOrigin](),
                UnsafePointer(to=result).bitcast[NoneType](),
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
        var result = NapiValue()
        var auto_length: UInt = ~UInt(0)
        check_status(
            raw_create_function(
                b,
                env,
                name.unsafe_ptr().bitcast[NoneType](),
                auto_length,
                cb_ptr,
                data,
                UnsafePointer(to=result).bitcast[NoneType](),
            )
        )
        return JsFunction(result)

    ## create_named — create a JS function with an explicit name and arity hint
    ##
    ## Matches napi-rs's Function::new_with_length. `name` is a runtime String
    ## (vs StringLiteral for create/create_with_data) so the name can be
    ## computed at runtime. `length` sets fn.length (the arity hint) via a
    ## napi_define_properties call after creation.
    ##
    ## Note: pass NAPI_AUTO_LENGTH (~UInt(0)) as the string-length argument to
    ## raw_create_function so that N-API uses strlen() on the null-terminated
    ## name. The `length` Int parameter is the JavaScript arity, not the string
    ## byte-count.
    @staticmethod
    def create_named(
        env: NapiEnv,
        name: String,
        length: Int,
        cb_ptr: OpaquePointer[MutAnyOrigin],
    ) raises -> JsFunction:
        var result = NapiValue()
        var auto_length: UInt = ~UInt(0)
        var name_ptr: OpaquePointer[ImmutAnyOrigin] = name.unsafe_ptr().bitcast[
            NoneType
        ]()
        check_status(
            raw_create_function(
                env,
                name_ptr,
                auto_length,
                cb_ptr,
                OpaquePointer[MutAnyOrigin](),
                UnsafePointer(to=result).bitcast[NoneType](),
            )
        )
        _ = name  # keep name alive past FFI call (ASAP safety)
        # Set fn.length = length via napi_define_properties
        var len_val = JsNumber.create_int(env, length).value
        var desc = NapiPropertyDescriptor()
        desc.utf8name = "length".unsafe_ptr().bitcast[NoneType]()
        desc.method = OpaquePointer[MutAnyOrigin]()
        desc.value = len_val
        desc.attributes = 4  # napi_configurable
        desc.data = OpaquePointer[MutAnyOrigin]()
        define_property(env, result, desc)
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
            b, env, name, length, cb_ptr, OpaquePointer[MutAnyOrigin]()
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
        var result = NapiValue()
        var auto_length: UInt = ~UInt(0)
        var name_ptr: OpaquePointer[ImmutAnyOrigin] = name.unsafe_ptr().bitcast[
            NoneType
        ]()
        check_status(
            raw_create_function(
                b,
                env,
                name_ptr,
                auto_length,
                cb_ptr,
                data_ptr,
                UnsafePointer(to=result).bitcast[NoneType](),
            )
        )
        _ = name  # keep name alive past FFI call (ASAP safety)
        # Set fn.length = length via napi_define_properties
        var len_val = JsNumber.create_int(b, env, length).value
        var desc = NapiPropertyDescriptor()
        desc.utf8name = "length".unsafe_ptr().bitcast[NoneType]()
        desc.method = OpaquePointer[MutAnyOrigin]()
        desc.value = len_val
        desc.attributes = 4  # napi_configurable
        desc.data = OpaquePointer[MutAnyOrigin]()
        define_property(b, env, result, desc)
        return JsFunction(result)
