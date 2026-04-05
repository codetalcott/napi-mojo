## src/napi/framework/js_class.mojo — helpers for registering Mojo-backed JS classes
##
## Uses the one-property-at-a-time pattern (consistent with register_method).
## Call define_class() first, then add methods/getters/setters to the returned
## constructor napi_value. Instance properties go on the prototype (retrieved
## via constructor.prototype).

from napi.types import NapiEnv, NapiValue, NapiPropertyDescriptor
from napi.bindings import Bindings
from napi.raw import (
    raw_define_class,
    raw_define_properties,
    raw_get_named_property,
    raw_unwrap,
)
from napi.error import check_status
from napi.framework.args import CbArgs
from napi.module import define_property
from napi.framework.js_value import js_get_global
from napi.framework.js_function import JsFunction


## _get_prototype — get constructor.prototype as a napi_value
def _get_prototype(env: NapiEnv, constructor: NapiValue) raises -> NapiValue:
    var proto = NapiValue()
    check_status(
        raw_get_named_property(
            env,
            constructor,
            "prototype".unsafe_ptr().bitcast[NoneType](),
            UnsafePointer(to=proto).bitcast[NoneType](),
        )
    )
    return proto


def _get_prototype(
    b: Bindings, env: NapiEnv, constructor: NapiValue
) raises -> NapiValue:
    var proto = NapiValue()
    check_status(
        raw_get_named_property(
            b,
            env,
            constructor,
            "prototype".unsafe_ptr().bitcast[NoneType](),
            UnsafePointer(to=proto).bitcast[NoneType](),
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
    var result = NapiValue()
    # NAPI_AUTO_LENGTH = SIZE_MAX tells N-API to use strlen on the name
    var auto_length: UInt = ~UInt(0)
    check_status(
        raw_define_class(
            env,
            name.unsafe_ptr().bitcast[NoneType](),
            auto_length,
            constructor_ptr,
            OpaquePointer[MutAnyOrigin](),  # data = NULL
            0,  # property_count = 0
            OpaquePointer[ImmutAnyOrigin](),  # properties = NULL
            UnsafePointer(to=result).bitcast[NoneType](),
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
    var result = NapiValue()
    var auto_length: UInt = ~UInt(0)
    check_status(
        raw_define_class(
            env,
            name.unsafe_ptr().bitcast[NoneType](),
            auto_length,
            constructor_ptr,
            data_ptr,
            0,
            OpaquePointer[ImmutAnyOrigin](),
            UnsafePointer(to=result).bitcast[NoneType](),
        )
    )
    return result


def define_class(
    b: Bindings,
    env: NapiEnv,
    name: StringLiteral,
    constructor_ptr: OpaquePointer[MutAnyOrigin],
) raises -> NapiValue:
    var result = NapiValue()
    var auto_length: UInt = ~UInt(0)
    check_status(
        raw_define_class(
            b,
            env,
            name.unsafe_ptr().bitcast[NoneType](),
            auto_length,
            constructor_ptr,
            OpaquePointer[MutAnyOrigin](),  # data = NULL
            0,  # property_count = 0
            OpaquePointer[ImmutAnyOrigin](),  # properties = NULL
            UnsafePointer(to=result).bitcast[NoneType](),
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
    var result = NapiValue()
    var auto_length: UInt = ~UInt(0)
    check_status(
        raw_define_class(
            b,
            env,
            name.unsafe_ptr().bitcast[NoneType](),
            auto_length,
            constructor_ptr,
            data_ptr,
            0,
            OpaquePointer[ImmutAnyOrigin](),
            UnsafePointer(to=result).bitcast[NoneType](),
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
    desc.utf8name = name.unsafe_ptr().bitcast[NoneType]()
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
    desc.utf8name = name.unsafe_ptr().bitcast[NoneType]()
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
    desc.utf8name = name.unsafe_ptr().bitcast[NoneType]()
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
    desc.utf8name = name.unsafe_ptr().bitcast[NoneType]()
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
    desc.utf8name = name.unsafe_ptr().bitcast[NoneType]()
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
    desc.utf8name = name.unsafe_ptr().bitcast[NoneType]()
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
    desc.utf8name = name.unsafe_ptr().bitcast[NoneType]()
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
    desc.utf8name = name.unsafe_ptr().bitcast[NoneType]()
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
    desc.utf8name = name.unsafe_ptr().bitcast[NoneType]()
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
    desc.utf8name = name.unsafe_ptr().bitcast[NoneType]()
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
    var object_key = NapiValue()
    check_status(
        raw_get_named_property(
            env,
            global_obj.value,
            "Object".unsafe_ptr().bitcast[NoneType](),
            UnsafePointer(to=object_key).bitcast[NoneType](),
        )
    )
    var set_proto_of = NapiValue()
    check_status(
        raw_get_named_property(
            env,
            object_key,
            "setPrototypeOf".unsafe_ptr().bitcast[NoneType](),
            UnsafePointer(to=set_proto_of).bitcast[NoneType](),
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
    var object_key = NapiValue()
    check_status(
        raw_get_named_property(
            b,
            env,
            global_obj.value,
            "Object".unsafe_ptr().bitcast[NoneType](),
            UnsafePointer(to=object_key).bitcast[NoneType](),
        )
    )
    var set_proto_of = NapiValue()
    check_status(
        raw_get_named_property(
            b,
            env,
            object_key,
            "setPrototypeOf".unsafe_ptr().bitcast[NoneType](),
            UnsafePointer(to=set_proto_of).bitcast[NoneType](),
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
    desc.utf8name = name.unsafe_ptr().bitcast[NoneType]()
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
    desc.utf8name = name.unsafe_ptr().bitcast[NoneType]()
    desc.getter = getter_ptr
    desc.setter = setter_ptr
    desc.attributes = 0
    define_property(b, env, constructor, desc)


## unwrap_native — extract the wrapped native pointer from `this` and cast it
##
## Replaces the 4-line unwrap dance in every class method callback:
##   var this_val = CbArgs.get_this(env, info)
##   var data = OpaquePointer[MutAnyOrigin]()
##   check_status(raw_unwrap(env, this_val, ...))
##   var ptr = data.bitcast[T]()
##
## Usage:
##   var ptr = unwrap_native[CounterData](env, info)
##   return JsNumber.create(env, ptr[].count).value
def unwrap_native[
    T: AnyType
](env: NapiEnv, info: NapiValue) raises -> UnsafePointer[T, MutAnyOrigin]:
    var this_val = CbArgs.get_this(env, info)
    var data = OpaquePointer[MutAnyOrigin]()
    check_status(
        raw_unwrap(env, this_val, UnsafePointer(to=data).bitcast[NoneType]())
    )
    if not data:
        raise Error("unwrap failed: NULL native pointer")
    return data.bitcast[T]()


def unwrap_native[
    T: AnyType
](b: Bindings, env: NapiEnv, info: NapiValue) raises -> UnsafePointer[
    T, MutAnyOrigin
]:
    var this_val = CbArgs.get_this(env, info)
    var data = OpaquePointer[MutAnyOrigin]()
    check_status(
        raw_unwrap(b, env, this_val, UnsafePointer(to=data).bitcast[NoneType]())
    )
    if not data:
        raise Error("unwrap failed: NULL native pointer")
    return data.bitcast[T]()


## unwrap_native_from_this — unwrap using a pre-extracted this_val
##
## Use when this_val was already retrieved via get_bindings_and_this or
## get_bindings_this_and_one, avoiding a second napi_get_cb_info call.
## Distinct name required: same type signature as unwrap_native[T](b, env, info).
def unwrap_native_from_this[
    T: AnyType
](b: Bindings, env: NapiEnv, this_val: NapiValue) raises -> UnsafePointer[
    T, MutAnyOrigin
]:
    var data = OpaquePointer[MutAnyOrigin]()
    check_status(
        raw_unwrap(b, env, this_val, UnsafePointer(to=data).bitcast[NoneType]())
    )
    if not data:
        raise Error("unwrap failed: NULL native pointer")
    return data.bitcast[T]()
