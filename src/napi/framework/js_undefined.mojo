"""Ergonomic wrapper for the JavaScript `undefined` value.

```mojo
var undef = JsUndefined.create(b, env)
return undef.value
```

`undefined` is a singleton, so `napi_get_undefined` returns the same
`napi_value` every time within a given `napi_env`.

This is the right value to return from a callback that has nothing to
return. It is **not** interchangeable with a null napi_value handle: a
null handle returned with no pending exception is what makes a failed
callback look like a successful one that produced `undefined`. Return
this explicitly when you mean it, and throw when you do not.
"""


from napi.types import NapiEnv, NapiValue
from napi.raw import raw_get_undefined
from napi.error import check_status
from napi.bindings import Bindings


## JsUndefined — typed wrapper for the JavaScript undefined napi_value
struct JsUndefined:
    """Typed wrapper for the JavaScript `undefined` napi_value.
    """
    ## The underlying napi_value handle (the undefined singleton).
    var value: NapiValue
    """The underlying napi_value handle (the undefined singleton).
    """

    def __init__(out self, value: NapiValue):
        """Wrap an existing napi_value of the matching JS type.

        This does not validate the handle.

        Args:
            value: The napi_value to wrap.
        """
        self.value = value

    @staticmethod
    def create(b: Bindings, env: NapiEnv) raises -> JsUndefined:
        """Return the JavaScript `undefined` singleton.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.

        Returns:
            A JsUndefined wrapping the environment's undefined singleton.

        Raises:
            If napi_get_undefined does not return napi_ok.
        """
        var result: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=result
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var status = raw_get_undefined(b, env, result_ptr)
        check_status(status)
        return JsUndefined(result)
