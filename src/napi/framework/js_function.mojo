"""Ergonomic wrapper for calling and creating JavaScript functions.

```mojo
var f = JsFunction(some_callback_value)
var out = f.call1(b, env, arg)
```

**`this` binding is the trap here.** `call0`/`call1`/`call2`/`call_n` all
pass `undefined` as the receiver, which silently breaks any callee that
reads `this` — a method pulled off an object and called this way loses its
object. Use `call_with` for an explicit receiver, or
`JsObject.call_method`, which looks the method up and binds `this` for you.

**Argument lifetime.** The variadic forms build an argv buffer from a
`List[NapiValue]` and keep it alive across the FFI call. An empty list
passes a genuine null argv rather than the data pointer of an empty List.

**Created functions are not garbage-collected on the Mojo side.** Data
passed via `create_with_data` has no finalizer hook, so it leaks unless
you free it yourself. Use `JsExternal` or a class wrap when you need the
GC to own the lifetime.
"""


from napi.types import NapiEnv, NapiValue, NapiStore, NapiConstStore, NapiPropertyDescriptor
from napi.bindings import Bindings
from napi.raw import raw_call_function, raw_get_undefined, raw_create_function
from napi.error import check_status
from napi.module import define_property
from napi.framework.js_number import JsNumber
from napi.keepalive import pin_across_ffi


## JsFunction — typed wrapper for a JavaScript function napi_value
struct JsFunction:
    """Typed wrapper for a callable JavaScript napi_value.
    """
    ## The underlying napi_value handle. Valid within the current handle scope.
    var value: NapiValue
    """The underlying napi_value handle. Valid within the current handle scope.
    """

    def __init__(out self, value: NapiValue):
        """Wrap an existing napi_value known to be callable.

        This does not validate the handle; `js_typeof` reports
        `NAPI_TYPE_FUNCTION` for callables.

        Args:
            value: The napi_value to wrap.
        """
        self.value = value

    # --- Bindings-aware overloads ---

    def call0(self, b: Bindings, env: NapiEnv) raises -> NapiValue:
        """Call the function with no arguments and `undefined` as `this`.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.

        Returns:
            The function's return value.

        Raises:
            If the call throws, or napi_call_function fails.
        """
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
        """Call the function with one argument and `undefined` as `this`.

        Use `call_with` if the callee reads `this`.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            arg: The single argument.

        Returns:
            The function's return value.

        Raises:
            If the call throws, or napi_call_function fails.
        """
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
        pin_across_ffi(arg0)  # napi reads argv during the call
        return result

    def call2(
        self, b: Bindings, env: NapiEnv, arg0: NapiValue, arg1: NapiValue
    ) raises -> NapiValue:
        """Call the function with two arguments and `undefined` as `this`.

        Use `call_with` if the callee reads `this`.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            arg1: The first argument.
            arg2: The second argument.

        Returns:
            The function's return value.

        Raises:
            If the call throws, or napi_call_function fails.
        """
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
        pin_across_ffi(args)  # napi reads argv during the call
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
        # Keep `args`'s heap buffer alive past the FFI call. `unsafe_ptr()` is
        # NOT a tracked use, so ASAP destruction is otherwise free to release
        # the buffer napi is mid-read on. This is the argv lifetime hazard
        # CLAUDE.md flags for call1/call2.
        pin_across_ffi(args)
        return result
    @staticmethod
    def create(
        b: Bindings,
        env: NapiEnv,
        name: StringLiteral,
        cb_ptr: OpaquePointer[MutAnyOrigin],
    ) raises -> JsFunction:
        """Create a JS function backed by a Mojo callback.

        The callback must have the napi_callback signature and must not let a
        Mojo exception escape into C.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            name: The function's name, as a compile-time literal.
            cb_ptr: The callback, via `fn_ptr(...)`.

        Returns:
            A JsFunction wrapping the new function.

        Raises:
            If napi_create_function does not return napi_ok.
        """
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
        """Create a JS function carrying an arbitrary data pointer.

        The callback retrieves the pointer with `CbArgs.get_data`. This is the
        closure mechanism for plain functions.

        **The data is never freed for you** — a plain function has no finalizer
        hook, so heap data passed here leaks unless you free it yourself.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            name: The function's name, as a compile-time literal.
            cb_ptr: The callback, via `fn_ptr(...)`.
            data: Pointer handed to the callback on every invocation.

        Returns:
            A JsFunction wrapping the new function.

        Raises:
            If napi_create_function does not return napi_ok.
        """
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
        """Create a JS function with a runtime name and declared arity.

        The String overload of `create`, for a name computed at runtime. The
        `data_ptr` overload additionally carries closure data, with the same
        no-finalizer caveat as `create_with_data`.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            name: The function's name.
            length: The value reported as the function's `length`.
            cb_ptr: The callback, via `fn_ptr(...)`.
            data_ptr: Closure data (data overload only).

        Returns:
            A JsFunction wrapping the new function.

        Raises:
            If napi_create_function does not return napi_ok.
        """
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
        """Create a JS function with a runtime name and declared arity.

        The String overload of `create`, for a name computed at runtime. The
        `data_ptr` overload additionally carries closure data, with the same
        no-finalizer caveat as `create_with_data`.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            name: The function's name.
            length: The value reported as the function's `length`.
            cb_ptr: The callback, via `fn_ptr(...)`.
            data_ptr: Closure data (data overload only).

        Returns:
            A JsFunction wrapping the new function.

        Raises:
            If napi_create_function does not return napi_ok.
        """
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
        pin_across_ffi(name)  # napi reads name_ptr during the call
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
