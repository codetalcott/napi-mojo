## src/napi/framework/args.mojo — callback argument extraction helpers
##
## CbArgs centralizes the boilerplate of calling napi_get_cb_info and
## validating argc, so that napi_callback implementations don't repeat
## the same Array/pointer/check_status dance.
##
## Usage (preferred — bindings-aware, single napi_get_cb_info call):
##   var a   = CbArgs.get_bindings_and_one(env, info)   # a.b=bindings, a.arg0=value
##   var ab  = CbArgs.get_bindings_and_two(env, info)   # ab.b, ab.arg0, ab.arg1
##
## Or retrieve bindings first, then args:
##   var _b  = CbArgs.get_bindings(env, info)
##   var arg = CbArgs.get_one(_b, env, info)             # raises if argc < 1
##
## This file is (with error.mojo) the surviving env-only surface: every
## method here bottoms out in the ONE kept per-call-dlsym symbol,
## napi_get_cb_info — the bootstrap that runs before bindings are available.
## The env-only get_one/get_two/... overloads cost nothing extra to keep and
## serve callbacks that only need raw argv without touching other N-API.

from napi.types import NapiEnv, NapiValue
from napi.raw import raw_get_cb_info
from napi.error import check_status
from napi.bindings import NapiBindings, Bindings, BINDINGS_MAGIC


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
##     bindings pointer as the TSFN context, which N-API hands to call_js_cb
##     as its `context` parameter.
##   - TSFN finalize_cb: N-API passes the same context as `finalize_hint`.
##   - wrap_native finalizers: the bindings pointer is the finalize_hint.
## Verifies the BINDINGS_MAGIC sentinel and raises if the pointer is null or
## not a NapiBindings — check Int(ptr) first in teardown paths where a null
## is expected and the call should be silently dropped.
def bindings_from_context(
    context: OpaquePointer[MutAnyOrigin],
) raises -> Bindings:
    return _verified_bindings(context)


## BindingsAndOne — bindings pointer + one argument (single napi_get_cb_info call)
struct BindingsAndOne:
    var b: Bindings
    var arg0: NapiValue

    def __init__(out self, b: Bindings, arg0: NapiValue):
        self.b = b
        self.arg0 = arg0


## BindingsAndTwo — bindings pointer + two arguments (single napi_get_cb_info call)
struct BindingsAndTwo:
    var b: Bindings
    var arg0: NapiValue
    var arg1: NapiValue

    def __init__(out self, b: Bindings, arg0: NapiValue, arg1: NapiValue):
        self.b = b
        self.arg0 = arg0
        self.arg1 = arg1


## BindingsAndThree — bindings pointer + three arguments (single napi_get_cb_info call)
struct BindingsAndThree:
    var b: Bindings
    var arg0: NapiValue
    var arg1: NapiValue
    var arg2: NapiValue

    def __init__(
        out self, b: Bindings, arg0: NapiValue, arg1: NapiValue, arg2: NapiValue
    ):
        self.b = b
        self.arg0 = arg0
        self.arg1 = arg1
        self.arg2 = arg2


## BindingsAndThis — bindings pointer + this value (single napi_get_cb_info call)
##
## Used by zero-argument class method/getter callbacks. Pass this_val directly
## to unwrap_native_from_this[T](b, env, this_val) to skip a second get_cb_info.
struct BindingsAndThis:
    var b: Bindings
    var this_val: NapiValue

    def __init__(out self, b: Bindings, this_val: NapiValue):
        self.b = b
        self.this_val = this_val


## BindingsThisAndOne — bindings pointer + this value + one argument (single napi_get_cb_info call)
##
## Used by one-argument class method/setter callbacks. Replaces the triple call:
##   get_bindings + get_one(b,...) + get_this inside unwrap_native.
struct BindingsThisAndOne:
    var b: Bindings
    var this_val: NapiValue
    var arg0: NapiValue

    def __init__(out self, b: Bindings, this_val: NapiValue, arg0: NapiValue):
        self.b = b
        self.this_val = this_val
        self.arg0 = arg0


## CbArgs — typed helpers for extracting napi_callback arguments
struct CbArgs:
    ## get_one — extract exactly one callback argument (env-only)
    ##
    ## env-only: for async complete, TSFN, finalizer, and except-block callbacks
    ## where NapiBindings is unavailable. Use the bindings overload in hot paths.
    ##
    ## Calls napi_get_cb_info requesting 1 argument. Raises if the caller
    ## provided fewer than 1 argument.
    @staticmethod
    def get_one(env: NapiEnv, info: NapiValue) raises -> NapiValue:
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
        return this_val

    @staticmethod
    def get_this(
        b: Bindings, env: NapiEnv, info: NapiValue
    ) raises -> NapiValue:
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
        return this_val

    ## get_this_and_one — extract `this` plus one argument
    ##
    ## Returns [this, arg0] in an Array[NapiValue, 2].
    @staticmethod
    def get_this_and_one(
        env: NapiEnv, info: NapiValue
    ) raises -> Array[NapiValue, 2]:
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
        return data

    @staticmethod
    def get_data(
        b: Bindings, env: NapiEnv, info: NapiValue
    ) raises -> OpaquePointer[MutAnyOrigin]:
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
        return data

    ## get_bindings — retrieve the NapiBindings pointer from callback data
    ##
    ## Every callback registered via ModuleBuilder/ClassBuilder receives the
    ## bindings pointer as its napi_callback data. This method retrieves it
    ## via napi_get_cb_info (1 OwnedDLHandle + 1 dlsym per callback entry),
    ## then all subsequent framework calls use cached function pointers.
    @staticmethod
    def get_bindings(env: NapiEnv, info: NapiValue) raises -> Bindings:
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
