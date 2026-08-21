"""Ergonomic wrapper for JavaScript number values.

```mojo
var n = JsNumber.create(b, env, 42.5)
var x = JsNumber.from_napi_value(b, env, n.value)   # 42.5
```

JavaScript has a single numeric type, IEEE 754 Float64, which is what
`create`/`from_napi_value` use. `create_int`/`to_int` are the Int-typed
convenience pair over the same JS type — they go through
`napi_create_int64`/`napi_get_value_int64`, so integers beyond 2**53 - 1
lose precision. Reach for `JsBigInt` when you need exact 64-bit values,
or `JsInt32`/`JsUInt32` when you want the wrapping ToInt32/ToUint32
conversions.
"""


from napi.types import NapiEnv, NapiValue
from napi.raw import (
    raw_create_double,
    raw_get_value_double,
    raw_create_int64,
    raw_get_value_int64,
)
from napi.error import check_status
from napi.bindings import Bindings


## JsNumber — typed wrapper for a JavaScript number napi_value
struct JsNumber:
    """Typed wrapper for a JavaScript number napi_value.
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
    def create(b: Bindings, env: NapiEnv, n: Float64) raises -> JsNumber:
        """Create a JS number from a Mojo Float64.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            n: The value to represent.

        Returns:
            A JsNumber wrapping the new napi_value.

        Raises:
            If napi_create_double does not return napi_ok.
        """
        var result: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=result
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var status = raw_create_double(b, env, n, result_ptr)
        check_status(status)
        return JsNumber(result)

    @staticmethod
    def from_napi_value(
        b: Bindings, env: NapiEnv, val: NapiValue
    ) raises -> Float64:
        """Read a napi_value as a Mojo Float64.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            val: A napi_value holding a JS number.

        Returns:
            The Float64 value.

        Raises:
            `napi_number_expected` if val is not a number.
        """
        var n: Float64 = 0.0
        var n_ptr: OpaquePointer[MutAnyOrigin] = Pointer(to=n).unsafe_bitcast[
            NoneType
        ]().as_unsafe_any_origin()
        var status = raw_get_value_double(b, env, val, n_ptr)
        check_status(status)
        return n

    @staticmethod
    def create_int(b: Bindings, env: NapiEnv, n: Int) raises -> JsNumber:
        """Create a JS number from a Mojo Int.

        Goes through napi_create_int64, so values beyond 2**53 - 1 lose
        precision in the resulting JS number.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            n: The value to represent.

        Returns:
            A JsNumber wrapping the new napi_value.

        Raises:
            If napi_create_int64 does not return napi_ok.
        """
        var result = NapiValue(unsafe_from_address=Int(0))
        check_status(
            raw_create_int64(
                b, env, Int64(n), Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
            )
        )
        return JsNumber(result)

    @staticmethod
    def to_int(b: Bindings, env: NapiEnv, val: NapiValue) raises -> Int:
        """Read a napi_value as a Mojo Int.

        Out-of-range doubles are clamped; NaN and the infinities give 0.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            val: A napi_value holding a JS number.

        Returns:
            The Int value.

        Raises:
            `napi_number_expected` if val is not a number.
        """
        var n: Int64 = 0
        check_status(
            raw_get_value_int64(
                b,
                env,
                val,
                Pointer(to=n).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        return Int(n)
