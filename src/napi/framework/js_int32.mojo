"""Ergonomic wrapper for JavaScript numbers read and written as `Int32`.

JavaScript has one numeric type (Float64), so these helpers are about how
the value is *converted* at the boundary, not about a distinct JS type:

```mojo
var n = JsInt32.create(b, env, -7)
var back = JsInt32.from_napi_value(b, env, n.value)   # -7
```

`from_napi_value` follows `napi_get_value_int32`, which does **not** raise
on out-of-range input: it applies the ECMAScript ToInt32 conversion, so
`2**31` arrives as `-2147483648` and a non-integral value is truncated
toward zero. Check the range yourself if wraparound would be a bug.
NaN and the infinities convert to 0.
"""


from napi.types import NapiEnv, NapiValue
from napi.raw import raw_create_int32, raw_get_value_int32
from napi.error import check_status
from napi.bindings import Bindings


struct JsInt32:
    """Typed wrapper for a JavaScript number carrying an Int32 value.
    """
    var value: NapiValue
    """The underlying napi_value handle. Valid within the current handle scope.
    """

    def __init__(out self, value: NapiValue):
        """Wrap an existing napi_value known to hold a number.

        Args:
            value: The napi_value to wrap.
        """
        self.value = value

    @staticmethod
    def create(b: Bindings, env: NapiEnv, n: Int32) raises -> JsInt32:
        """Create a JS number from a Mojo Int32.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            n: The value to represent.

        Returns:
            A JsInt32 wrapping the new napi_value.

        Raises:
            If napi_create_int32 does not return napi_ok.
        """
        var result = NapiValue(unsafe_from_address=Int(0))
        check_status(
            raw_create_int32(
                b, env, n, Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
            )
        )
        return JsInt32(result)

    @staticmethod
    def from_napi_value(
        b: Bindings, env: NapiEnv, val: NapiValue
    ) raises -> Int32:
        """Read a napi_value as a Mojo Int32.

        Applies the ECMAScript ToInt32 conversion — out-of-range values wrap
        rather than raising, and non-integral values truncate toward zero.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            val: A napi_value holding a JS number.

        Returns:
            The converted Int32.

        Raises:
            `napi_number_expected` if val is not a number.
        """
        var n: Int32 = 0
        check_status(
            raw_get_value_int32(
                b, env, val, Pointer(to=n).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
            )
        )
        return n
