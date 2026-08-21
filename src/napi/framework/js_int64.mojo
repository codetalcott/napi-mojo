"""Ergonomic wrapper for JavaScript numbers read and written as `Int64`.

```mojo
var n = JsInt64.create(b, env, 9007199254740993)
```

**A JS number cannot hold every Int64 exactly.** JavaScript numbers are
Float64, so only integers up to 2**53 - 1 survive a round trip unchanged;
beyond that `create` silently loses precision. `from_napi_value` follows
`napi_get_value_int64`, which clamps out-of-range doubles and converts
NaN and the infinities to 0. When you need exact 64-bit integers across
the boundary, use `JsBigInt` instead — it is lossless by construction.
"""


from napi.types import NapiEnv, NapiValue
from napi.raw import raw_create_int64, raw_get_value_int64
from napi.error import check_status
from napi.bindings import Bindings


struct JsInt64:
    """Typed wrapper for a JavaScript number carrying an Int64 value.
    """
    var value: NapiValue
    """The underlying napi_value handle. Valid within the current handle scope.
    """

    def __init__(out self, value: NapiValue):
        """Wrap an existing napi_value of the matching JS type.

        This does not validate the handle.

        Args:
            value: The napi_value to wrap.
        """
        self.value = value

    @staticmethod
    def create(b: Bindings, env: NapiEnv, n: Int64) raises -> JsInt64:
        """Create a JS number from a Mojo Int64.

        Values beyond 2**53 - 1 lose precision, because the JS number is a
        Float64. Use `JsBigInt` when that matters.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            n: The value to represent.

        Returns:
            A JsInt64 wrapping the new napi_value.

        Raises:
            If napi_create_int64 does not return napi_ok.
        """
        var result = NapiValue(unsafe_from_address=Int(0))
        check_status(
            raw_create_int64(
                b, env, n, Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
            )
        )
        return JsInt64(result)

    @staticmethod
    def from_napi_value(
        b: Bindings, env: NapiEnv, val: NapiValue
    ) raises -> Int64:
        """Read a napi_value as a Mojo Int64.

        Out-of-range doubles are clamped; NaN and the infinities give 0.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            val: A napi_value holding a JS number.

        Returns:
            The converted Int64.

        Raises:
            `napi_number_expected` if val is not a number.
        """
        var n: Int64 = 0
        check_status(
            raw_get_value_int64(
                b, env, val, Pointer(to=n).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
            )
        )
        return n
