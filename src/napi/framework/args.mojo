## src/napi/framework/args.mojo — callback argument extraction helpers
##
## CbArgs centralizes the boilerplate of calling napi_get_cb_info and
## validating argc, so that napi_callback implementations don't repeat
## the same InlineArray/pointer/check_status dance.
##
## Usage (preferred — bindings-aware, single napi_get_cb_info call):
##   var a   = CbArgs.get_bindings_and_one(env, info)   # a.b=bindings, a.arg0=value
##   var ab  = CbArgs.get_bindings_and_two(env, info)   # ab.b, ab.arg0, ab.arg1
##
## Or retrieve bindings first, then args:
##   var _b  = CbArgs.get_bindings(env, info)
##   var arg = CbArgs.get_one(_b, env, info)             # raises if argc < 1
##
## No-bindings overloads — get_one(env, info) etc. — are kept for
## standalone addons that use ModuleBuilder(env, exports) without NapiBindings.

from napi.types import NapiEnv, NapiValue
from napi.raw import raw_get_cb_info
from napi.error import check_status
from napi.bindings import NapiBindings, Bindings


## BindingsAndOne — bindings pointer + one argument (single napi_get_cb_info call)
struct BindingsAndOne:
    var b: Bindings
    var arg0: NapiValue

    fn __init__(out self, b: Bindings, arg0: NapiValue):
        self.b = b
        self.arg0 = arg0

## BindingsAndTwo — bindings pointer + two arguments (single napi_get_cb_info call)
struct BindingsAndTwo:
    var b: Bindings
    var arg0: NapiValue
    var arg1: NapiValue

    fn __init__(out self, b: Bindings, arg0: NapiValue, arg1: NapiValue):
        self.b = b
        self.arg0 = arg0
        self.arg1 = arg1

