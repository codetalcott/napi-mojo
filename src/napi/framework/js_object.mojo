"""Ergonomic wrapper for JavaScript object values.

```mojo
var obj = JsObject.create(b, env)
var msg = JsString.create_literal(b, env, "Hello!")
obj.set_property(b, env, "message", msg.value)
return obj.value
```

**Three key flavours, and picking the wrong one is the classic bug here.**
Every accessor comes in three forms, distinguished by how the key is
spelled:

- `*_property` takes a **StringLiteral** — a static, NUL-terminated
  `.rodata` key handed straight to N-API's C-string API. Preferred for
  fixed names.
- `*_named_property` takes a heap **String**, for a key computed at
  runtime. It is converted to a length-delimited JS string key internally,
  never passed to the C-string API: a heap Mojo String has no guaranteed
  NUL terminator, so a strlen-based API would read out of bounds.
- `set`/`get`/`has`/`has_own`/`delete_prop` take a **NapiValue** key, for
  keys that came from JavaScript, and for Symbol keys. Pass a JS string
  value directly rather than round-tripping it through a Mojo String —
  that round trip loses the NUL terminator and the lookup silently fails.
"""


from std.collections import Optional
from napi.types import (
    NapiEnv,
    NapiValue,
    NAPI_KEY_OWN_ONLY,
    NAPI_KEY_ENUMERABLE,
    NAPI_KEY_SKIP_SYMBOLS,
    NAPI_KEY_NUMBERS_TO_STRINGS,
)
from napi.bindings import Bindings
# js_function imports only js_number, so this direction is acyclic.
from napi.framework.js_function import JsFunction
from napi.raw import (
    raw_create_object,
    raw_create_string_utf8,
    raw_set_named_property,
    raw_get_named_property,
    raw_has_named_property,
    raw_get_property,
    raw_set_property,
    raw_has_property,
    raw_get_property_names,
    raw_get_all_property_names,
    raw_has_own_property,
    raw_delete_property,
    raw_instanceof,
    raw_object_freeze,
    raw_object_seal,
    raw_get_prototype,
)
from napi.error import check_status


def _named_key(b: Bindings, env: NapiEnv, name: String) raises -> NapiValue:
    var result: NapiValue = NapiValue(unsafe_from_address=Int(0))
    var str_ptr: OpaquePointer[ImmutAnyOrigin] = name.unsafe_ptr().unsafe_bitcast[
        NoneType
    ]().as_unsafe_any_origin()
    var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
        to=result
    ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
    var status = raw_create_string_utf8(
        b, env, str_ptr, UInt(name.byte_length()), result_ptr
    )
    check_status(status)
    return result


