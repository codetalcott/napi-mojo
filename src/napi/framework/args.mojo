"""Reading a callback's arguments, receiver, and cached bindings.

`CbArgs` wraps `napi_get_cb_info`, which is the single call that unpacks
everything a `napi_callback` was invoked with. The first thing almost every
callback does is fetch its cached bindings:

```mojo
# inside a napi_callback — see examples/hello-addon.mojo for the whole file
try:
    var r = CbArgs.get_bindings_and_one(env, info)
    return JsString.create(r.b, env, "hi").value
except:
    throw_js_error(env, "greet failed")
    return NapiValue(unsafe_from_address=Int(0))
```

(The example shows the body rather than the `def` line on purpose:
scripts/check-compile-coverage.mjs scans for public declarations by regex, and
a `def` inside a doc fence reads to it as an uncovered method — the same
reason js_host.mojo writes its example that way.)

**Prefer the fused `get_bindings_and_*` accessors.** They make ONE
`napi_get_cb_info` call and return both the bindings and the arguments;
calling `get_bindings` and then `get_one` makes two.

**Overload pairs.** Most accessors exist twice — taking cached `Bindings`,
and env-only. The env-only forms resolve `napi_get_cb_info` per call and
exist for contexts where bindings are genuinely unavailable: async complete
callbacks, ThreadsafeFunction callbacks, finalizers, and `except:` blocks
reached because bindings retrieval itself failed. Everywhere else, pass
Bindings.

**Arity is checked, not padded.** `get_one`/`get_two`/`get_three`/`get_four`
raise when the caller supplied fewer arguments. For a variadic callback,
use `argc` to size a buffer and `get_argv` to fill it — N-API pads argv
with `undefined` and drops extras, so compare `get_argv`'s return value
against your buffer size to detect either case.
"""


from napi.types import NapiEnv, NapiValue
from napi.raw import raw_get_cb_info
from napi.error import check_status
from napi.bindings import NapiBindings, Bindings, BINDINGS_MAGIC
from napi.keepalive import pin_across_ffi


## _verified_bindings — bitcast callback data to Bindings, checking the magic
##
## The data pointer is caller-controlled: an addon can register a callback
## with arbitrary data (JsFunction.create_with_data, ClassBuilder data) and
## still call a get_bindings* helper here, which would otherwise hand back
## 143 garbage function pointers — a jump to garbage inside Node on first
## use. The sentinel (written by NapiBindings.__init__, see bindings.mojo)
## turns that mistake into a raised Mojo error for one extra word read; the
## callback's except block then throws a normal JS error.
def _verified_bindings(data: OpaquePointer[MutAnyOrigin]) raises -> Bindings:
    if Int(data) == 0:
        raise Error("get_bindings: callback data is NULL, not NapiBindings")
    var b = data.unsafe_bitcast[NapiBindings]().unsafe_origin_cast[
        MutUntrackedOrigin
    ]()
    if b[].magic != BINDINGS_MAGIC:
        raise Error(
            "get_bindings: callback data is not a NapiBindings pointer"
        )
    return b


## bindings_from_context — recover cached Bindings from an opaque pointer
##
## For callbacks that receive the bindings pointer through a channel other
## than napi_callback data:
##   - TSFN call_js_cb: ThreadsafeFunction.create(b, ...) registers the
def bindings_from_context(
    context: OpaquePointer[MutAnyOrigin],
) raises -> Bindings:
    """Recover cached bindings from a designated carrier pointer.

    For callbacks N-API does not hand `info` to, the bindings pointer travels
    in whatever slot that callback *does* receive: the TSFN `context` (and
    the same pointer as the TSFN finalize_cb's `finalize_hint`), or a
    `wrap_native` finalizer's `finalize_hint`.

    Verifies the BINDINGS_MAGIC sentinel. In a teardown path where a null is
    expected, check `Int(ptr)` first and drop the call rather than relying on
    the raise.

    Args:
        context: The carrier pointer.

    Returns:
        The cached Bindings.

    Raises:
        If the pointer is null or does not carry the magic sentinel.
    """
    return _verified_bindings(context)


