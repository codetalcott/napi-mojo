"""Registering Mojo-backed JavaScript classes.

Call `define_class` first, then add members to the returned constructor,
one property at a time:

```mojo
var ctor = define_class(b, env, "Counter", fn_ptr(counter_ctor))
register_instance_method(b, env, ctor, "increment", fn_ptr(inc_fn))
register_getter(b, env, ctor, "value", fn_ptr(value_getter))
```

**Instance members go on the PROTOTYPE, not the constructor** — these
helpers retrieve `constructor.prototype` for you. Static members go on the
constructor itself.

**Wrapping native state must be type-tagged, and this is a memory-safety
rule, not a nicety.** `napi_unwrap` alone only proves "some native pointer
is wrapped here". A method borrowed onto a foreign wrapped instance —
`Counter.prototype.increment.call(someAnimal)` — would reinterpret an
`AnimalData` as a `CounterData`. That is memory corruption reachable from
pure JavaScript. So wrap with `wrap_native` (which tags) and unwrap with
the `NapiTypeTag`-taking overloads of `unwrap_native` (which verify).

**An object can carry exactly ONE tag**: `napi_type_tag_object` fails on a
second. Inheritance is therefore an accept-set at the unwrap site — an
Animal method checks for the Animal OR Dog tag with
`check_object_type_tag`, then uses the untagged unwrap, which is sound only
because `DogData` is layout-compatible with `AnimalData`. The untagged
overloads exist for exactly that pattern and are otherwise unverified: reach
for a tagged one unless you are implementing an accept-set.
"""


from napi.types import (
    NapiEnv,
    NapiValue,
    NapiPropertyDescriptor,
    NapiTypeTag,
    NapiStore,
)
from napi.bindings import Bindings
from napi.raw import (
    raw_define_class,
    raw_define_properties,
    raw_get_named_property,
    raw_unwrap,
    raw_wrap,
    raw_remove_wrap,
    raw_type_tag_object,
    raw_check_object_type_tag,
)
from napi.error import check_status, throw_js_type_error
from napi.framework.args import CbArgs
from napi.module import define_property
from napi.framework.js_value import js_get_global
from napi.framework.js_function import JsFunction
from napi.keepalive import pin_across_ffi


def _get_prototype(
    b: Bindings, env: NapiEnv, constructor: NapiValue
) raises -> NapiValue:
    var proto = NapiValue(unsafe_from_address=Int(0))
    check_status(
        raw_get_named_property(
            b,
            env,
            constructor,
            "prototype".unsafe_ptr().unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            Pointer(to=proto).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
        )
    )
    return proto


def define_class(
    b: Bindings,
    env: NapiEnv,
    name: StringLiteral,
    constructor_ptr: OpaquePointer[MutAnyOrigin],
) raises -> NapiValue:
    """Define a JavaScript class backed by a Mojo constructor callback.

    Registers the class with no properties; add members afterwards with the
    `register_*` helpers. The `data_ptr` overload attaches callback data,
    which for a napi-mojo addon is the cached bindings pointer.

    Args:
        b: Cached N-API bindings.
        env: The N-API environment.
        name: The class name, as a compile-time literal.
        constructor_ptr: The constructor callback, via `fn_ptr(...)`.
        data_ptr: Callback data for every member (data overload only).

    Returns:
        The constructor napi_value — pass it to the register_* helpers.

    Raises:
        If napi_define_class does not return napi_ok.
    """
    var result = NapiValue(unsafe_from_address=Int(0))
    var auto_length: UInt = ~UInt(0)
    check_status(
        raw_define_class(
            b,
            env,
            name.unsafe_ptr().unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            auto_length,
            constructor_ptr,
            OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0)),  # data = NULL
            0,  # property_count = 0
            OpaquePointer[ImmutAnyOrigin](unsafe_from_address=Int(0)),  # properties = NULL
            Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
        )
    )
    return result


def define_class(
    b: Bindings,
    env: NapiEnv,
    name: StringLiteral,
    constructor_ptr: OpaquePointer[MutAnyOrigin],
    data_ptr: OpaquePointer[MutAnyOrigin],
) raises -> NapiValue:
    """Define a JavaScript class backed by a Mojo constructor callback.

    Registers the class with no properties; add members afterwards with the
    `register_*` helpers. The `data_ptr` overload attaches callback data,
    which for a napi-mojo addon is the cached bindings pointer.

    Args:
        b: Cached N-API bindings.
        env: The N-API environment.
        name: The class name, as a compile-time literal.
        constructor_ptr: The constructor callback, via `fn_ptr(...)`.
        data_ptr: Callback data for every member (data overload only).

    Returns:
        The constructor napi_value — pass it to the register_* helpers.

    Raises:
        If napi_define_class does not return napi_ok.
    """
    var result = NapiValue(unsafe_from_address=Int(0))
    var auto_length: UInt = ~UInt(0)
    check_status(
        raw_define_class(
            b,
            env,
            name.unsafe_ptr().unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            auto_length,
            constructor_ptr,
            data_ptr,
            0,
            OpaquePointer[ImmutAnyOrigin](unsafe_from_address=Int(0)),
            Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
        )
    )
    return result