## JsObject — typed wrapper for a JavaScript object napi_value
struct JsObject:
    """Typed wrapper for a JavaScript object napi_value.
    """
    ## The underlying napi_value handle. Valid within the current handle scope.
    var value: NapiValue
    """The underlying napi_value handle. Valid within the current handle scope.
    """

    def __init__(out self, value: NapiValue):
        """Wrap an existing napi_value known to be an object.

        This does not validate the handle. Prefer `create` for a fresh object.

        Args:
            value: The napi_value to wrap.
        """
        self.value = value

    # --- Bindings-aware overloads ---

    @staticmethod
    def create(b: Bindings, env: NapiEnv) raises -> JsObject:
        """Create a new, empty JavaScript object (`{}`).

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.

        Returns:
            A JsObject wrapping the new napi_value.

        Raises:
            If napi_create_object does not return napi_ok.
        """
        var result: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=result
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var status = raw_create_object(b, env, result_ptr)
        check_status(status)
        return JsObject(result)

    def set_property(
        self, b: Bindings, env: NapiEnv, key: StringLiteral, val: NapiValue
    ) raises:
        """Set a property using a static string key.

        The preferred form for fixed names — the literal is NUL-terminated
        `.rodata`, so it is safe to hand to N-API's C-string API.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            key: The property name, as a compile-time literal.
            val: The value to store.

        Raises:
            If napi_set_named_property does not return napi_ok.
        """
        var key_ptr: OpaquePointer[ImmutAnyOrigin] = key.unsafe_ptr().unsafe_bitcast[
            NoneType
        ]().as_unsafe_any_origin()
        var status = raw_set_named_property(b, env, self.value, key_ptr, val)
        check_status(status)

    def set_named_property(
        self, b: Bindings, env: NapiEnv, name: String, val: NapiValue
    ) raises:
        """Set a property using a runtime-computed String key.

        The key is converted to a JS string with an explicit byte length, not
        passed to the C-string API — a heap Mojo String has no guaranteed NUL
        terminator.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            name: The property name.
            val: The value to store.

        Raises:
            If the underlying N-API calls do not return napi_ok.
        """
        var key = _named_key(b, env, name)
        var status = raw_set_property(b, env, self.value, key, val)
        check_status(status)

    def set(
        self, b: Bindings, env: NapiEnv, key: NapiValue, val: NapiValue
    ) raises:
        """Set a property using a napi_value key.

        Use this for keys that came from JavaScript, and for Symbol keys.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            key: The property key, as a JS value.
            val: The value to store.

        Raises:
            If napi_set_property does not return napi_ok.
        """
        var status = raw_set_property(b, env, self.value, key, val)
        check_status(status)

    def has(self, b: Bindings, env: NapiEnv, key: NapiValue) raises -> Bool:
        """Report whether a property exists, using a napi_value key.

        Follows the `in` operator: inherited properties count. Use `has_own`
        for own properties only.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            key: The property key, as a JS value.

        Returns:
            True if the property is present.

        Raises:
            If napi_has_property does not return napi_ok.
        """
        var exists: Bool = False
        var exists_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=exists
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var status = raw_has_property(b, env, self.value, key, exists_ptr)
        check_status(status)
        return exists

    def get(
        self, b: Bindings, env: NapiEnv, key: NapiValue
    ) raises -> NapiValue:
        """Read a property using a napi_value key.

        Use this for keys that came from JavaScript, and for Symbol keys.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            key: The property key, as a JS value.

        Returns:
            The property value, or undefined if absent.

        Raises:
            If napi_get_property does not return napi_ok.
        """
        var result: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=result
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var status = raw_get_property(b, env, self.value, key, result_ptr)
        check_status(status)
        return result

    def get_property(
        self, b: Bindings, env: NapiEnv, key: StringLiteral
    ) raises -> NapiValue:
        """Read a property using a static string key.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            key: The property name, as a compile-time literal.

        Returns:
            The property value, or undefined if absent.

        Raises:
            If napi_get_named_property does not return napi_ok.
        """
        var result: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var key_ptr: OpaquePointer[ImmutAnyOrigin] = key.unsafe_ptr().unsafe_bitcast[
            NoneType
        ]().as_unsafe_any_origin()
        var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=result
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var status = raw_get_named_property(
            b, env, self.value, key_ptr, result_ptr
        )
        check_status(status)
        return result

    def get_named_property(
        self, b: Bindings, env: NapiEnv, name: String
    ) raises -> NapiValue:
        """Read a property using a runtime-computed String key.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            name: The property name.

        Returns:
            The property value, or undefined if absent.

        Raises:
            If the underlying N-API calls do not return napi_ok.
        """
        var key = _named_key(b, env, name)
        var result: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=result
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var status = raw_get_property(b, env, self.value, key, result_ptr)
        check_status(status)
        return result

    def call_method(
        self, b: Bindings, env: NapiEnv, name: String, args: List[NapiValue]
    ) raises -> NapiValue:
        """Look up a method by name and call it with `this` bound to self.

        This is the ergonomic form of driving JavaScript from Mojo:

            var fs = host.require("fs")
            var txt = fs.call_method(b, env, "readFileSync", args)

        Binding `this` matters: `JsFunction.call1` uses `undefined` as the
        receiver, which silently breaks any callee that reads `this`.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            name: The method's property name on this object.
            args: The arguments, in order. May be empty.

        Returns:
            The value the method returned.

        Raises:
            Error: If the property is missing or not callable, or the method
                threw. A JS exception raised by the method stays pending and
                keeps its identity.
        """
        var f = JsFunction(self.get_named_property(b, env, name))
        return f.call_with(b, env, self.value, args)

    def has_property(
        self, b: Bindings, env: NapiEnv, key: StringLiteral
    ) raises -> Bool:
        """Report whether a property exists, using a static string key.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            key: The property name, as a compile-time literal.

        Returns:
            True if the property is present.

        Raises:
            If napi_has_named_property does not return napi_ok.
        """
        var exists: Bool = False
        var key_ptr: OpaquePointer[ImmutAnyOrigin] = key.unsafe_ptr().unsafe_bitcast[
            NoneType
        ]().as_unsafe_any_origin()
        var exists_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=exists
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var status = raw_has_named_property(
            b, env, self.value, key_ptr, exists_ptr
        )
        check_status(status)
        return exists

    def get_opt(
        self, b: Bindings, env: NapiEnv, key: StringLiteral
    ) raises -> Optional[NapiValue]:
        """Read a property, or None when it is absent.

        Distinguishes "missing" from "present and undefined", which `get_property`
        cannot: it returns undefined for both. Costs an extra `has` check.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            key: The property name, as a compile-time literal.

        Returns:
            The value, or None if the property does not exist.

        Raises:
            If the underlying N-API calls do not return napi_ok.
        """
        if not self.has_property(b, env, key):
            return None
        return self.get_property(b, env, key)

    def keys(self, b: Bindings, env: NapiEnv) raises -> NapiValue:
        """List the object's own enumerable string keys.

        Matches `Object.keys`: own properties only, enumerable only, symbols
        skipped, integer indices rendered as strings. Use `keys_filtered` for
        any other combination.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.

        Returns:
            A JS Array of key strings.

        Raises:
            If napi_get_all_property_names does not return napi_ok.
        """
        var result: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=result
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var status = raw_get_all_property_names(
            b,
            env,
            self.value,
            NAPI_KEY_OWN_ONLY,
            NAPI_KEY_ENUMERABLE | NAPI_KEY_SKIP_SYMBOLS,
            NAPI_KEY_NUMBERS_TO_STRINGS,
            result_ptr,
        )
        check_status(status)
        return result

    def keys_filtered(
        self,
        b: Bindings,
        env: NapiEnv,
        mode: Int32,
        filter: Int32,
        conversion: Int32,
    ) raises -> NapiValue:
        """List property names with full control over the filters.

        The unrestricted form of `napi_get_all_property_names`, for the cases
        `keys` does not cover — inherited properties, non-enumerables, symbols.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            mode: A NAPI_KEY_* collection mode (own vs. include prototypes).
            filter: A bitwise OR of NAPI_KEY_* attribute filters.
            conversion: A NAPI_KEY_* index-conversion mode.

        Returns:
            A JS Array of keys.

        Raises:
            If napi_get_all_property_names does not return napi_ok.
        """
        var result: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=result
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        check_status(
            raw_get_all_property_names(
                b, env, self.value, mode, filter, conversion, result_ptr
            )
        )
        return result

    def has_own(self, b: Bindings, env: NapiEnv, key: NapiValue) raises -> Bool:
        """Report whether the object has the property as its **own**.

        Unlike `has`, inherited properties do not count.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            key: The property key, as a JS value.

        Returns:
            True if the property is an own property.

        Raises:
            If napi_has_own_property does not return napi_ok.
        """
        var exists: Bool = False
        var exists_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=exists
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var status = raw_has_own_property(b, env, self.value, key, exists_ptr)
        check_status(status)
        return exists

    def delete_prop(
        self, b: Bindings, env: NapiEnv, key: NapiValue
    ) raises -> Bool:
        """Delete a property, using a napi_value key.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            key: The property key, as a JS value.

        Returns:
            True if the property was deleted, or was already absent;
            False if it exists but is non-configurable.

        Raises:
            If napi_delete_property does not return napi_ok.
        """
        var deleted: Bool = False
        var deleted_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=deleted
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var status = raw_delete_property(b, env, self.value, key, deleted_ptr)
        check_status(status)
        return deleted

    def instance_of(
        self, b: Bindings, env: NapiEnv, constructor: NapiValue
    ) raises -> Bool:
        """Test the object against a constructor, like `instanceof`.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            constructor: The constructor function to test against.

        Returns:
            True if the object is an instance.

        Raises:
            If napi_instanceof does not return napi_ok.
        """
        var result: Bool = False
        var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=result
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var status = raw_instanceof(b, env, self.value, constructor, result_ptr)
        check_status(status)
        return result

    def freeze(self, b: Bindings, env: NapiEnv) raises:
        """Freeze the object, like `Object.freeze`.

        Existing properties become non-writable and non-configurable, and no
        new ones can be added. Irreversible.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.

        Raises:
            If napi_object_freeze does not return napi_ok.
        """
        var status = raw_object_freeze(b, env, self.value)
        check_status(status)

    def seal(self, b: Bindings, env: NapiEnv) raises:
        """Seal the object, like `Object.seal`.

        No properties may be added or removed, but existing writable ones can
        still be assigned — the difference from `freeze`.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.

        Raises:
            If napi_object_seal does not return napi_ok.
        """
        var status = raw_object_seal(b, env, self.value)
        check_status(status)

    def prototype(self, b: Bindings, env: NapiEnv) raises -> NapiValue:
        """Return the object's prototype, like `Object.getPrototypeOf`.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.

        Returns:
            The prototype value.

        Raises:
            If napi_get_prototype does not return napi_ok.
        """
        var result: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=result
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var status = raw_get_prototype(b, env, self.value, result_ptr)
        check_status(status)
        return result