struct BindingsAndOne:
    """Result of a fused accessor: bindings plus one argument.

    Returned by the matching `CbArgs.get_bindings_*` method, which fills
    it from a single `napi_get_cb_info` call.
    """
    var b: Bindings
    """The cached N-API bindings for this environment."""
    var arg0: NapiValue
    """The first callback argument."""

    def __init__(out self, b: Bindings, arg0: NapiValue):
        """Build the result directly.

        Normally produced by the matching `CbArgs.get_bindings_*` method
        rather than constructed by hand.

        Args:
            b: The cached N-API bindings for this environment.
            arg0: The first callback argument.
        """
        self.b = b
        self.arg0 = arg0


struct BindingsAndTwo:
    """Result of a fused accessor: bindings plus two arguments.

    Returned by the matching `CbArgs.get_bindings_*` method, which fills
    it from a single `napi_get_cb_info` call.
    """
    var b: Bindings
    """The cached N-API bindings for this environment."""
    var arg0: NapiValue
    """The first callback argument."""
    var arg1: NapiValue
    """The second callback argument."""

    def __init__(out self, b: Bindings, arg0: NapiValue, arg1: NapiValue):
        """Build the result directly.

        Normally produced by the matching `CbArgs.get_bindings_*` method
        rather than constructed by hand.

        Args:
            b: The cached N-API bindings for this environment.
            arg0: The first callback argument.
            arg1: The second callback argument.
        """
        self.b = b
        self.arg0 = arg0
        self.arg1 = arg1


struct BindingsAndThree:
    """Result of a fused accessor: bindings plus three arguments.

    Returned by the matching `CbArgs.get_bindings_*` method, which fills
    it from a single `napi_get_cb_info` call.
    """
    var b: Bindings
    """The cached N-API bindings for this environment."""
    var arg0: NapiValue
    """The first callback argument."""
    var arg1: NapiValue
    """The second callback argument."""
    var arg2: NapiValue
    """The third callback argument."""

    def __init__(
        out self, b: Bindings, arg0: NapiValue, arg1: NapiValue, arg2: NapiValue
    ):
        """Build the result directly.

        Normally produced by the matching `CbArgs.get_bindings_*` method
        rather than constructed by hand.

        Args:
            b: The cached N-API bindings for this environment.
            arg0: The first callback argument.
            arg1: The second callback argument.
            arg2: The third callback argument.
        """
        self.b = b
        self.arg0 = arg0
        self.arg1 = arg1
        self.arg2 = arg2


struct BindingsAndThis:
    """Result of a fused accessor: bindings plus the receiver.

    Returned by the matching `CbArgs.get_bindings_*` method, which fills
    it from a single `napi_get_cb_info` call.
    """
    var b: Bindings
    """The cached N-API bindings for this environment."""
    var this_val: NapiValue
    """The callback's receiver (`this`)."""

    def __init__(out self, b: Bindings, this_val: NapiValue):
        """Build the result directly.

        Normally produced by the matching `CbArgs.get_bindings_*` method
        rather than constructed by hand.

        Args:
            b: The cached N-API bindings for this environment.
            this_val: The callback's receiver (`this`).
        """
        self.b = b
        self.this_val = this_val


struct BindingsThisAndOne:
    """Result of a fused accessor: bindings, the receiver, and one argument.

    Returned by the matching `CbArgs.get_bindings_*` method, which fills
    it from a single `napi_get_cb_info` call.
    """
    var b: Bindings
    """The cached N-API bindings for this environment."""
    var this_val: NapiValue
    """The callback's receiver (`this`)."""
    var arg0: NapiValue
    """The first callback argument."""

    def __init__(out self, b: Bindings, this_val: NapiValue, arg0: NapiValue):
        """Build the result directly.

        Normally produced by the matching `CbArgs.get_bindings_*` method
        rather than constructed by hand.

        Args:
            b: The cached N-API bindings for this environment.
            this_val: The callback's receiver (`this`).
            arg0: The first callback argument.
        """
        self.b = b
        self.this_val = this_val
        self.arg0 = arg0


