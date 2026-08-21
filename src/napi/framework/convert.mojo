"""Type-conversion traits for JS <-> Mojo marshalling.

`ToJsValue` and `FromJsValue` standardise how a Mojo value crosses the
boundary, so generic code can be written once over any convertible type:

```mojo
var result = JsF64(42.0).to_js(b, env)          # Mojo -> JS
var n = JsF64.from_js(b, env, napi_val)         # JS -> Mojo, type-checked
var arr = to_js_array(b, env, List[JsF64](...)) # parametric over the traits
var items = from_js_array[JsStr](b, env, napi_val)
```

**The error-signalling convention, which every `from_js` here follows:** on a
type mismatch it BOTH sets a pending JS `TypeError` (so JavaScript sees a
typed error with a real message) AND raises a Mojo error (so execution
unwinds to the callback's `except:` block). A caller that catches the Mojo
error must NOT make further N-API calls other than returning — a pending
exception makes every subsequent call report `napi_pending_exception`.

**Both trait methods take `Bindings` first, and that is load-bearing.** An
env-only trait method used to live here, and it forced one
`dlopen(NULL)` + `dlsym` *per element* inside the parametric helpers.

Object helpers (`to_js_object_str_f64` and friends) live in
`addon/convert_ops.mojo`, not here.
"""


from napi.types import (
    NapiEnv,
    NapiValue,
    NapiValueType,
    NAPI_TYPE_NUMBER,
    NAPI_TYPE_STRING,
    NAPI_TYPE_BOOLEAN,
)
from napi.bindings import Bindings
from napi.framework.js_number import JsNumber
from napi.framework.js_string import JsString
from napi.framework.js_boolean import JsBoolean
from napi.framework.js_int32 import JsInt32
from napi.framework.js_array import JsArray
from napi.framework.js_value import js_typeof, js_type_name, js_is_array
from napi.error import throw_js_type_error_dynamic


trait ToJsValue:
    """Convert a Mojo value into a JavaScript napi_value.

    Implement alongside `FromJsValue` to make a type usable with the
    parametric array helpers.
    """
    def to_js(self, b: Bindings, env: NapiEnv) raises -> NapiValue:
        """Convert this value to a napi_value.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.

        Returns:
            The JavaScript value.

        Raises:
            If the underlying N-API call fails.
        """
        ...


trait FromJsValue:
    """Extract a Mojo value from a JavaScript napi_value.

    Implementations validate the JS type first and follow the module's
    error-signalling convention on mismatch: throw a JS TypeError *and*
    raise.
    """
    @staticmethod
    def from_js(b: Bindings, env: NapiEnv, val: NapiValue) raises -> Self:
        """Read a napi_value into a Mojo value of this type.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            val: The JavaScript value to convert.

        Returns:
            The converted value.

        Raises:
            If val is not the expected JS type, after setting a pending
                JS TypeError.
        """
        ...


## _check_type — validate that a NapiValue has the expected type, throw TypeError if not
##
## Error-signalling convention (applies to every validation helper here): on
## mismatch we BOTH set a pending JS TypeError (so JS sees a typed error with
## a real message) AND raise a Mojo error (so Mojo execution unwinds to the
## callback's except block, which returns null). Callers that catch the Mojo
## error must NOT make further N-API calls other than returning — the pending
## exception makes any subsequent call report napi_pending_exception.
def _check_type(
    b: Bindings,
    env: NapiEnv,
    val: NapiValue,
    expected: NapiValueType,
    expected_name: StringLiteral,
) raises:
    var actual = js_typeof(b, env, val)
    if actual != expected:
        throw_js_type_error_dynamic(
            b,
            env,
            "expected " + expected_name + ", got " + js_type_name(actual),
        )
        raise Error("type mismatch")


