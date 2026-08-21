"""Ergonomic wrapper for JavaScript numbers read and written as `UInt32`.

```mojo
var n = JsUInt32.create(b, env, 0xDEADBEEF)
var back = JsUInt32.from_napi_value(b, env, n.value)
```

`from_napi_value` follows `napi_get_value_uint32`, which applies the
ECMAScript ToUint32 conversion rather than raising: negatives wrap into
the unsigned range (`-1` arrives as `4294967295`), non-integral values
truncate toward zero, and NaN and the infinities convert to 0. Use this
for bitmask-style values; use `JsNumber` when you want the exact double.
"""


from napi.types import NapiEnv, NapiValue
from napi.raw import raw_create_uint32, raw_get_value_uint32
from napi.error import check_status
from napi.bindings import Bindings


struct JsUInt32:
    """Typed wrapper for a JavaScript number carrying a UInt32 value.
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
    def create(b: Bindings, env: NapiEnv, n: UInt32) raises -> JsUInt32:
        """Create a JS number from a Mojo UInt32.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            n: The value to represent.

        Returns:
            A JsUInt32 wrapping the new napi_value.

        Raises:
            If napi_create_uint32 does not return napi_ok.
        """
        var result = NapiValue(unsafe_from_address=Int(0))
        check_status(
            raw_create_uint32(
                b, env, n, Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
            )
        )
        return JsUInt32(result)

    @staticmethod
    def from_napi_value(
        b: Bindings, env: NapiEnv, val: NapiValue
    ) raises -> UInt32:
        """Read a napi_value as a Mojo UInt32.

        Applies the ECMAScript ToUint32 conversion — negatives and
        out-of-range values wrap rather than raising.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            val: A napi_value holding a JS number.

        Returns:
            The converted UInt32.

        Raises:
            `napi_number_expected` if val is not a number.
        """
        var n: UInt32 = 0
        check_status(
            raw_get_value_uint32(
                b, env, val, Pointer(to=n).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
            )
        )
        return n
