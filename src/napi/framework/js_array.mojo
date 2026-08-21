"""Ergonomic wrapper for JavaScript Array values.

```mojo
var arr = JsArray.create_with_length(b, env, 3)
arr.set(b, env, 0, JsNumber.create(b, env, 1.0).value)
return arr.value
```

Indices are `UInt32`, matching JavaScript's array index range.

**A loop that creates a napi_value per iteration needs a handle scope.**
Every handle stays alive until its enclosing scope closes, so building a
large array without one accumulates handles for the whole loop. Open a
`HandleScope` per iteration — and create the array itself *outside* it, or
it dies with the first iteration. Values stored into the array survive the
scope that created them.
"""


from napi.types import NapiEnv, NapiValue
from napi.bindings import Bindings
from napi.raw import (
    raw_create_array_with_length,
    raw_set_element,
    raw_get_element,
    raw_get_array_length,
    raw_has_element,
    raw_delete_element,
)
from napi.error import check_status


## JsArray — typed wrapper for a JavaScript array napi_value
struct JsArray:
    """Typed wrapper for a JavaScript Array napi_value.
    """
    ## The underlying napi_value handle. Valid within the current handle scope.
    var value: NapiValue
    """The underlying napi_value handle. Valid within the current handle scope.
    """

    def __init__(out self, value: NapiValue):
        """Wrap an existing napi_value known to be an Array.

        This does not validate the handle; use `js_is_array` if unsure.

        Args:
            value: The napi_value to wrap.
        """
        self.value = value

    # --- Bindings-aware overloads ---

    @staticmethod
    def create_with_length(
        b: Bindings, env: NapiEnv, len: UInt
    ) raises -> JsArray:
        """Create a JS Array with a given initial length.

        The length is a hint for the engine, exactly like `new Array(n)` — the
        elements are holes until assigned, not zeros.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            len: The initial length.

        Returns:
            A JsArray wrapping the new napi_value.

        Raises:
            If napi_create_array_with_length does not return napi_ok.
        """
        var result: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=result
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var status = raw_create_array_with_length(b, env, len, result_ptr)
        check_status(status)
        return JsArray(result)

    def set(
        self, b: Bindings, env: NapiEnv, index: UInt32, val: NapiValue
    ) raises:
        """Store a value at an index.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            index: The array index.
            val: The value to store.

        Raises:
            If napi_set_element does not return napi_ok.
        """
        var status = raw_set_element(b, env, self.value, index, val)
        check_status(status)

    def get(self, b: Bindings, env: NapiEnv, index: UInt32) raises -> NapiValue:
        """Read the value at an index.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            index: The array index.

        Returns:
            The element, or undefined if the index is a hole or
            out of range.

        Raises:
            If napi_get_element does not return napi_ok.
        """
        var result: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=result
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var status = raw_get_element(b, env, self.value, index, result_ptr)
        check_status(status)
        return result

    def length(self, b: Bindings, env: NapiEnv) raises -> UInt32:
        """Return the array's `length`.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.

        Returns:
            The length.

        Raises:
            If napi_get_array_length does not return napi_ok.
        """
        var len: UInt32 = 0
        var len_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=len
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var status = raw_get_array_length(b, env, self.value, len_ptr)
        check_status(status)
        return len

    def has(self, b: Bindings, env: NapiEnv, index: UInt32) raises -> Bool:
        """Report whether an index has a value.

        False for a hole in a sparse array, even below `length`.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            index: The array index.

        Returns:
            True if the element exists.

        Raises:
            If napi_has_element does not return napi_ok.
        """
        var result: Bool = False
        var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=result
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var status = raw_has_element(b, env, self.value, index, result_ptr)
        check_status(status)
        return result

    def delete_element(
        self, b: Bindings, env: NapiEnv, index: UInt32
    ) raises -> Bool:
        """Delete the element at an index, leaving a hole.

        Like the `delete` operator: `length` is unchanged.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            index: The array index.

        Returns:
            True if the element was deleted or was already absent.

        Raises:
            If napi_delete_element does not return napi_ok.
        """
        var deleted: Bool = False
        var deleted_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=deleted
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var status = raw_delete_element(b, env, self.value, index, deleted_ptr)
        check_status(status)
        return deleted