## JsF64 — Float64 ↔ JS number
struct JsF64(Copyable, FromJsValue, ToJsValue):
    """`Float64` wrapper implementing both conversion traits.

    Round-trips through `napi_create_double` / `napi_get_value_double`, so it is the exact JS numeric type.
    """
    var val: Float64
    """The wrapped Mojo value."""

    def __init__(out self, val: Float64):
        """Wrap a Mojo Float64.

        Args:
            val: The value to wrap.
        """
        self.val = val

    def __init__(out self, *, copy: Self):
        """Copy-construct from another JsF64.

        Args:
            copy: The value to copy.
        """
        self.val = copy.val

    def __init__(out self, *, deinit move: Self):
        """Move-construct from another JsF64.

        Args:
            move: The value to move from.
        """
        self.val = move.val

    def to_js(self, b: Bindings, env: NapiEnv) raises -> NapiValue:
        """Convert the wrapped value to a JS number.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.

        Returns:
            The JavaScript value.

        Raises:
            If the underlying N-API call fails.
        """
        return JsNumber.create(b, env, self.val).value

    @staticmethod
    def from_js(b: Bindings, env: NapiEnv, val: NapiValue) raises -> Self:
        """Read a napi_value as a JS number.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            val: The JavaScript value.

        Returns:
            The wrapped Mojo value.

        Raises:
            If val is not a JS number, after setting a pending TypeError.
        """
        _check_type(b, env, val, NAPI_TYPE_NUMBER, "number")
        var n: Float64 = JsNumber.from_napi_value(b, env, val)
        return JsF64(n)


## JsI32 — Int32 ↔ JS number (int32)
struct JsI32(FromJsValue, ToJsValue):
    """`Int32` wrapper implementing both conversion traits.

    Reads via the ECMAScript ToInt32 conversion, so an out-of-range value wraps rather than raising.
    """
    var val: Int32
    """The wrapped Mojo value."""

    def __init__(out self, val: Int32):
        """Wrap a Mojo Int32.

        Args:
            val: The value to wrap.
        """
        self.val = val

    def to_js(self, b: Bindings, env: NapiEnv) raises -> NapiValue:
        """Convert the wrapped value to a JS number read as Int32.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.

        Returns:
            The JavaScript value.

        Raises:
            If the underlying N-API call fails.
        """
        return JsInt32.create(b, env, self.val).value

    @staticmethod
    def from_js(b: Bindings, env: NapiEnv, val: NapiValue) raises -> Self:
        """Read a napi_value as a JS number read as Int32.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            val: The JavaScript value.

        Returns:
            The wrapped Mojo value.

        Raises:
            If val is not a JS number, after setting a pending TypeError.
        """
        _check_type(b, env, val, NAPI_TYPE_NUMBER, "number")
        return JsI32(JsInt32.from_napi_value(b, env, val))


## JsBool — Bool ↔ JS boolean
struct JsBool(FromJsValue, ToJsValue):
    """`Bool` wrapper implementing both conversion traits.

    Requires an actual boolean; this is not a truthiness test.
    """
    var val: Bool
    """The wrapped Mojo value."""

    def __init__(out self, val: Bool):
        """Wrap a Mojo Bool.

        Args:
            val: The value to wrap.
        """
        self.val = val

    def to_js(self, b: Bindings, env: NapiEnv) raises -> NapiValue:
        """Convert the wrapped value to a JS boolean.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.

        Returns:
            The JavaScript value.

        Raises:
            If the underlying N-API call fails.
        """
        return JsBoolean.create(b, env, self.val).value

    @staticmethod
    def from_js(b: Bindings, env: NapiEnv, val: NapiValue) raises -> Self:
        """Read a napi_value as a JS boolean.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            val: The JavaScript value.

        Returns:
            The wrapped Mojo value.

        Raises:
            If val is not a JS boolean, after setting a pending TypeError.
        """
        _check_type(b, env, val, NAPI_TYPE_BOOLEAN, "boolean")
        return JsBool(JsBoolean.from_napi_value(b, env, val))