def register_instance_method(
    b: Bindings,
    env: NapiEnv,
    constructor: NapiValue,
    name: StringLiteral,
    method_ptr: OpaquePointer[MutAnyOrigin],
) raises:
    """Add a method to the class prototype.

    On the prototype, so every instance shares it.

    Args:
        b: Cached N-API bindings.
        env: The N-API environment.
        constructor: The class constructor from `define_class`.
        name: The member name, as a compile-time literal.
        method_ptr: The callback, via `fn_ptr(...)`.

    Raises:
        If reading the prototype or defining the property fails.
    """
    var proto = _get_prototype(b, env, constructor)
    var desc = NapiPropertyDescriptor()
    desc.utf8name = name.unsafe_ptr().unsafe_bitcast[
            NoneType
        ]().unsafe_origin_cast[ImmUntrackedOrigin]()
    desc.method = method_ptr.unsafe_origin_cast[MutUntrackedOrigin]()
    desc.attributes = 0
    define_property(b, env, proto, desc)


def register_getter(
    b: Bindings,
    env: NapiEnv,
    constructor: NapiValue,
    name: StringLiteral,
    getter_ptr: OpaquePointer[MutAnyOrigin],
) raises:
    """Add a read-only accessor to the class prototype.

    Args:
        b: Cached N-API bindings.
        env: The N-API environment.
        constructor: The class constructor from `define_class`.
        name: The member name, as a compile-time literal.
        getter_ptr: The getter callback, via `fn_ptr(...)`.

    Raises:
        If reading the prototype or defining the property fails.
    """
    var proto = _get_prototype(b, env, constructor)
    var desc = NapiPropertyDescriptor()
    desc.utf8name = name.unsafe_ptr().unsafe_bitcast[
            NoneType
        ]().unsafe_origin_cast[ImmUntrackedOrigin]()
    desc.getter = getter_ptr.unsafe_origin_cast[MutUntrackedOrigin]()
    desc.attributes = 0
    define_property(b, env, proto, desc)


def register_getter_setter(
    b: Bindings,
    env: NapiEnv,
    constructor: NapiValue,
    name: StringLiteral,
    getter_ptr: OpaquePointer[MutAnyOrigin],
    setter_ptr: OpaquePointer[MutAnyOrigin],
) raises:
    """Add a read/write accessor to the class prototype.

    Args:
        b: Cached N-API bindings.
        env: The N-API environment.
        constructor: The class constructor from `define_class`.
        name: The member name, as a compile-time literal.
        getter_ptr: The getter callback, via `fn_ptr(...)`.
        setter_ptr: The setter callback, via `fn_ptr(...)`.

    Raises:
        If reading the prototype or defining the property fails.
    """
    var proto = _get_prototype(b, env, constructor)
    var desc = NapiPropertyDescriptor()
    desc.utf8name = name.unsafe_ptr().unsafe_bitcast[
            NoneType
        ]().unsafe_origin_cast[ImmUntrackedOrigin]()
    desc.getter = getter_ptr.unsafe_origin_cast[MutUntrackedOrigin]()
    desc.setter = setter_ptr.unsafe_origin_cast[MutUntrackedOrigin]()
    desc.attributes = 0
    define_property(b, env, proto, desc)


def register_static_method(
    b: Bindings,
    env: NapiEnv,
    constructor: NapiValue,
    name: StringLiteral,
    method_ptr: OpaquePointer[MutAnyOrigin],
) raises:
    """Add a static method to the constructor itself.

    On the constructor, not the prototype — so it is `Counter.isCounter(x)`,
    not an instance member, and it receives no wrapped instance state.

    Args:
        b: Cached N-API bindings.
        env: The N-API environment.
        constructor: The class constructor from `define_class`.
        name: The member name, as a compile-time literal.
        method_ptr: The callback, via `fn_ptr(...)`.

    Raises:
        If napi_define_properties does not return napi_ok.
    """
    var desc = NapiPropertyDescriptor()
    desc.utf8name = name.unsafe_ptr().unsafe_bitcast[
            NoneType
        ]().unsafe_origin_cast[ImmUntrackedOrigin]()
    desc.method = method_ptr.unsafe_origin_cast[MutUntrackedOrigin]()
    desc.attributes = 0
    define_property(b, env, constructor, desc)


