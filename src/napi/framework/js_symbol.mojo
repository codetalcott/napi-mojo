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

    def __init__(out self, value: NapiValue):
        self.value = value

    # --- Bindings-aware overloads ---

    @staticmethod
    def create(
        b: Bindings, env: NapiEnv, description: NapiValue
    ) raises -> JsSymbol:
        var result = NapiValue(unsafe_from_address=Int(0))
        check_status(
            raw_create_symbol(
                b,
                env,
                description,
                Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        return JsSymbol(result)

    @staticmethod
    def create_for(
        b: Bindings, env: NapiEnv, key: StringLiteral
    ) raises -> JsSymbol:
        var result = NapiValue(unsafe_from_address=Int(0))
        check_status(
            raw_symbol_for(
                b,
                env,
                key.unsafe_ptr().unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                UInt(key.byte_length()),
                Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        return JsSymbol(result)
