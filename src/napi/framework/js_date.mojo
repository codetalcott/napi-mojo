## src/napi/framework/js_date.mojo — Date wrapper
##
## JsDate wraps creation and reading of JavaScript Date objects.
##
## Usage:
##   var d = JsDate.create(env, 1709424000000.0)
##   var ts = d.timestamp_ms(env)
##   var is_d = JsDate.is_date(env, some_value)

from napi.types import NapiEnv, NapiValue
from napi.raw import raw_create_date, raw_get_date_value, raw_is_date
from napi.error import check_status

struct JsDate:
    var value: NapiValue

    fn __init__(out self, value: NapiValue):
        self.value = value

    @staticmethod
    fn create(env: NapiEnv, timestamp_ms: Float64) raises -> JsDate:
        var result = NapiValue()
        check_status(raw_create_date(env, timestamp_ms,
            UnsafePointer(to=result).bitcast[NoneType]()))
        return JsDate(result)

    fn timestamp_ms(self, env: NapiEnv) raises -> Float64:
        var result: Float64 = 0.0
        check_status(raw_get_date_value(env, self.value,
            UnsafePointer(to=result).bitcast[NoneType]()))
        return result

    @staticmethod
    fn is_date(env: NapiEnv, val: NapiValue) raises -> Bool:
        var result: Bool = False
        check_status(raw_is_date(env, val,
            UnsafePointer(to=result).bitcast[NoneType]()))
        return result
