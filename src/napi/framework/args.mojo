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