## JsStr — String ↔ JS string
struct JsStr(Copyable, FromJsValue, ToJsValue):
    """`String` wrapper implementing both conversion traits.

    The Mojo String owns its bytes; the JS string is built with an explicit byte length.
    """
    var val: String
    """The wrapped Mojo value."""

    def __init__(out self, val: String):
        """Wrap a Mojo String.

        Args:
            val: The value to wrap.
        """
        self.val = val

    def __init__(out self, *, copy: Self):
        """Copy-construct from another JsStr.

        Args:
            copy: The value to copy.
        """
        self.val = copy.val

    def __init__(out self, *, deinit move: Self):
        """Move-construct from another JsStr.

        Args:
            move: The value to move from.
        """
        self.val = move.val^

    def to_js(self, b: Bindings, env: NapiEnv) raises -> NapiValue:
        """Convert the wrapped value to a JS string.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.

        Returns:
            The JavaScript value.

        Raises:
            If the underlying N-API call fails.
        """
        return JsString.create(b, env, self.val).value

    @staticmethod
    def from_js(b: Bindings, env: NapiEnv, val: NapiValue) raises -> Self:
        """Read a napi_value as a JS string.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            val: The JavaScript value.

        Returns:
            The wrapped Mojo value.

        Raises:
            If val is not a JS string, after setting a pending TypeError.
        """
        _check_type(b, env, val, NAPI_TYPE_STRING, "string")
        var s: String = JsString.from_napi_value(b, env, val)
        return JsStr(s)


## JsRaw — NapiValue pass-through (no type checking)
struct JsRaw(FromJsValue, ToJsValue):
    """`NapiValue` wrapper implementing both conversion traits.

    The escape hatch: it performs no conversion and no type check, so it lets an already-obtained napi_value flow through the generic helpers unchanged.
    """
    var val: NapiValue
    """The wrapped Mojo value."""

    def __init__(out self, val: NapiValue):
        """Wrap a Mojo NapiValue.

        Args:
            val: The value to wrap.
        """
        self.val = val

    def to_js(self, b: Bindings, env: NapiEnv) raises -> NapiValue:
        """Convert the wrapped value to any JS value.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.

        Returns:
            The JavaScript value.

        Raises:
            If the underlying N-API call fails.
        """
        return self.val

    @staticmethod
    def from_js(b: Bindings, env: NapiEnv, val: NapiValue) raises -> Self:
        """Read a napi_value as any JS value.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            val: The JavaScript value.

        Returns:
            The wrapped Mojo value.

        Raises:
            Never for a type mismatch — this wrapper does no checking.
        """
        return JsRaw(val)


# ---------------------------------------------------------------------------
# Collection helpers (E6): JS Array ↔ Mojo List conversions
#
# Concrete typed free functions for the most common element types.
# Uses cached Bindings for all N-API calls (array create/get/set).
# ---------------------------------------------------------------------------


def to_js_array_f64(
    b: Bindings, env: NapiEnv, items: List[Float64]
) raises -> NapiValue:
    """Convert a `List[Float64]` to a JavaScript `Array<number>`.

    Args:
        b: Cached N-API bindings.
        env: The N-API environment.
        items: The values, in order.

    Returns:
        The JS Array.

    Raises:
        If an underlying N-API call fails.
    """
    var arr = JsArray.create_with_length(b, env, UInt(len(items)))
    for i in range(len(items)):
        arr.set(b, env, UInt32(i), JsNumber.create(b, env, items[i]).value)
    return arr.value


def from_js_array_f64(
    b: Bindings, env: NapiEnv, val: NapiValue
) raises -> List[Float64]:
    """Convert a JavaScript `Array<number>` to a `List[Float64]`.

    Each element is read with `napi_get_value_double`, whose behaviour on a
    **non-number element is to yield 0 rather than to fail** — so a mixed
    array converts silently. Check element types yourself if that matters.

    Args:
        b: Cached N-API bindings.
        env: The N-API environment.
        val: A napi_value holding a JS Array.

    Returns:
        The converted values, in order.

    Raises:
        If val is not an array, after setting a pending TypeError.
    """
    if not js_is_array(b, env, val):
        throw_js_type_error_dynamic(
            b, env, "from_js_array_f64: expected array"
        )
        raise Error("type mismatch")
    var arr = JsArray(val)
    var n = Int(arr.length(b, env))
    var result = List[Float64]()
    for i in range(n):
        result.append(
            JsNumber.from_napi_value(b, env, arr.get(b, env, UInt32(i)))
        )
    return result^


