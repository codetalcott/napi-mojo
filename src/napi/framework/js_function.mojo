## src/napi/framework/js_function.mojo — ergonomic wrapper for JavaScript function values
##
## JsFunction wraps the calling convention for JS functions:
##
##   var func = JsFunction(napi_val)
##   var result = func.call0(env)               # no args
##   var result = func.call1(env, arg0)          # one arg
##   var result = func.call2(env, arg0, arg1)    # two args
##   var result = func.call_n(env, args)         # runtime-length List
##   var result = func.call_with(env, recv, args) # explicit `this`
##
## call0/call1/call2/call_n use `undefined` as the `this` value; call_with
## takes it explicitly, which is what method invocation requires (see
## JsObject.call_method). The function must already be a valid JS function
## napi_value (check with js_typeof first).

from napi.types import NapiEnv, NapiValue, NapiStore, NapiConstStore, NapiPropertyDescriptor
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

    def call_n(
        self, b: Bindings, env: NapiEnv, args: List[NapiValue]
    ) raises -> NapiValue:
        """Call the function with N arguments and `undefined` as `this`.

        `call0`/`call1`/`call2` remain the allocation-free fast paths; reach
        for this one when the argument count is only known at runtime.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            args: The arguments, in order. May be empty.

        Returns:
            The value the function returned.

        Raises:
            Error: If the call fails, or the callee threw. A JS exception
                raised by the callee stays pending and keeps its identity —
                do not throw a replacement error over it.
        """
        var recv: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var recv_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=recv
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        check_status(raw_get_undefined(b, env, recv_ptr))
        return self.call_with(b, env, recv, args)

    def call_with(
        self,
        b: Bindings,
        env: NapiEnv,
        recv: NapiValue,
        args: List[NapiValue],
    ) raises -> NapiValue:
        """Call the function with N arguments and an explicit `this`.

        Method calls need this: `obj.method(...)` only behaves correctly when
        `recv` is `obj`. `JsObject.call_method` is the ergonomic wrapper.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            recv: The `this` value for the call.
            args: The arguments, in order. May be empty.

        Returns:
            The value the function returned.

        Raises:
            Error: If the call fails, or the callee threw. A JS exception
                raised by the callee stays pending and keeps its identity —
                do not throw a replacement error over it.
        """
        var result: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=result
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        # An empty List's data pointer is not guaranteed dereferenceable, so
        # hand napi a genuine null argv rather than a zero-length buffer —
        # the same null_argv call0 passes.
        var argv_ptr = OpaquePointer[ImmutAnyOrigin](unsafe_from_address=Int(0))
        if len(args) > 0:
            argv_ptr = args.unsafe_ptr().unsafe_bitcast[
                NoneType
            ]().as_unsafe_any_origin()
        check_status(
            raw_call_function(
                b, env, recv, self.value, UInt(len(args)), argv_ptr, result_ptr
            )
        )
        # Keep `args` alive past the FFI call. `unsafe_ptr()` is NOT a tracked
        # use, so ASAP destruction is otherwise free to release the buffer
        # napi is mid-read on. Same idiom as create_named's `_ = name`; this
        # is the argv lifetime hazard CLAUDE.md flags for call1/call2.
        _ = args
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
        desc.utf8name = "length".unsafe_ptr().unsafe_bitcast[
            NoneType
        ]().unsafe_origin_cast[ImmUntrackedOrigin]()
        desc.method = NapiStore(unsafe_from_address=Int(0))
        desc.value = len_val.unsafe_origin_cast[MutUntrackedOrigin]()
        desc.attributes = 4  # napi_configurable
        desc.data = NapiStore(unsafe_from_address=Int(0))
        define_property(b, env, result, desc)
        return JsFunction(result)
