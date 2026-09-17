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

**Closure data is freed by the collector, never by a call.** A created
function may be called many times or never, so there is no "right call" to
free its data in. Pass heap data to the `finalize_cb` overload of
`create_with_data`, which frees it when the function is collected. The plain
overload frees nothing: use it only for data that outlives every function,
such as the bindings pointer.
"""


from napi.types import NapiEnv, NapiValue, NapiStore, NapiConstStore, NapiPropertyDescriptor
from napi.bindings import Bindings
from napi.raw import (
    raw_call_function,
    raw_get_undefined,
    raw_create_function,
    raw_add_finalizer,
)
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
                name.ptr().unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
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

        **The data is never freed for you.** For heap data, use the
        `finalize_cb` overload, which frees it when the function is collected
        — never free it when the callback fires, which may be never or many
        times. For a promise continuation, use `JsPromise.on_settled`.

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
                name.ptr().unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                auto_length,
                cb_ptr,
                data,
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
        finalize_cb: OpaquePointer[MutAnyOrigin],
    ) raises -> JsFunction:
        """Create a JS function whose closure data the collector frees.

        The closure mechanism for heap data. The callback retrieves `data`
        with `CbArgs.get_data`, on every call, for as long as the function is
        reachable; `finalize_cb(env, data, null)` runs once the function has
        been collected. Nothing is freed on the call path, so a function that
        is called many times — or never — is equally safe.

        `data` is ADOPTED on every path: if the function cannot be created or
        the finalizer cannot be attached, `finalize_cb` runs before this
        raises. Never free `data` yourself after passing it.

        The finalizer runs on the main thread after collection. Free memory
        there; do not call into JavaScript.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            name: The function's name, as a compile-time literal.
            cb_ptr: The callback, via `fn_ptr(...)`.
            data: Pointer handed to the callback on every invocation.
            finalize_cb: A `def(env, data, hint)` that frees `data`, via
                `fn_ptr(...)`. May be null, making this the plain overload.

        Returns:
            A JsFunction wrapping the new function.

        Raises:
            If the function could not be created or the finalizer attached.
            `data` has been finalized either way.
        """
        try:
            var f = JsFunction.create_with_data(b, env, name, cb_ptr, data)
            if Int(finalize_cb) != 0:
                check_status(
                    raw_add_finalizer(
                        b,
                        env,
                        f.value,
                        data,
                        finalize_cb,
                        OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0)),
                        OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0)),
                    )
                )
            return f^
        except e:
            # Nothing else can reach `data` now: a function that exists but
            # has no finalizer is never handed out, so it can never be called.
            _run_finalizer(env, finalize_cb, data)
            raise e^

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
        `data_ptr` overload additionally carries closure data and frees none
        of it, like the plain `create_with_data`; tie heap data to the result
        with `JsObject(fn.value).add_finalizer(...)`.

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
        `data_ptr` overload additionally carries closure data and frees none
        of it, like the plain `create_with_data`; tie heap data to the result
        with `JsObject(fn.value).add_finalizer(...)`.

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
        desc.utf8name = "length".ptr().unsafe_bitcast[
            NoneType
        ]().unsafe_origin_cast[ImmUntrackedOrigin]()
        desc.method = NapiStore(unsafe_from_address=Int(0))
        desc.value = len_val.unsafe_origin_cast[MutUntrackedOrigin]()
        desc.attributes = 4  # napi_configurable
        desc.data = NapiStore(unsafe_from_address=Int(0))
        define_property(b, env, result, desc)
        return JsFunction(result)


def _run_finalizer(
    env: NapiEnv,
    finalize_cb: OpaquePointer[MutAnyOrigin],
    data: OpaquePointer[MutAnyOrigin],
):
    # Call a napi_finalize-shaped function pointer directly, for the paths
    # where N-API never will (an adopted pointer whose finalizer could not be
    # attached). Reinterpret the WORD holding the address, never the address
    # itself — the trap raw.mojo's _sym documents. This is the only place the
    # cast is spelled; js_promise.mojo reuses it.
    if Int(finalize_cb) == 0:
        return
    var fn_word = finalize_cb
    var finalize = Pointer(to=fn_word).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
        ) thin abi("C") -> None
    ]()[]
    finalize(
        env.as_unsafe_any_origin(),
        data,
        OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0)),
    )
