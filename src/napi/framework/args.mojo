## src/napi/framework/args.mojo — callback argument extraction helpers
##
## CbArgs centralizes the boilerplate of calling napi_get_cb_info and
## validating argc, so that napi_callback implementations don't repeat
## the same InlineArray/pointer/check_status dance.
##
## Usage:
##   var arg = CbArgs.get_one(env, info)        # raises if argc < 1
##   var args = CbArgs.get_two(env, info)        # raises if argc < 2
##   var a = JsNumber.from_napi_value(env, args[0])

from napi.types import NapiEnv, NapiValue
from napi.raw import raw_get_cb_info
from napi.error import check_status
from napi.bindings import Bindings

## CbArgs — typed helpers for extracting napi_callback arguments
struct CbArgs:

    ## get_one — extract exactly one callback argument
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