def register_static_getter(
    b: Bindings,
    env: NapiEnv,
    constructor: NapiValue,
    name: StringLiteral,
    getter_ptr: OpaquePointer[MutAnyOrigin],
) raises:
    """Add a read-only static accessor to the constructor itself.

    Args:
        b: Cached N-API bindings.
        env: The N-API environment.
        constructor: The class constructor from `define_class`.
        name: The member name, as a compile-time literal.
        getter_ptr: The getter callback, via `fn_ptr(...)`.

    Raises:
        If napi_define_properties does not return napi_ok.
    """
    var desc = NapiPropertyDescriptor()
    desc.utf8name = name.unsafe_ptr().unsafe_bitcast[
            NoneType
        ]().unsafe_origin_cast[ImmUntrackedOrigin]()
    desc.getter = getter_ptr.unsafe_origin_cast[MutUntrackedOrigin]()
    desc.attributes = 0
    define_property(b, env, constructor, desc)


def set_class_prototype(
    b: Bindings,
    env: NapiEnv,
    child_ctor: NapiValue,
    parent_ctor: NapiValue,
) raises:
    """Chain one class's prototype to another's, giving JS inheritance.

    Sets `child.prototype.__proto__ = parent.prototype`, so instances of the
    child inherit the parent's prototype members.

    Note this does NOT let an object carry both classes' type tags — a second
    tag fails. Handle the subclass at the unwrap site with an accept-set; see
    the module docstring.

    Args:
        b: Cached N-API bindings.
        env: The N-API environment.
        child_ctor: The subclass constructor.
        parent_ctor: The superclass constructor.

    Raises:
        If reading either prototype or setting it fails.
    """
    var child_proto = _get_prototype(b, env, child_ctor)
    var parent_proto = _get_prototype(b, env, parent_ctor)

    var global_obj = js_get_global(b, env)
    var object_key = NapiValue(unsafe_from_address=Int(0))
    check_status(
        raw_get_named_property(
            b,
            env,
            global_obj.value,
            "Object".unsafe_ptr().unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            Pointer(to=object_key).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
        )
    )
    var set_proto_of = NapiValue(unsafe_from_address=Int(0))
    check_status(
        raw_get_named_property(
            b,
            env,
            object_key,
            "setPrototypeOf".unsafe_ptr().unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            Pointer(to=set_proto_of).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
        )
    )

    _ = JsFunction(set_proto_of).call2(b, env, child_proto, parent_proto)


def register_static_getter_setter(
    b: Bindings,
    env: NapiEnv,
    constructor: NapiValue,
    name: StringLiteral,
    getter_ptr: OpaquePointer[MutAnyOrigin],
    setter_ptr: OpaquePointer[MutAnyOrigin],
) raises:
    """Add a read/write static accessor to the constructor itself.

    Args:
        b: Cached N-API bindings.
        env: The N-API environment.
        constructor: The class constructor from `define_class`.
        name: The member name, as a compile-time literal.
        getter_ptr: The getter callback, via `fn_ptr(...)`.
        setter_ptr: The setter callback, via `fn_ptr(...)`.

    Raises:
        If napi_define_properties does not return napi_ok.
    """
    var desc = NapiPropertyDescriptor()
    desc.utf8name = name.unsafe_ptr().unsafe_bitcast[
            NoneType
        ]().unsafe_origin_cast[ImmUntrackedOrigin]()
    desc.getter = getter_ptr.unsafe_origin_cast[MutUntrackedOrigin]()
    desc.setter = setter_ptr.unsafe_origin_cast[MutUntrackedOrigin]()
    desc.attributes = 0
    define_property(b, env, constructor, desc)


