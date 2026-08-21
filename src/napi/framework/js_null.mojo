"""Ergonomic wrapper for the JavaScript `null` value.

`JsNull` wraps `napi_get_null`, which returns the pre-existing null singleton:

```mojo
var null_val = JsNull.create(b, env)
return null_val.value
```

JavaScript `null` is a singleton, so `napi_get_null` returns the same
`napi_value` every time within a given `napi_env`. Note that `null` and
`undefined` are distinct values in JavaScript — see `js_undefined` for the
other one; returning the wrong one is visible to callers through `===`.
"""

from napi.types import NapiEnv, NapiValue
from napi.raw import raw_get_null
from napi.error import check_status
from napi.bindings import Bindings


struct JsNull:
    """Typed wrapper for the JavaScript `null` napi_value."""

    var value: NapiValue
    """The underlying napi_value handle (the null singleton)."""

    def __init__(out self, value: NapiValue):
        """Wrap an existing napi_value known to be JavaScript `null`.

        This does not validate the handle. Prefer `create` unless you already
        hold a null from N-API.

        Args:
            value: The napi_value to wrap.
        """
        self.value = value

    @staticmethod
    def create(b: Bindings, env: NapiEnv) raises -> JsNull:
        """Return the JavaScript `null` singleton.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.

        Returns:
            A JsNull wrapping the environment's null singleton.

        Raises:
            If napi_get_null does not return napi_ok.
        """
        var result: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=result
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var status = raw_get_null(b, env, result_ptr)
        check_status(status)
        return JsNull(result)