## BindingsAndThree — bindings pointer + three arguments (single napi_get_cb_info call)
struct BindingsAndThree:
    var b: Bindings
    var arg0: NapiValue
    var arg1: NapiValue
    var arg2: NapiValue

    fn __init__(out self, b: Bindings, arg0: NapiValue, arg1: NapiValue, arg2: NapiValue):
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

    fn __init__(out self, b: Bindings, this_val: NapiValue):
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

    fn __init__(out self, b: Bindings, this_val: NapiValue, arg0: NapiValue):
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
    fn get_one(env: NapiEnv, info: NapiValue) raises -> NapiValue:
        var argc: UInt = 1
        var arg0: NapiValue = NapiValue()
        var null = OpaquePointer[MutAnyOrigin]()
        check_status(raw_get_cb_info(
            env, info,
            UnsafePointer(to=argc).bitcast[NoneType](),
            UnsafePointer(to=arg0).bitcast[NoneType](),
            null, null,
        ))
        if argc < 1:
            raise Error("expected at least 1 argument")
        return arg0

    @staticmethod
    fn get_one(b: Bindings, env: NapiEnv, info: NapiValue) raises -> NapiValue:
        var argc: UInt = 1
        var arg0: NapiValue = NapiValue()
        var null = OpaquePointer[MutAnyOrigin]()
        check_status(raw_get_cb_info(
            b, env, info,
            UnsafePointer(to=argc).bitcast[NoneType](),
            UnsafePointer(to=arg0).bitcast[NoneType](),
            null, null,
        ))
        if argc < 1:
            raise Error("expected at least 1 argument")
        return arg0

    ## get_two — extract exactly two callback arguments
    ##
    ## Calls napi_get_cb_info requesting 2 arguments via an
    ## InlineArray[NapiValue, 2] argv buffer. Raises if the caller
    ## provided fewer than 2 arguments.
    @staticmethod
    fn get_two(env: NapiEnv, info: NapiValue) raises -> InlineArray[NapiValue, 2]:
        var argc: UInt = 2
        var args = InlineArray[NapiValue, 2](fill=NapiValue())
        var null = OpaquePointer[MutAnyOrigin]()
        check_status(raw_get_cb_info(
            env, info,
            UnsafePointer(to=argc).bitcast[NoneType](),
            UnsafePointer(to=args[0]).bitcast[NoneType](),
            null, null,
        ))
        if argc < 2:
            raise Error("expected at least 2 arguments")
        return args^

    @staticmethod
    fn get_two(b: Bindings, env: NapiEnv, info: NapiValue) raises -> InlineArray[NapiValue, 2]:
        var argc: UInt = 2
        var args = InlineArray[NapiValue, 2](fill=NapiValue())
        var null = OpaquePointer[MutAnyOrigin]()
        check_status(raw_get_cb_info(
            b, env, info,
            UnsafePointer(to=argc).bitcast[NoneType](),
            UnsafePointer(to=args[0]).bitcast[NoneType](),
            null, null,
        ))
        if argc < 2:
            raise Error("expected at least 2 arguments")
        return args^

    ## get_three — extract exactly three callback arguments
    @staticmethod
    fn get_three(b: Bindings, env: NapiEnv, info: NapiValue) raises -> InlineArray[NapiValue, 3]:
        var argc: UInt = 3
        var args = InlineArray[NapiValue, 3](fill=NapiValue())
        var null = OpaquePointer[MutAnyOrigin]()
        check_status(raw_get_cb_info(
            b, env, info,
            UnsafePointer(to=argc).bitcast[NoneType](),
            UnsafePointer(to=args[0]).bitcast[NoneType](),
            null, null,
        ))
        if argc < 3:
            raise Error("expected at least 3 arguments")
        return args^

    ## get_four — extract exactly four callback arguments
    @staticmethod
    fn get_four(b: Bindings, env: NapiEnv, info: NapiValue) raises -> InlineArray[NapiValue, 4]:
        var argc: UInt = 4
        var args = InlineArray[NapiValue, 4](fill=NapiValue())
        var null = OpaquePointer[MutAnyOrigin]()
        check_status(raw_get_cb_info(
            b, env, info,
            UnsafePointer(to=argc).bitcast[NoneType](),
            UnsafePointer(to=args[0]).bitcast[NoneType](),
            null, null,
        ))
        if argc < 4:
            raise Error("expected at least 4 arguments")
        return args^

    ## get_this — extract the `this` value from a callback
    ##
    ## Used by class method/getter/setter callbacks to get the JS instance.
    @staticmethod
    fn get_this(env: NapiEnv, info: NapiValue) raises -> NapiValue:
        var argc: UInt = 0
        var this_val: NapiValue = NapiValue()
        var null = OpaquePointer[MutAnyOrigin]()
        check_status(raw_get_cb_info(
            env, info,
            UnsafePointer(to=argc).bitcast[NoneType](),
            null,
            UnsafePointer(to=this_val).bitcast[NoneType](),
            null,
        ))
        return this_val

    @staticmethod
    fn get_this(b: Bindings, env: NapiEnv, info: NapiValue) raises -> NapiValue:
        var argc: UInt = 0
        var this_val: NapiValue = NapiValue()
        var null = OpaquePointer[MutAnyOrigin]()
        check_status(raw_get_cb_info(
            b, env, info,
            UnsafePointer(to=argc).bitcast[NoneType](),
            null,
            UnsafePointer(to=this_val).bitcast[NoneType](),
            null,
        ))
        return this_val

    ## get_this_and_one — extract `this` plus one argument
    ##
    ## Returns [this, arg0] in an InlineArray[NapiValue, 2].
    @staticmethod
    fn get_this_and_one(env: NapiEnv, info: NapiValue) raises -> InlineArray[NapiValue, 2]:
        var argc: UInt = 1
        var arg0: NapiValue = NapiValue()
        var this_val: NapiValue = NapiValue()
        var null = OpaquePointer[MutAnyOrigin]()
        check_status(raw_get_cb_info(
            env, info,
            UnsafePointer(to=argc).bitcast[NoneType](),
            UnsafePointer(to=arg0).bitcast[NoneType](),
            UnsafePointer(to=this_val).bitcast[NoneType](),
            null,
        ))
        if argc < 1:
            raise Error("expected at least 1 argument")
        var result = InlineArray[NapiValue, 2](fill=NapiValue())
        result[0] = this_val
        result[1] = arg0
        return result^

    @staticmethod
    fn get_this_and_one(b: Bindings, env: NapiEnv, info: NapiValue) raises -> InlineArray[NapiValue, 2]:
        var argc: UInt = 1
        var arg0: NapiValue = NapiValue()
        var this_val: NapiValue = NapiValue()
        var null = OpaquePointer[MutAnyOrigin]()
        check_status(raw_get_cb_info(
            b, env, info,
            UnsafePointer(to=argc).bitcast[NoneType](),
            UnsafePointer(to=arg0).bitcast[NoneType](),
            UnsafePointer(to=this_val).bitcast[NoneType](),
            null,
        ))
        if argc < 1:
            raise Error("expected at least 1 argument")
        var result = InlineArray[NapiValue, 2](fill=NapiValue())
        result[0] = this_val
        result[1] = arg0
        return result^

    ## argc — query the number of arguments without reading any
    @staticmethod
    fn argc(env: NapiEnv, info: NapiValue) raises -> UInt:
        var count: UInt = 0
        var null = OpaquePointer[MutAnyOrigin]()
        check_status(raw_get_cb_info(
            env, info,
            UnsafePointer(to=count).bitcast[NoneType](),
            null, null, null,
        ))
        return count

    @staticmethod
    fn argc(b: Bindings, env: NapiEnv, info: NapiValue) raises -> UInt:
        var count: UInt = 0
        var null = OpaquePointer[MutAnyOrigin]()
        check_status(raw_get_cb_info(
            b, env, info,
            UnsafePointer(to=count).bitcast[NoneType](),
            null, null, null,
        ))
        return count

    ## get_argv — read `count` arguments into a caller-provided buffer
    @staticmethod
    fn get_argv(env: NapiEnv, info: NapiValue, count: UInt,
                argv_ptr: UnsafePointer[NapiValue, MutAnyOrigin]) raises:
        var actual = count
        var null = OpaquePointer[MutAnyOrigin]()
        check_status(raw_get_cb_info(
            env, info,
            UnsafePointer(to=actual).bitcast[NoneType](),
            argv_ptr.bitcast[NoneType](),
            null, null,
        ))

    @staticmethod
    fn get_argv(b: Bindings, env: NapiEnv, info: NapiValue, count: UInt,
                argv_ptr: UnsafePointer[NapiValue, MutAnyOrigin]) raises:
        var actual = count
        var null = OpaquePointer[MutAnyOrigin]()
        check_status(raw_get_cb_info(
            b, env, info,
            UnsafePointer(to=actual).bitcast[NoneType](),
            argv_ptr.bitcast[NoneType](),
            null, null,
        ))

    ## get_data — extract the data pointer from a callback
    ##
    ## Used by dynamically-created functions (napi_create_function with data).
    @staticmethod
    fn get_data(env: NapiEnv, info: NapiValue) raises -> OpaquePointer[MutAnyOrigin]:
        var argc: UInt = 0
        var data = OpaquePointer[MutAnyOrigin]()
        var null = OpaquePointer[MutAnyOrigin]()
        check_status(raw_get_cb_info(
            env, info,
            UnsafePointer(to=argc).bitcast[NoneType](),
            null, null,
            UnsafePointer(to=data).bitcast[NoneType](),
        ))
        return data

    @staticmethod
    fn get_data(b: Bindings, env: NapiEnv, info: NapiValue) raises -> OpaquePointer[MutAnyOrigin]:
        var argc: UInt = 0
        var data = OpaquePointer[MutAnyOrigin]()
        var null = OpaquePointer[MutAnyOrigin]()
        check_status(raw_get_cb_info(
            b, env, info,
            UnsafePointer(to=argc).bitcast[NoneType](),
            null, null,
            UnsafePointer(to=data).bitcast[NoneType](),
        ))
        return data

    ## get_bindings — retrieve the NapiBindings pointer from callback data
    ##
    ## Every callback registered via ModuleBuilder/ClassBuilder receives the
    ## bindings pointer as its napi_callback data. This method retrieves it
    ## via napi_get_cb_info (1 OwnedDLHandle + 1 dlsym per callback entry),
    ## then all subsequent framework calls use cached function pointers.
    @staticmethod
    fn get_bindings(env: NapiEnv, info: NapiValue) raises -> Bindings:
        var data = CbArgs.get_data(env, info)
        return data.bitcast[NapiBindings]()

    ## get_bindings_and_one — extract bindings + 1 arg in a single napi_get_cb_info call
    ##
    ## Saves one N-API round-trip vs. separate get_bindings + get_one.
    ## Uses the bootstrap (env-only) path — the data ptr retrieval must
    ## always use this path since cached bindings aren't available yet.
    @staticmethod
    fn get_bindings_and_one(env: NapiEnv, info: NapiValue) raises -> BindingsAndOne:
        var argc: UInt = 1
        var arg0: NapiValue = NapiValue()
        var data = OpaquePointer[MutAnyOrigin]()
        var null = OpaquePointer[MutAnyOrigin]()
        check_status(raw_get_cb_info(
            env, info,
            UnsafePointer(to=argc).bitcast[NoneType](),
            UnsafePointer(to=arg0).bitcast[NoneType](),
            null,
            UnsafePointer(to=data).bitcast[NoneType](),
        ))
        if argc < 1:
            raise Error("expected at least 1 argument")
        return BindingsAndOne(data.bitcast[NapiBindings](), arg0)

    ## get_bindings_and_two — extract bindings + 2 args in a single napi_get_cb_info call
    @staticmethod
    fn get_bindings_and_two(env: NapiEnv, info: NapiValue) raises -> BindingsAndTwo:
        var argc: UInt = 2
        var args = InlineArray[NapiValue, 2](fill=NapiValue())
        var data = OpaquePointer[MutAnyOrigin]()
        var null = OpaquePointer[MutAnyOrigin]()
        check_status(raw_get_cb_info(
            env, info,
            UnsafePointer(to=argc).bitcast[NoneType](),
            UnsafePointer(to=args[0]).bitcast[NoneType](),
            null,
            UnsafePointer(to=data).bitcast[NoneType](),
        ))
        if argc < 2:
            raise Error("expected at least 2 arguments")
        return BindingsAndTwo(data.bitcast[NapiBindings](), args[0], args[1])

    ## get_bindings_and_three — extract bindings + 3 args in a single napi_get_cb_info call
    @staticmethod
    fn get_bindings_and_three(env: NapiEnv, info: NapiValue) raises -> BindingsAndThree:
        var argc: UInt = 3
        var args = InlineArray[NapiValue, 3](fill=NapiValue())
        var data = OpaquePointer[MutAnyOrigin]()
        var null = OpaquePointer[MutAnyOrigin]()
        check_status(raw_get_cb_info(
            env, info,
            UnsafePointer(to=argc).bitcast[NoneType](),
            UnsafePointer(to=args[0]).bitcast[NoneType](),
            null,
            UnsafePointer(to=data).bitcast[NoneType](),
        ))
        if argc < 3:
            raise Error("expected at least 3 arguments")
        return BindingsAndThree(data.bitcast[NapiBindings](), args[0], args[1], args[2])

    ## get_bindings_and_this — extract bindings + this value in a single napi_get_cb_info call
    ##
    ## Saves one N-API round-trip vs. separate get_bindings + unwrap_native[T](b, env, info)
    ## (the latter calls get_this internally). Use for zero-argument class method/getter
    ## callbacks. Pass the returned this_val to unwrap_native_from_this[T](b, env, this_val).
    @staticmethod
    fn get_bindings_and_this(env: NapiEnv, info: NapiValue) raises -> BindingsAndThis:
        var argc: UInt = 0
        var this_val: NapiValue = NapiValue()
        var data = OpaquePointer[MutAnyOrigin]()
        var null = OpaquePointer[MutAnyOrigin]()
        check_status(raw_get_cb_info(
            env, info,
            UnsafePointer(to=argc).bitcast[NoneType](),
            null,
            UnsafePointer(to=this_val).bitcast[NoneType](),
            UnsafePointer(to=data).bitcast[NoneType](),
        ))
        return BindingsAndThis(data.bitcast[NapiBindings](), this_val)

    ## get_bindings_this_and_one — extract bindings + this + 1 arg in a single napi_get_cb_info call
    ##
    ## For one-argument class method/setter callbacks. Replaces the triple call:
    ##   get_bindings + get_one(b,...) + get_this inside unwrap_native.
    ## Pass this_val to unwrap_native_from_this[T](b, env, this_val).
    @staticmethod
    fn get_bindings_this_and_one(env: NapiEnv, info: NapiValue) raises -> BindingsThisAndOne:
        var argc: UInt = 1
        var arg0: NapiValue = NapiValue()
        var this_val: NapiValue = NapiValue()
        var data = OpaquePointer[MutAnyOrigin]()
        check_status(raw_get_cb_info(
            env, info,
            UnsafePointer(to=argc).bitcast[NoneType](),
            UnsafePointer(to=arg0).bitcast[NoneType](),
            UnsafePointer(to=this_val).bitcast[NoneType](),
            UnsafePointer(to=data).bitcast[NoneType](),
        ))
        if argc < 1:
            raise Error("expected at least 1 argument")
        return BindingsThisAndOne(data.bitcast[NapiBindings](), this_val, arg0)