def type_tag_object(
    b: Bindings, env: NapiEnv, value: NapiValue, tag: NapiTypeTag
) raises:
    """Stamp an object with a 128-bit type tag (N-API v8).

    An object can carry exactly ONE tag — `napi_type_tag_object` fails with
    `napi_invalid_arg` if the object is already tagged. Inheritance is
    therefore expressed as an accept-set of tags at the unwrap site, never by
    tagging an object twice.

    Args:
        b: Cached N-API bindings.
        env: The N-API environment.
        value: The object to tag.
        tag: The class's fixed 128-bit tag.

    Raises:
        If the object is already tagged, or is not an object.
    """
    var t = NapiTypeTag(tag.lower, tag.upper)
    var tag_ptr: OpaquePointer[ImmutAnyOrigin] = Pointer(
        to=t
    ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
    check_status(raw_type_tag_object(b, env, value, tag_ptr))
    # napi READS the 128-bit tag through `tag_ptr` during the call and `t` has
    # no later use, so pin its slot until the call has returned.
    pin_across_ffi(t)


def check_object_type_tag(
    b: Bindings, env: NapiEnv, value: NapiValue, tag: NapiTypeTag
) raises -> Bool:
    """Report whether an object carries exactly this type tag.

    False for an untagged object and for one tagged with a different tag.
    This is the accept-set primitive: a superclass method checks for its own
    tag OR each subclass tag, then uses an untagged unwrap.

    Args:
        b: Cached N-API bindings.
        env: The N-API environment.
        value: The object to inspect.
        tag: The tag to test for.

    Returns:
        True if the object carries this exact tag.

    Raises:
        `napi_object_expected` if value is not an object.
    """
    var t = NapiTypeTag(tag.lower, tag.upper)
    var tag_ptr: OpaquePointer[ImmutAnyOrigin] = Pointer(
        to=t
    ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
    var result: Bool = False
    check_status(
        raw_check_object_type_tag(
            b,
            env,
            value,
            tag_ptr,
            Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
        )
    )
    pin_across_ffi(t)  # napi reads the tag through tag_ptr — see type_tag_object
    return result


## wrap_native — napi_wrap a native pointer onto `this` and type-tag it
##
## The tag is what makes unwrap_native[T](..., tag) safe: napi_unwrap alone
## only proves "some native pointer is wrapped here", so a method borrowed
## onto a foreign wrapped object (Counter.prototype.increment.call(anAnimal))
## would reinterpret the wrong struct type — memory corruption reachable from
## pure JS. Tag on wrap, verify on unwrap.
##
## `data_ptr` ownership: on success the finalizer owns it. On raise the
## CALLER still owns it and must free — the wrap happens first, and if
## tagging then fails the wrap is removed again (napi_remove_wrap) before
def wrap_native(
    b: Bindings,
    env: NapiEnv,
    this_val: NapiValue,
    data_ptr: OpaquePointer[MutAnyOrigin],
    finalize_ptr: OpaquePointer[MutAnyOrigin],
    tag: NapiTypeTag,
) raises:
    """Attach a native pointer to `this` and type-tag it.

    The tag is what makes the tagged `unwrap_native` safe. Without it,
    `napi_unwrap` proves only that *some* native pointer is wrapped, so a
    method borrowed onto a foreign instance would reinterpret the wrong
    struct — memory corruption reachable from pure JavaScript.

    **Ownership of `data_ptr`:** on success the finalizer owns it. On raise
    the CALLER still owns it and must free it. The wrap happens first, and if
    tagging then fails the wrap is removed again (`napi_remove_wrap`) before
    raising, so the caller's cleanup cannot double-free against the finalizer.

    The finalizer's `finalize_hint` is the cached-bindings pointer, which
    lives for the whole env lifetime, so a finalizer needing N-API can recover
    them with `bindings_from_context(hint)`.

    Args:
        b: Cached N-API bindings.
        env: The N-API environment.
        this_val: The instance to wrap onto, from `CbArgs.get_this`.
        data_ptr: The heap-allocated native state.
        finalize_ptr: The finalizer callback, which frees data_ptr.
        tag: The class's fixed 128-bit tag.

    Raises:
        If wrapping or tagging fails; on a tagging failure the wrap
            is removed first and data_ptr remains the caller's to free.
    """
    check_status(
        raw_wrap(
            b,
            env,
            this_val,
            data_ptr,
            finalize_ptr,
            b.unsafe_bitcast[NoneType]().as_unsafe_any_origin(),  # finalize_hint = cached bindings
            OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0)),
        )
    )
    try:
        type_tag_object(b, env, this_val, tag)
    except e:
        var removed = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        _ = raw_remove_wrap(
            b,
            env,
            this_val,
            Pointer(to=removed).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
        )
        # `removed` is an IGNORED output slot on the unwind path.
        pin_across_ffi(removed)
        raise e^


