## src/napi/framework/js_class.mojo — helpers for registering Mojo-backed JS classes
##
## Uses the one-property-at-a-time pattern (consistent with register_method).
## Call define_class() first, then add methods/getters/setters to the returned
## constructor napi_value. Instance properties go on the prototype (retrieved
## via constructor.prototype).

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
    data_ptr: NapiStore,
) raises -> NapiValue:
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
    method_ptr: NapiStore,
) raises:
    var proto = _get_prototype(b, env, constructor)
    var desc = NapiPropertyDescriptor()
    desc.utf8name = name.unsafe_ptr().unsafe_bitcast[
            NoneType
        ]().unsafe_origin_cast[ImmutUntrackedOrigin]()
    desc.method = method_ptr
    desc.attributes = 0
    define_property(b, env, proto, desc)


def register_getter(
    b: Bindings,
    env: NapiEnv,
    constructor: NapiValue,
    name: StringLiteral,
    getter_ptr: NapiStore,
) raises:
    var proto = _get_prototype(b, env, constructor)
    var desc = NapiPropertyDescriptor()
    desc.utf8name = name.unsafe_ptr().unsafe_bitcast[
            NoneType
        ]().unsafe_origin_cast[ImmutUntrackedOrigin]()
    desc.getter = getter_ptr
    desc.attributes = 0
    define_property(b, env, proto, desc)


def register_getter_setter(
    b: Bindings,
    env: NapiEnv,
    constructor: NapiValue,
    name: StringLiteral,
    getter_ptr: NapiStore,
    setter_ptr: NapiStore,
) raises:
    var proto = _get_prototype(b, env, constructor)
    var desc = NapiPropertyDescriptor()
    desc.utf8name = name.unsafe_ptr().unsafe_bitcast[
            NoneType
        ]().unsafe_origin_cast[ImmutUntrackedOrigin]()
    desc.getter = getter_ptr
    desc.setter = setter_ptr
    desc.attributes = 0
    define_property(b, env, proto, desc)


def register_static_method(
    b: Bindings,
    env: NapiEnv,
    constructor: NapiValue,
    name: StringLiteral,
    method_ptr: NapiStore,
) raises:
    var desc = NapiPropertyDescriptor()
    desc.utf8name = name.unsafe_ptr().unsafe_bitcast[
            NoneType
        ]().unsafe_origin_cast[ImmutUntrackedOrigin]()
    desc.method = method_ptr
    desc.attributes = 0
    define_property(b, env, constructor, desc)


def register_static_getter(
    b: Bindings,
    env: NapiEnv,
    constructor: NapiValue,
    name: StringLiteral,
    getter_ptr: NapiStore,
) raises:
    var desc = NapiPropertyDescriptor()
    desc.utf8name = name.unsafe_ptr().unsafe_bitcast[
            NoneType
        ]().unsafe_origin_cast[ImmutUntrackedOrigin]()
    desc.getter = getter_ptr
    desc.attributes = 0
    define_property(b, env, constructor, desc)


def set_class_prototype(
    b: Bindings,
    env: NapiEnv,
    child_ctor: NapiValue,
    parent_ctor: NapiValue,
) raises:
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
    getter_ptr: NapiStore,
    setter_ptr: NapiStore,
) raises:
    var desc = NapiPropertyDescriptor()
    desc.utf8name = name.unsafe_ptr().unsafe_bitcast[
            NoneType
        ]().unsafe_origin_cast[ImmutUntrackedOrigin]()
    desc.getter = getter_ptr
    desc.setter = setter_ptr
    desc.attributes = 0
    define_property(b, env, constructor, desc)


## type_tag_object — stamp an object with a 128-bit type tag (N-API v8)
##
## An object can carry exactly ONE tag: napi_type_tag_object fails with
## napi_invalid_arg if the object is already tagged. Inheritance is therefore
## expressed as an accept-set of tags at the unwrap site (see class_animal),
## never by tagging an object twice.
def type_tag_object(
    b: Bindings, env: NapiEnv, value: NapiValue, tag: NapiTypeTag
) raises:
    var t = NapiTypeTag(tag.lower, tag.upper)
    var tag_ptr: OpaquePointer[ImmutAnyOrigin] = Pointer(
        to=t
    ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
    check_status(raw_type_tag_object(b, env, value, tag_ptr))


## check_object_type_tag — does the object carry exactly this tag?
##
## Returns False for untagged objects and objects tagged with a different
## tag. Raises (napi_object_expected) if `value` is not an object.
def check_object_type_tag(
    b: Bindings, env: NapiEnv, value: NapiValue, tag: NapiTypeTag
) raises -> Bool:
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
## raising, so the caller's cleanup path cannot double-free against the
## finalizer.
##
## The finalize_hint passed to the finalizer is the cached-bindings pointer
## (alive for the env's whole lifetime — allocated at module init, never
## freed), so a finalizer that needs N-API can recover cached bindings via
## bindings_from_context(hint) instead of the per-call OwnedDLHandle path.
def wrap_native(
    b: Bindings,
    env: NapiEnv,
    this_val: NapiValue,
    data_ptr: NapiStore,
    finalize_ptr: OpaquePointer[MutAnyOrigin],
    tag: NapiTypeTag,
) raises:
    check_status(
        raw_wrap(
            b,
            env,
            this_val,
            data_ptr,
            finalize_ptr,
            b.unsafe_bitcast[NoneType](),  # finalize_hint = cached bindings
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
        raise e^


def unwrap_native[
    T: AnyType
](b: Bindings, env: NapiEnv, info: NapiValue) raises -> Pointer[
    T, MutAnyOrigin
]:
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
    var this_val = CbArgs.get_this(b, env, info)
    return unwrap_native_from_this[T](b, env, this_val, tag)


def unwrap_native_from_this[
    T: AnyType
](
    b: Bindings, env: NapiEnv, this_val: NapiValue, tag: NapiTypeTag
) raises -> Pointer[T, MutAnyOrigin]:
    if not check_object_type_tag(b, env, this_val, tag):
        throw_js_type_error(
            b, env, "native type mismatch: object was not created by this class"
        )
        raise Error("unwrap: type tag mismatch")
    return unwrap_native_from_this[T](b, env, this_val)
