"""Ergonomic wrapper for JavaScript boolean values.

```mojo
var flag = JsBoolean.create(b, env, True)
var back = JsBoolean.from_napi_value(b, env, flag.value)
```

JavaScript has `true`/`false` singletons, so `napi_get_boolean` returns a
pre-existing value rather than allocating one.

`from_napi_value` requires an actual boolean and raises otherwise — it
does not apply JavaScript truthiness. For truthiness (`""` -> False,
`0` -> False, any object -> True), use `js_coerce_to_bool`.
"""


from napi.types import NapiEnv, NapiValue
from napi.raw import raw_get_boolean, raw_get_value_bool
from napi.error import check_status
from napi.bindings import Bindings


## JsBoolean — typed wrapper for a JavaScript boolean napi_value
struct JsBoolean:
    """Typed wrapper for a JavaScript boolean napi_value.
    """
    ## The underlying napi_value handle. Valid within the current handle scope.
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
    def create(b: Bindings, env: NapiEnv, bval: Bool) raises -> JsBoolean:
        """Create a JS boolean from a Mojo Bool.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            bval: The value to represent.

        Returns:
            A JsBoolean wrapping the JS true/false singleton.

        Raises:
            If napi_get_boolean does not return napi_ok.
        """
        var result: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=result
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var status = raw_get_boolean(b, env, bval, result_ptr)
        check_status(status)
        return JsBoolean(result)

    @staticmethod
    def from_napi_value(
        b: Bindings, env: NapiEnv, val: NapiValue
    ) raises -> Bool:
        """Read a napi_value as a Mojo Bool.

        Requires an actual JS boolean; this is not a truthiness test.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            val: A napi_value holding a JS boolean.

        Returns:
            The Mojo Bool.

        Raises:
            `napi_boolean_expected` if val is not a boolean.
        """
        var bval: Bool = False
        var b_ptr: OpaquePointer[MutAnyOrigin] = Pointer(to=bval).unsafe_bitcast[
            NoneType
        ]().as_unsafe_any_origin()
        var status = raw_get_value_bool(b, env, val, b_ptr)
        check_status(status)
        return bval