struct CbArgs:
    """Static accessors over `napi_get_cb_info`.

    Never instantiated — a namespace for the callback-unpacking helpers.
    See the module docstring for the overload and arity rules.
    """
    ## get_one — extract exactly one callback argument (env-only)
    ##
    ## env-only: for async complete, TSFN, finalizer, and except-block callbacks
    ## where NapiBindings is unavailable. Use the bindings overload in hot paths.
    ##
    ## Calls napi_get_cb_info requesting 1 argument. Raises if the caller
    ## provided fewer than 1 argument.
    @staticmethod
    def get_one(env: NapiEnv, info: NapiValue) raises -> NapiValue:
        """Extract exactly one callback argument.

        Raises when the caller supplied fewer than 1 — arguments are checked,
        not silently padded with undefined.

        Exists as a Bindings overload and an env-only overload; prefer the
        Bindings form outside finalizer/TSFN/except contexts.

        Args:
            b: Cached N-API bindings (Bindings overload only).
            env: The N-API environment.
            info: The callback info handle.

        Returns:
            The argument.

        Raises:
            If fewer than 1 arguments were supplied, or napi_get_cb_info fails.
        """
        var argc: UInt = 1
        var arg0: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        check_status(
            raw_get_cb_info(
                env,
                info,
                Pointer(to=argc).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                Pointer(to=arg0).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                null,
                null,
            )
        )
        if argc < 1:
            raise Error("expected at least 1 argument")
        return arg0

    @staticmethod
    def get_one(b: Bindings, env: NapiEnv, info: NapiValue) raises -> NapiValue:
        """Extract exactly one callback argument.

        Raises when the caller supplied fewer than 1 — arguments are checked,
        not silently padded with undefined.

        Exists as a Bindings overload and an env-only overload; prefer the
        Bindings form outside finalizer/TSFN/except contexts.

        Args:
            b: Cached N-API bindings (Bindings overload only).
            env: The N-API environment.
            info: The callback info handle.

        Returns:
            The argument.

        Raises:
            If fewer than 1 arguments were supplied, or napi_get_cb_info fails.
        """
        var argc: UInt = 1
        var arg0: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        check_status(
            raw_get_cb_info(
                b,
                env,
                info,
                Pointer(to=argc).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                Pointer(to=arg0).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                null,
                null,
            )
        )
        if argc < 1:
            raise Error("expected at least 1 argument")
        return arg0

    ## get_two — extract exactly two callback arguments
    ##
    ## Calls napi_get_cb_info requesting 2 arguments via an
    ## Array[NapiValue, 2] argv buffer. Raises if the caller
    ## provided fewer than 2 arguments.
    @staticmethod
    def get_two(
        env: NapiEnv, info: NapiValue
    ) raises -> Array[NapiValue, 2]:
        """Extract exactly two callback arguments.

        Raises when the caller supplied fewer than 2 — arguments are checked,
        not silently padded with undefined.

        Exists as a Bindings overload and an env-only overload; prefer the
        Bindings form outside finalizer/TSFN/except contexts.

        Args:
            b: Cached N-API bindings (Bindings overload only).
            env: The N-API environment.
            info: The callback info handle.

        Returns:
            A tuple of the two arguments, in order.

        Raises:
            If fewer than 2 arguments were supplied, or napi_get_cb_info fails.
        """
        var argc: UInt = 2
        var args = Array[NapiValue, 2](fill=NapiValue(unsafe_from_address=Int(0)))
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        check_status(
            raw_get_cb_info(
                env,
                info,
                Pointer(to=argc).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                Pointer(to=args[0]).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                null,
                null,
            )
        )
        if argc < 2:
            raise Error("expected at least 2 arguments")
        return args^

    @staticmethod
    def get_two(
        b: Bindings, env: NapiEnv, info: NapiValue
    ) raises -> Array[NapiValue, 2]:
        """Extract exactly two callback arguments.

        Raises when the caller supplied fewer than 2 — arguments are checked,
        not silently padded with undefined.

        Exists as a Bindings overload and an env-only overload; prefer the
        Bindings form outside finalizer/TSFN/except contexts.

        Args:
            b: Cached N-API bindings (Bindings overload only).
            env: The N-API environment.
            info: The callback info handle.

        Returns:
            A tuple of the two arguments, in order.

        Raises:
            If fewer than 2 arguments were supplied, or napi_get_cb_info fails.
        """
        var argc: UInt = 2
        var args = Array[NapiValue, 2](fill=NapiValue(unsafe_from_address=Int(0)))
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        check_status(
            raw_get_cb_info(
                b,
                env,
                info,
                Pointer(to=argc).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                Pointer(to=args[0]).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                null,
                null,
            )
        )
        if argc < 2:
            raise Error("expected at least 2 arguments")
        return args^

    ## get_three — extract exactly three callback arguments
    @staticmethod
    def get_three(
        b: Bindings, env: NapiEnv, info: NapiValue
    ) raises -> Array[NapiValue, 3]:
        """Extract exactly three callback arguments.

        Raises when the caller supplied fewer than 3 — arguments are checked,
        not silently padded with undefined.

        Args:
            b: Cached N-API bindings (Bindings overload only).
            env: The N-API environment.
            info: The callback info handle.

        Returns:
            A tuple of the three arguments, in order.

        Raises:
            If fewer than 3 arguments were supplied, or napi_get_cb_info fails.
        """
        var argc: UInt = 3
        var args = Array[NapiValue, 3](fill=NapiValue(unsafe_from_address=Int(0)))
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        check_status(
            raw_get_cb_info(
                b,
                env,
                info,
                Pointer(to=argc).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                Pointer(to=args[0]).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                null,
                null,
            )
        )
        if argc < 3:
            raise Error("expected at least 3 arguments")
        return args^

    ## get_four — extract exactly four callback arguments
    @staticmethod
    def get_four(
        b: Bindings, env: NapiEnv, info: NapiValue
    ) raises -> Array[NapiValue, 4]:
        """Extract exactly four callback arguments.

        Raises when the caller supplied fewer than 4 — arguments are checked,
        not silently padded with undefined.

        Args:
            b: Cached N-API bindings (Bindings overload only).
            env: The N-API environment.
            info: The callback info handle.

        Returns:
            A tuple of the four arguments, in order.

        Raises:
            If fewer than 4 arguments were supplied, or napi_get_cb_info fails.
        """
        var argc: UInt = 4
        var args = Array[NapiValue, 4](fill=NapiValue(unsafe_from_address=Int(0)))
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        check_status(
            raw_get_cb_info(
                b,
                env,
                info,
                Pointer(to=argc).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                Pointer(to=args[0]).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                null,
                null,
            )
        )
        if argc < 4:
            raise Error("expected at least 4 arguments")
        return args^

    ## get_this — extract the `this` value from a callback
    ##
    ## Used by class method/getter/setter callbacks to get the JS instance.
    @staticmethod
    def get_this(env: NapiEnv, info: NapiValue) raises -> NapiValue:
        """Return the callback's receiver (`this`).

        The value a constructor wraps native state onto, and what an instance
        method unwraps from.

        Exists as a Bindings overload and an env-only overload; prefer the
        Bindings form outside finalizer/TSFN/except contexts.

        Args:
            b: Cached N-API bindings (Bindings overload only).
            env: The N-API environment.
            info: The callback info handle.

        Returns:
            The receiver.

        Raises:
            If napi_get_cb_info does not return napi_ok.
        """
        var argc: UInt = 0
        var this_val: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        check_status(
            raw_get_cb_info(
                env,
                info,
                Pointer(to=argc).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                null,
                Pointer(to=this_val).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                null,
            )
        )
        # `argc` is an IGNORED output slot: napi writes the arg count through
        # the pointer and nothing reads it back, so nothing else keeps the
        # slot alive across the call. Pin it explicitly.
        pin_across_ffi(argc)
        return this_val

    @staticmethod
    def get_this(
        b: Bindings, env: NapiEnv, info: NapiValue
    ) raises -> NapiValue:
        """Return the callback's receiver (`this`).

        The value a constructor wraps native state onto, and what an instance
        method unwraps from.

        Exists as a Bindings overload and an env-only overload; prefer the
        Bindings form outside finalizer/TSFN/except contexts.

        Args:
            b: Cached N-API bindings (Bindings overload only).
            env: The N-API environment.
            info: The callback info handle.

        Returns:
            The receiver.

        Raises:
            If napi_get_cb_info does not return napi_ok.
        """
        var argc: UInt = 0
        var this_val: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        check_status(
            raw_get_cb_info(
                b,
                env,
                info,
                Pointer(to=argc).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                null,
                Pointer(to=this_val).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                null,
            )
        )
        # `argc` is an IGNORED output slot: napi writes the arg count through
        # the pointer and nothing reads it back, so nothing else keeps the
        # slot alive across the call. Pin it explicitly.
        pin_across_ffi(argc)
        return this_val

    ## get_this_and_one — extract `this` plus one argument
    ##
    ## Returns [this, arg0] in an Array[NapiValue, 2].
    @staticmethod
    def get_this_and_one(
        env: NapiEnv, info: NapiValue
    ) raises -> Array[NapiValue, 2]:
        """Return the receiver and exactly one argument.

        One `napi_get_cb_info` call — the shape a setter or a single-argument
        instance method wants.

        Exists as a Bindings overload and an env-only overload; prefer the
        Bindings form outside finalizer/TSFN/except contexts.

        Args:
            b: Cached N-API bindings (Bindings overload only).
            env: The N-API environment.
            info: The callback info handle.

        Returns:
            A tuple of (this, arg0).

        Raises:
            If fewer than one argument was supplied, or napi_get_cb_info fails.
        """
        var argc: UInt = 1
        var arg0: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var this_val: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        check_status(
            raw_get_cb_info(
                env,
                info,
                Pointer(to=argc).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                Pointer(to=arg0).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                Pointer(to=this_val).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                null,
            )
        )
        if argc < 1:
            raise Error("expected at least 1 argument")
        var result = Array[NapiValue, 2](fill=NapiValue(unsafe_from_address=Int(0)))
        result[0] = this_val
        result[1] = arg0
        return result^

    @staticmethod
    def get_this_and_one(
        b: Bindings, env: NapiEnv, info: NapiValue
    ) raises -> Array[NapiValue, 2]:
        """Return the receiver and exactly one argument.

        One `napi_get_cb_info` call — the shape a setter or a single-argument
        instance method wants.

        Exists as a Bindings overload and an env-only overload; prefer the
        Bindings form outside finalizer/TSFN/except contexts.

        Args:
            b: Cached N-API bindings (Bindings overload only).
            env: The N-API environment.
            info: The callback info handle.

        Returns:
            A tuple of (this, arg0).

        Raises:
            If fewer than one argument was supplied, or napi_get_cb_info fails.
        """
        var argc: UInt = 1
        var arg0: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var this_val: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        check_status(
            raw_get_cb_info(
                b,
                env,
                info,
                Pointer(to=argc).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                Pointer(to=arg0).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                Pointer(to=this_val).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                null,
            )
        )
        if argc < 1:
            raise Error("expected at least 1 argument")
        var result = Array[NapiValue, 2](fill=NapiValue(unsafe_from_address=Int(0)))
        result[0] = this_val
        result[1] = arg0
        return result^

    ## argc — query the number of arguments without reading any
    @staticmethod
    def argc(env: NapiEnv, info: NapiValue) raises -> UInt:
        """Return how many arguments the caller actually supplied.

        Use it to size a buffer before `get_argv` for a variadic callback.

        Exists as a Bindings overload and an env-only overload; prefer the
        Bindings form outside finalizer/TSFN/except contexts.

        Args:
            b: Cached N-API bindings (Bindings overload only).
            env: The N-API environment.
            info: The callback info handle.

        Returns:
            The supplied argument count.

        Raises:
            If napi_get_cb_info does not return napi_ok.
        """
        var count: UInt = 0
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        check_status(
            raw_get_cb_info(
                env,
                info,
                Pointer(to=count).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                null,
                null,
                null,
            )
        )
        return count

    @staticmethod
    def argc(b: Bindings, env: NapiEnv, info: NapiValue) raises -> UInt:
        """Return how many arguments the caller actually supplied.

        Use it to size a buffer before `get_argv` for a variadic callback.

        Exists as a Bindings overload and an env-only overload; prefer the
        Bindings form outside finalizer/TSFN/except contexts.

        Args:
            b: Cached N-API bindings (Bindings overload only).
            env: The N-API environment.
            info: The callback info handle.

        Returns:
            The supplied argument count.

        Raises:
            If napi_get_cb_info does not return napi_ok.
        """
        var count: UInt = 0
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        check_status(
            raw_get_cb_info(
                b,
                env,
                info,
                Pointer(to=count).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                null,
                null,
                null,
            )
        )
        return count

    ## get_argv — read up to `count` arguments into a caller-provided buffer
    ##
    ## Returns the invocation's ACTUAL argument count as reported by
    ## napi_get_cb_info. N-API pads argv with `undefined` when the caller
    ## supplied fewer than `count` arguments and silently drops extras when
    ## it supplied more, so compare the return value against `count` to
    ## detect either case. Callers that pre-sized the buffer via argc() can
    ## discard the result with `_ =`.
    @staticmethod
    def get_argv(
        env: NapiEnv,
        info: NapiValue,
        count: UInt,
        argv_ptr: Pointer[NapiValue, MutAnyOrigin],
    ) raises -> UInt:
        """Fill a caller-provided buffer with the callback's arguments.

        N-API pads the buffer with `undefined` when fewer arguments were
        supplied and drops the extras when more were, so compare the RETURN
        value against `count` to detect either case. Discard it with `_ =` when
        the buffer was sized from `argc` and you do not care.

        Exists as a Bindings overload and an env-only overload; prefer the
        Bindings form outside finalizer/TSFN/except contexts.

        Args:
            b: Cached N-API bindings (Bindings overload only).
            env: The N-API environment.
            info: The callback info handle.
            count: Capacity of the buffer, in elements.
            argv: Buffer receiving the arguments.

        Returns:
            The number of arguments the caller actually supplied.

        Raises:
            If napi_get_cb_info does not return napi_ok.
        """
        var actual = count
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        check_status(
            raw_get_cb_info(
                env,
                info,
                Pointer(to=actual).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                argv_ptr.unsafe_bitcast[NoneType](),
                null,
                null,
            )
        )
        return actual

    @staticmethod
    def get_argv(
        b: Bindings,
        env: NapiEnv,
        info: NapiValue,
        count: UInt,
        argv_ptr: Pointer[NapiValue, MutAnyOrigin],
    ) raises -> UInt:
        """Fill a caller-provided buffer with the callback's arguments.

        N-API pads the buffer with `undefined` when fewer arguments were
        supplied and drops the extras when more were, so compare the RETURN
        value against `count` to detect either case. Discard it with `_ =` when
        the buffer was sized from `argc` and you do not care.

        Exists as a Bindings overload and an env-only overload; prefer the
        Bindings form outside finalizer/TSFN/except contexts.

        Args:
            b: Cached N-API bindings (Bindings overload only).
            env: The N-API environment.
            info: The callback info handle.
            count: Capacity of the buffer, in elements.
            argv: Buffer receiving the arguments.

        Returns:
            The number of arguments the caller actually supplied.

        Raises:
            If napi_get_cb_info does not return napi_ok.
        """
        var actual = count
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        check_status(
            raw_get_cb_info(
                b,
                env,
                info,
                Pointer(to=actual).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                argv_ptr.unsafe_bitcast[NoneType](),
                null,
                null,
            )
        )
        return actual

    ## get_data — extract the data pointer from a callback
    ##
    ## Used by dynamically-created functions (napi_create_function with data).
    @staticmethod
    def get_data(
        env: NapiEnv, info: NapiValue
    ) raises -> OpaquePointer[MutAnyOrigin]:
        """Return the callback's associated data pointer.

        For a function made by `JsFunction.create_with_data`, this is that
        closure data. For a callback registered through `ModuleBuilder` or
        `ClassBuilder`, it is the cached bindings pointer — which is what
        `get_bindings` reads.

        Exists as a Bindings overload and an env-only overload; prefer the
        Bindings form outside finalizer/TSFN/except contexts.

        Args:
            b: Cached N-API bindings (Bindings overload only).
            env: The N-API environment.
            info: The callback info handle.

        Returns:
            The data pointer.

        Raises:
            If napi_get_cb_info does not return napi_ok.
        """
        var argc: UInt = 0
        var data = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        check_status(
            raw_get_cb_info(
                env,
                info,
                Pointer(to=argc).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                null,
                null,
                Pointer(to=data).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        pin_across_ffi(argc)  # ignored output slot — see get_this
        return data

    @staticmethod
    def get_data(
        b: Bindings, env: NapiEnv, info: NapiValue
    ) raises -> OpaquePointer[MutAnyOrigin]:
        """Return the callback's associated data pointer.

        For a function made by `JsFunction.create_with_data`, this is that
        closure data. For a callback registered through `ModuleBuilder` or
        `ClassBuilder`, it is the cached bindings pointer — which is what
        `get_bindings` reads.

        Exists as a Bindings overload and an env-only overload; prefer the
        Bindings form outside finalizer/TSFN/except contexts.

        Args:
            b: Cached N-API bindings (Bindings overload only).
            env: The N-API environment.
            info: The callback info handle.

        Returns:
            The data pointer.

        Raises:
            If napi_get_cb_info does not return napi_ok.
        """
        var argc: UInt = 0
        var data = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        check_status(
            raw_get_cb_info(
                b,
                env,
                info,
                Pointer(to=argc).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                null,
                null,
                Pointer(to=data).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        pin_across_ffi(argc)  # ignored output slot — see get_this
        return data

    ## get_bindings — retrieve the NapiBindings pointer from callback data
    ##
    ## Every callback registered via ModuleBuilder/ClassBuilder receives the
    ## bindings pointer as its napi_callback data. This method retrieves it
    ## via napi_get_cb_info (1 OwnedDLHandle + 1 dlsym per callback entry),
    ## then all subsequent framework calls use cached function pointers.
    @staticmethod
    def get_bindings(env: NapiEnv, info: NapiValue) raises -> Bindings:
        """Fetch the cached N-API bindings attached to this callback.

        The bootstrap almost every callback begins with. Prefer a fused
        `get_bindings_and_*` accessor when you also need arguments — that is one
        `napi_get_cb_info` call instead of two.

        Args:
            env: The N-API environment.
            info: The callback info handle.

        Returns:
            The cached Bindings.

        Raises:
            If the data pointer is missing or fails the magic check.
        """
        var data = CbArgs.get_data(env, info)
        return _verified_bindings(data)

    ## get_bindings_and_one — extract bindings + 1 arg in a single napi_get_cb_info call
    ##
    ## Saves one N-API round-trip vs. separate get_bindings + get_one.
    ## Uses the bootstrap (env-only) path — the data ptr retrieval must
    ## always use this path since cached bindings aren't available yet.
    @staticmethod
    def get_bindings_and_one(
        env: NapiEnv, info: NapiValue
    ) raises -> BindingsAndOne:
        """Fetch cached bindings and one argument in ONE napi_get_cb_info call.

        The preferred entry point for a callback that needs both — the
        unfused pair costs a second N-API call.

        Args:
            env: The N-API environment.
            info: The callback info handle.

        Returns:
            A BindingsAndOne.

        Raises:
            If too few arguments were supplied, the data pointer is
                missing, or napi_get_cb_info fails.
        """
        var argc: UInt = 1
        var arg0: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var data = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        check_status(
            raw_get_cb_info(
                env,
                info,
                Pointer(to=argc).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                Pointer(to=arg0).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                null,
                Pointer(to=data).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        if argc < 1:
            raise Error("expected at least 1 argument")
        return BindingsAndOne(_verified_bindings(data), arg0)

    ## get_bindings_and_two — extract bindings + 2 args in a single napi_get_cb_info call
    @staticmethod
    def get_bindings_and_two(
        env: NapiEnv, info: NapiValue
    ) raises -> BindingsAndTwo:
        """Fetch cached bindings and two arguments in ONE napi_get_cb_info call.

        The preferred entry point for a callback that needs both — the
        unfused pair costs a second N-API call.

        Args:
            env: The N-API environment.
            info: The callback info handle.

        Returns:
            A BindingsAndTwo.

        Raises:
            If too few arguments were supplied, the data pointer is
                missing, or napi_get_cb_info fails.
        """
        var argc: UInt = 2
        var args = Array[NapiValue, 2](fill=NapiValue(unsafe_from_address=Int(0)))
        var data = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        check_status(
            raw_get_cb_info(
                env,
                info,
                Pointer(to=argc).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                Pointer(to=args[0]).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                null,
                Pointer(to=data).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        if argc < 2:
            raise Error("expected at least 2 arguments")
        return BindingsAndTwo(_verified_bindings(data), args[0], args[1])

    ## get_bindings_and_three — extract bindings + 3 args in a single napi_get_cb_info call
    @staticmethod
    def get_bindings_and_three(
        env: NapiEnv, info: NapiValue
    ) raises -> BindingsAndThree:
        """Fetch cached bindings and three arguments in ONE napi_get_cb_info call.

        The preferred entry point for a callback that needs both — the
        unfused pair costs a second N-API call.

        Args:
            env: The N-API environment.
            info: The callback info handle.

        Returns:
            A BindingsAndThree.

        Raises:
            If too few arguments were supplied, the data pointer is
                missing, or napi_get_cb_info fails.
        """
        var argc: UInt = 3
        var args = Array[NapiValue, 3](fill=NapiValue(unsafe_from_address=Int(0)))
        var data = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        check_status(
            raw_get_cb_info(
                env,
                info,
                Pointer(to=argc).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                Pointer(to=args[0]).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                null,
                Pointer(to=data).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        if argc < 3:
            raise Error("expected at least 3 arguments")
        return BindingsAndThree(
            _verified_bindings(data), args[0], args[1], args[2]
        )

    ## get_bindings_and_this — extract bindings + this value in a single napi_get_cb_info call
    ##
    ## Saves one N-API round-trip vs. separate get_bindings + unwrap_native[T](b, env, info)
    ## (the latter calls get_this internally). Use for zero-argument class method/getter
    ## callbacks. Pass the returned this_val to unwrap_native_from_this[T](b, env, this_val).
    @staticmethod
    def get_bindings_and_this(
        env: NapiEnv, info: NapiValue
    ) raises -> BindingsAndThis:
        """Fetch cached bindings and the receiver in ONE napi_get_cb_info call.

        The preferred entry point for a callback that needs both — the
        unfused pair costs a second N-API call.

        Args:
            env: The N-API environment.
            info: The callback info handle.

        Returns:
            A BindingsAndThis.

        Raises:
            If too few arguments were supplied, the data pointer is
                missing, or napi_get_cb_info fails.
        """
        var argc: UInt = 0
        var this_val: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var data = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        check_status(
            raw_get_cb_info(
                env,
                info,
                Pointer(to=argc).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                null,
                Pointer(to=this_val).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                Pointer(to=data).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        pin_across_ffi(argc)  # ignored output slot — see get_this
        return BindingsAndThis(_verified_bindings(data), this_val)

    ## get_bindings_this_and_one — extract bindings + this + 1 arg in a single napi_get_cb_info call
    ##
    ## For one-argument class method/setter callbacks. Replaces the triple call:
    ##   get_bindings + get_one(b,...) + get_this inside unwrap_native.
    ## Pass this_val to unwrap_native_from_this[T](b, env, this_val).
    @staticmethod
    def get_bindings_this_and_one(
        env: NapiEnv, info: NapiValue
    ) raises -> BindingsThisAndOne:
        """Fetch cached bindings and the receiver and one argument in ONE napi_get_cb_info call.

        The preferred entry point for a callback that needs both — the
        unfused pair costs a second N-API call.

        Args:
            env: The N-API environment.
            info: The callback info handle.

        Returns:
            A BindingsThisAndOne.

        Raises:
            If too few arguments were supplied, the data pointer is
                missing, or napi_get_cb_info fails.
        """
        var argc: UInt = 1
        var arg0: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var this_val: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var data = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        check_status(
            raw_get_cb_info(
                env,
                info,
                Pointer(to=argc).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                Pointer(to=arg0).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                Pointer(to=this_val).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                Pointer(to=data).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        if argc < 1:
            raise Error("expected at least 1 argument")
        return BindingsThisAndOne(_verified_bindings(data), this_val, arg0)
