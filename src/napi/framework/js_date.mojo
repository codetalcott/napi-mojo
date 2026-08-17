## src/napi/framework/js_date.mojo — Date wrapper
##
## JsDate wraps creation and reading of JavaScript Date objects.
##
## Usage:
##   var d = JsDate.create(env, 1709424000000.0)
##   var ts = d.timestamp_ms(env)
##   var is_d = JsDate.is_date(env, some_value)

from napi.types import NapiEnv, NapiValue
from napi.bindings import Bindings
from napi.raw import raw_create_date, raw_get_date_value, raw_is_date
from napi.error import check_status


struct JsDate:
    @__allow_legacy_any_origin_fields
    var value: NapiValue

    def __init__(out self, value: NapiValue):
        self.value = value

    # --- Bindings-aware overloads ---

    @staticmethod
    def create(
        b: Bindings, env: NapiEnv, timestamp_ms: Float64
    ) raises -> JsDate:
        var result = NapiValue(unsafe_from_address=Int(0))
        check_status(
            raw_create_date(
                b,
                env,
                timestamp_ms,
                Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        return JsDate(result)

    def timestamp_ms(self, b: Bindings, env: NapiEnv) raises -> Float64:
        var result: Float64 = 0.0
        check_status(
            raw_get_date_value(
                b, env, self.value, Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
            )
        )
        return result

    @staticmethod
    def is_date(b: Bindings, env: NapiEnv, val: NapiValue) raises -> Bool:
        var result: Bool = False
        check_status(
            raw_is_date(
                b,
                env,
                val,
                Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        return result
