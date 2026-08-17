## src/napi/framework/js_class.mojo — helpers for registering Mojo-backed JS classes
##
## Uses the one-property-at-a-time pattern (consistent with register_method).
## Call define_class() first, then add methods/getters/setters to the returned
## constructor napi_value. Instance properties go on the prototype (retrieved
## via constructor.prototype).

from napi.types import NapiEnv, NapiValue, NapiPropertyDescriptor, NapiTypeTag
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


## _get_prototype — get constructor.prototype as a napi_value
def _get_prototype(env: NapiEnv, constructor: NapiValue) raises -> NapiValue:
    var proto = NapiValue(unsafe_from_address=Int(0))
    check_status(
        raw_get_named_property(
            env,
            constructor,
            "prototype".unsafe_ptr().unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            Pointer(to=proto).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
        )
    )
    return proto


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


## define_class — register a class, returning the constructor napi_value
##
## Calls napi_define_class with property_count=0 (bare constructor).
## Instance methods/getters are added afterward via register_instance_method().
def define_class(
    env: NapiEnv,
    name: StringLiteral,
    constructor_ptr: OpaquePointer[MutAnyOrigin],
) raises -> NapiValue:
    var result = NapiValue(unsafe_from_address=Int(0))
    # NAPI_AUTO_LENGTH = SIZE_MAX tells N-API to use strlen on the name
    var auto_length: UInt = ~UInt(0)
    check_status(
        raw_define_class(
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


## define_class with data — pass data pointer to the constructor callback
def define_class(
    env: NapiEnv,
    name: StringLiteral,
    constructor_ptr: OpaquePointer[MutAnyOrigin],
    data_ptr: OpaquePointer[MutAnyOrigin],
) raises -> NapiValue:
    var result = NapiValue(unsafe_from_address=Int(0))
    var auto_length: UInt = ~UInt(0)
    check_status(
        raw_define_class(
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
    data_ptr: OpaquePointer[MutAnyOrigin],
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


## register_instance_method — add an instance method to a class's prototype
def register_instance_method(
    env: NapiEnv,
    constructor: NapiValue,
    name: StringLiteral,
    method_ptr: OpaquePointer[MutAnyOrigin],
) raises:
    var proto = _get_prototype(env, constructor)
    var desc = NapiPropertyDescriptor()
    desc.utf8name = name.unsafe_ptr().unsafe_bitcast[NoneType]().as_unsafe_any_origin()
    desc.method = method_ptr
    desc.attributes = 0
    define_property(env, proto, desc)


def register_instance_method(
    b: Bindings,
    env: NapiEnv,
    constructor: NapiValue,
    name: StringLiteral,
    method_ptr: OpaquePointer[MutAnyOrigin],
) raises:
    var proto = _get_prototype(b, env, constructor)
    var desc = NapiPropertyDescriptor()
    desc.utf8name = name.unsafe_ptr().unsafe_bitcast[NoneType]().as_unsafe_any_origin()
    desc.method = method_ptr
    desc.attributes = 0
    define_property(b, env, proto, desc)


## register_getter — add a read-only getter to a class's prototype
def register_getter(
    env: NapiEnv,
    constructor: NapiValue,
    name: StringLiteral,
    getter_ptr: OpaquePointer[MutAnyOrigin],
) raises:
    var proto = _get_prototype(env, constructor)
    var desc = NapiPropertyDescriptor()
    desc.utf8name = name.unsafe_ptr().unsafe_bitcast[NoneType]().as_unsafe_any_origin()
    desc.getter = getter_ptr
    desc.attributes = 0
    define_property(env, proto, desc)


def register_getter(
    b: Bindings,
    env: NapiEnv,
    constructor: NapiValue,
    name: StringLiteral,
    getter_ptr: OpaquePointer[MutAnyOrigin],
) raises:
    var proto = _get_prototype(b, env, constructor)
    var desc = NapiPropertyDescriptor()
    desc.utf8name = name.unsafe_ptr().unsafe_bitcast[NoneType]().as_unsafe_any_origin()
    desc.getter = getter_ptr
    desc.attributes = 0
    define_property(b, env, proto, desc)


## register_getter_setter — add a getter+setter pair to a class's prototype
def register_getter_setter(
    env: NapiEnv,
    constructor: NapiValue,
    name: StringLiteral,
    getter_ptr: OpaquePointer[MutAnyOrigin],
    setter_ptr: OpaquePointer[MutAnyOrigin],
) raises:
    var proto = _get_prototype(env, constructor)
    var desc = NapiPropertyDescriptor()
    desc.utf8name = name.unsafe_ptr().unsafe_bitcast[NoneType]().as_unsafe_any_origin()
    desc.getter = getter_ptr
    desc.setter = setter_ptr
    desc.attributes = 0
    define_property(env, proto, desc)


def register_getter_setter(
    b: Bindings,
    env: NapiEnv,
    constructor: NapiValue,
    name: StringLiteral,
    getter_ptr: OpaquePointer[MutAnyOrigin],
    setter_ptr: OpaquePointer[MutAnyOrigin],
) raises:
    var proto = _get_prototype(b, env, constructor)
    var desc = NapiPropertyDescriptor()
    desc.utf8name = name.unsafe_ptr().unsafe_bitcast[NoneType]().as_unsafe_any_origin()
    desc.getter = getter_ptr
    desc.setter = setter_ptr
    desc.attributes = 0
    define_property(b, env, proto, desc)


## register_static_method — add a static method directly to the constructor
##
## Unlike register_instance_method (which targets the prototype), this applies
## the property descriptor to the constructor itself. The method appears as
## Class.method() and is NOT available on instances.
def register_static_method(
    env: NapiEnv,
    constructor: NapiValue,
    name: StringLiteral,
    method_ptr: OpaquePointer[MutAnyOrigin],
) raises:
    var desc = NapiPropertyDescriptor()
    desc.utf8name = name.unsafe_ptr().unsafe_bitcast[NoneType]().as_unsafe_any_origin()
    desc.method = method_ptr
    desc.attributes = 0
    define_property(env, constructor, desc)


def register_static_method(
    b: Bindings,
    env: NapiEnv,
    constructor: NapiValue,
    name: StringLiteral,
    method_ptr: OpaquePointer[MutAnyOrigin],
) raises:
    var desc = NapiPropertyDescriptor()
    desc.utf8name = name.unsafe_ptr().unsafe_bitcast[NoneType]().as_unsafe_any_origin()
    desc.method = method_ptr
    desc.attributes = 0
    define_property(b, env, constructor, desc)


## register_static_getter — add a read-only static getter to a class
def register_static_getter(
    env: NapiEnv,
    constructor: NapiValue,
    name: StringLiteral,
    getter_ptr: OpaquePointer[MutAnyOrigin],
) raises:
    var desc = NapiPropertyDescriptor()
    desc.utf8name = name.unsafe_ptr().unsafe_bitcast[NoneType]().as_unsafe_any_origin()
    desc.getter = getter_ptr
    desc.attributes = 0
    define_property(env, constructor, desc)


def register_static_getter(
    b: Bindings,
    env: NapiEnv,
    constructor: NapiValue,
    name: StringLiteral,
    getter_ptr: OpaquePointer[MutAnyOrigin],
) raises:
    var desc = NapiPropertyDescriptor()
    desc.utf8name = name.unsafe_ptr().unsafe_bitcast[NoneType]().as_unsafe_any_origin()
    desc.getter = getter_ptr
    desc.attributes = 0
    define_property(b, env, constructor, desc)


## set_class_prototype — set up inheritance: Dog.prototype.__proto__ = Animal.prototype
##
## Uses Object.setPrototypeOf(childProto, parentProto) via JS global.
## Works on all Node versions with N-API (no node_api_set_prototype needed).
def set_class_prototype(
    env: NapiEnv,
    child_ctor: NapiValue,
    parent_ctor: NapiValue,
) raises:
    var child_proto = _get_prototype(env, child_ctor)
    var parent_proto = _get_prototype(env, parent_ctor)

    # Get Object.setPrototypeOf from the global object
    var global_obj = js_get_global(env)
    var object_key = NapiValue(unsafe_from_address=Int(0))
    check_status(
        raw_get_named_property(
            env,
            global_obj.value,
            "Object".unsafe_ptr().unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            Pointer(to=object_key).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
        )
    )
    var set_proto_of = NapiValue(unsafe_from_address=Int(0))
    check_status(
        raw_get_named_property(
            env,
            object_key,
            "setPrototypeOf".unsafe_ptr().unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            Pointer(to=set_proto_of).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
        )
    )

    # Call Object.setPrototypeOf(childProto, parentProto)
    _ = JsFunction(set_proto_of).call2(env, child_proto, parent_proto)


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


## register_static_getter_setter — add a static getter+setter pair to a class
def register_static_getter_setter(
    env: NapiEnv,
    constructor: NapiValue,
    name: StringLiteral,
    getter_ptr: OpaquePointer[MutAnyOrigin],
    setter_ptr: OpaquePointer[MutAnyOrigin],
) raises:
    var desc = NapiPropertyDescriptor()
    desc.utf8name = name.unsafe_ptr().unsafe_bitcast[NoneType]().as_unsafe_any_origin()
    desc.getter = getter_ptr
    desc.setter = setter_ptr
    desc.attributes = 0
    define_property(env, constructor, desc)


def register_static_getter_setter(
    b: Bindings,
    env: NapiEnv,
    constructor: NapiValue,
    name: StringLiteral,
    getter_ptr: OpaquePointer[MutAnyOrigin],
    setter_ptr: OpaquePointer[MutAnyOrigin],
) raises:
    var desc = NapiPropertyDescriptor()
    desc.utf8name = name.unsafe_ptr().unsafe_bitcast[NoneType]().as_unsafe_any_origin()
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
def wrap_native(
    b: Bindings,
    env: NapiEnv,
    this_val: NapiValue,
    data_ptr: OpaquePointer[MutAnyOrigin],
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
            OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0)),
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


## unwrap_native — extract the wrapped native pointer from `this` and cast it
##
## Replaces the 4-line unwrap dance in every class method callback:
##   var this_val = CbArgs.get_this(env, info)
##   var data = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
##   check_status(raw_unwrap(env, this_val, ...))
##   var ptr = data.unsafe_bitcast[T]()
##
## Usage:
##   var ptr = unwrap_native[CounterData](env, info)
##   return JsNumber.create(env, ptr[].count).value
##
## UNVERIFIED: this overload does not check WHICH class wrapped the pointer —
## napi_unwrap succeeds for any wrapped object, so a method borrowed onto a
## foreign instance reinterprets the wrong struct. Prefer the tag-verified
## overloads (wrap with wrap_native, unwrap with the NapiTypeTag-taking
## overloads below). Use this form only after an explicit
## check_object_type_tag accept-set test, e.g. for inherited methods where
## `this` may legitimately carry one of several layout-compatible tags.
def unwrap_native[
    T: AnyType
](env: NapiEnv, info: NapiValue) raises -> Pointer[T, MutAnyOrigin]:
    var this_val = CbArgs.get_this(env, info)
    var data: Optional[OpaquePointer[MutAnyOrigin]] = None
    check_status(
        raw_unwrap(
            env, this_val, Pointer(to=data).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        )
    )
    if data is None:
        raise Error("unwrap failed: NULL native pointer")
    return data.value().unsafe_bitcast[T]()


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