def unwrap_native[
    T: AnyType
](b: Bindings, env: NapiEnv, info: NapiValue) raises -> Pointer[
    T, MutAnyOrigin
]:
    """Retrieve the native state wrapped on the callback's `this`.

    Parameters:
        T: The wrapped struct type.

    **Untagged, and therefore unchecked.** It verifies only that
    something is wrapped. Use it ONLY to implement an accept-set, after
    `check_object_type_tag` has confirmed one of the acceptable tags — the
    inheritance pattern described in the module docstring. Anywhere else,
    use the `tag`-taking overload.

    Args:
        b: Cached N-API bindings.
        env: The N-API environment.
        info: The callback info handle.

    Returns:
        A pointer to the wrapped T.

    Raises:
        If nothing is wrapped on `this`.
    """
    var this_val = CbArgs.get_this(b, env, info)
    var data: Optional[OpaquePointer[MutAnyOrigin]] = None
    check_status(
        raw_unwrap(
            b, env, this_val, Pointer(to=data).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        )
    )
    if data is None:
        raise Error("unwrap failed: NULL native pointer")
    return data.value().unsafe_bitcast[T]()


## unwrap_native_from_this — unwrap using a pre-extracted this_val
##
## Use when this_val was already retrieved via get_bindings_and_this or
## get_bindings_this_and_one, avoiding a second napi_get_cb_info call.
## Distinct name required: same type signature as unwrap_native[T](b, env, info).
def unwrap_native_from_this[
    T: AnyType
](b: Bindings, env: NapiEnv, this_val: NapiValue) raises -> Pointer[
    T, MutAnyOrigin
]:
    """Retrieve the native state wrapped on an explicit object.

    The form to use when you already hold the instance rather than the
    callback info.

    Parameters:
        T: The wrapped struct type.

    **Untagged, and therefore unchecked.** It verifies only that
    something is wrapped. Use it ONLY to implement an accept-set, after
    `check_object_type_tag` has confirmed one of the acceptable tags — the
    inheritance pattern described in the module docstring. Anywhere else,
    use the `tag`-taking overload.

    Args:
        b: Cached N-API bindings.
        env: The N-API environment.
        this_val: The wrapped instance.

    Returns:
        A pointer to the wrapped T.

    Raises:
        If nothing is wrapped on the object.
    """
    var data: Optional[OpaquePointer[MutAnyOrigin]] = None
    check_status(
        raw_unwrap(b, env, this_val, Pointer(to=data).unsafe_bitcast[NoneType]().as_unsafe_any_origin())
    )
    if data is None:
        raise Error("unwrap failed: NULL native pointer")
    return data.value().unsafe_bitcast[T]()


## Tag-verified unwrap overloads
##
## Verify the object carries `tag` (stamped by wrap_native) before casting
## the wrapped pointer to T. On mismatch, follows the dual-signal convention
## (see convert.mojo _check_type): sets a pending JS TypeError for the JS
## caller AND raises a Mojo error for control flow — the callback's except
## block returns null and its own generic throw is swallowed by the already-
## pending TypeError.
def unwrap_native[
    T: AnyType
](b: Bindings, env: NapiEnv, info: NapiValue, tag: NapiTypeTag) raises -> Pointer[
    T, MutAnyOrigin
]:
    """Retrieve the native state wrapped on `this`, checking its type tag.

    Parameters:
        T: The wrapped struct type.

    Verifies the type tag first, so a method borrowed onto a foreign
    wrapped instance throws a JS TypeError instead of reinterpreting the
    wrong struct. **This is the overload to use.**

    Args:
        b: Cached N-API bindings.
        env: The N-API environment.
        info: The callback info handle.
        tag: The class's fixed 128-bit tag.

    Returns:
        A pointer to the wrapped T.

    Raises:
        On a tag mismatch, after setting a pending JS TypeError; or
            if nothing is wrapped.
    """
    var this_val = CbArgs.get_this(b, env, info)
    return unwrap_native_from_this[T](b, env, this_val, tag)


def unwrap_native_from_this[
    T: AnyType
](
    b: Bindings, env: NapiEnv, this_val: NapiValue, tag: NapiTypeTag
) raises -> Pointer[T, MutAnyOrigin]:
    """Retrieve native state from an explicit object, checking its type tag.

    Parameters:
        T: The wrapped struct type.

    Verifies the type tag first, so a method borrowed onto a foreign
    wrapped instance throws a JS TypeError instead of reinterpreting the
    wrong struct. **This is the overload to use.**

    Args:
        b: Cached N-API bindings.
        env: The N-API environment.
        this_val: The wrapped instance.
        tag: The class's fixed 128-bit tag.

    Returns:
        A pointer to the wrapped T.

    Raises:
        On a tag mismatch, after setting a pending JS TypeError; or
            if nothing is wrapped.
    """
    if not check_object_type_tag(b, env, this_val, tag):
        throw_js_type_error(
            b, env, "native type mismatch: object was not created by this class"
        )
        raise Error("unwrap: type tag mismatch")
    return unwrap_native_from_this[T](b, env, this_val)