def to_js_array_str(
    b: Bindings, env: NapiEnv, items: List[String]
) raises -> NapiValue:
    """Convert a `List[String]` to a JavaScript `Array<string>`.

    Args:
        b: Cached N-API bindings.
        env: The N-API environment.
        items: The values, in order.

    Returns:
        The JS Array.

    Raises:
        If an underlying N-API call fails.
    """
    var arr = JsArray.create_with_length(b, env, UInt(len(items)))
    for i in range(len(items)):
        arr.set(b, env, UInt32(i), JsString.create(b, env, items[i]).value)
    return arr.value


def from_js_array_str(
    b: Bindings, env: NapiEnv, val: NapiValue
) raises -> List[String]:
    """Convert a JavaScript `Array<string>` to a `List[String]`.

    Unlike the Float64 form, a non-string element does not convert silently:
    `napi_get_value_string_utf8` reports a type error for it.

    Args:
        b: Cached N-API bindings.
        env: The N-API environment.
        val: A napi_value holding a JS Array.

    Returns:
        The converted values, in order.

    Raises:
        If val is not an array, or an element is not a string.
    """
    if not js_is_array(b, env, val):
        throw_js_type_error_dynamic(
            b, env, "from_js_array_str: expected array"
        )
        raise Error("type mismatch")
    var arr = JsArray(val)
    var n = Int(arr.length(b, env))
    var result = List[String]()
    for i in range(n):
        result.append(
            JsString.from_napi_value(b, env, arr.get(b, env, UInt32(i)))
        )
    return result^


# ---------------------------------------------------------------------------
# Parametric helpers (Step 1): JS Array ↔ List[T] for any ToJsValue/FromJsValue T
#
# Element types must implement both trait overloads and be Copyable.
# Example: to_js_array(b, env, List[JsF64](...))
#          from_js_array[JsStr](b, env, napi_val)
# ---------------------------------------------------------------------------


def to_js_array[
    T: ToJsValue & Copyable
](b: Bindings, env: NapiEnv, items: List[T]) raises -> NapiValue:
    """Convert a `List[T]` to a JavaScript Array, for any `ToJsValue` type.

    The generic form of `to_js_array_f64`/`_str`. Because the trait method
    takes cached bindings, element conversion costs no dlsym per element.

    Parameters:
        T: The element type; must implement ToJsValue and be Copyable.

    Args:
        b: Cached N-API bindings.
        env: The N-API environment.
        items: The values, in order.

    Returns:
        The JS Array.

    Raises:
        If an element's conversion or an N-API call fails.
    """
    var arr = JsArray.create_with_length(b, env, UInt(len(items)))
    for i in range(len(items)):
        arr.set(b, env, UInt32(i), items[i].to_js(b, env))
    return arr.value


def from_js_array[
    T: FromJsValue & Copyable & Deinitable
](b: Bindings, env: NapiEnv, val: NapiValue) raises -> List[T]:
    """Convert a JavaScript Array to a `List[T]`, for any `FromJsValue` type.

    Each element goes through `T.from_js`, so it inherits that type's
    validation and the module's error-signalling convention.

    Parameters:
        T: The element type; must implement FromJsValue, Copyable and Deinitable.

    Args:
        b: Cached N-API bindings.
        env: The N-API environment.
        val: A napi_value holding a JS Array.

    Returns:
        The converted values, in order.

    Raises:
        If val is not an array, or any element fails to convert.
            A pending JS TypeError is set in both cases.
    """
    if not js_is_array(b, env, val):
        throw_js_type_error_dynamic(b, env, "from_js_array: expected array")
        raise Error("type mismatch")
    var arr = JsArray(val)
    var n = Int(arr.length(b, env))
    var result = List[T]()
    for i in range(n):
        result.append(T.from_js(b, env, arr.get(b, env, UInt32(i))))
    return result^
