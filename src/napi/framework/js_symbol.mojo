## src/napi/framework/js_symbol.mojo — Symbol wrapper
##
## JsSymbol wraps creation of JavaScript Symbol values.
##
## Usage:
##   var s = JsSymbol.create(env, desc_napi_value)
##   var s2 = JsSymbol.create_for(env, "myKey")

from napi.types import NapiEnv, NapiValue
from napi.bindings import Bindings
from napi.raw import raw_create_symbol, raw_symbol_for
from napi.error import check_status

struct JsSymbol:
    var value: NapiValue

    fn __init__(out self, value: NapiValue):
        self.value = value

    ## create — create a new unique Symbol with the given description
    @staticmethod
    fn create(env: NapiEnv, description: NapiValue) raises -> JsSymbol:
        var result = NapiValue()
        check_status(raw_create_symbol(env, description,
            UnsafePointer(to=result).bitcast[NoneType]()))
        return JsSymbol(result)

    ## create_for — return the global Symbol for the given key (Symbol.for())
    @staticmethod
    fn create_for(env: NapiEnv, key: StringLiteral) raises -> JsSymbol:
        var result = NapiValue()
        check_status(raw_symbol_for(env,
            key.unsafe_ptr().bitcast[NoneType](),
            UInt(len(key)),
            UnsafePointer(to=result).bitcast[NoneType]()))
        return JsSymbol(result)

    # --- Bindings-aware overloads ---

    @staticmethod
    fn create(b: Bindings, env: NapiEnv, description: NapiValue) raises -> JsSymbol:
        var result = NapiValue()
        check_status(raw_create_symbol(b, env, description,
            UnsafePointer(to=result).bitcast[NoneType]()))
        return JsSymbol(result)

    @staticmethod
    fn create_for(b: Bindings, env: NapiEnv, key: StringLiteral) raises -> JsSymbol:
        var result = NapiValue()
        check_status(raw_symbol_for(b, env,
            key.unsafe_ptr().bitcast[NoneType](),
            UInt(len(key)),
            UnsafePointer(to=result).bitcast[NoneType]()))
        return JsSymbol(result)
