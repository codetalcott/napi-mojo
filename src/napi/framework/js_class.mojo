## src/napi/framework/js_class.mojo — helpers for registering Mojo-backed JS classes
##
## Uses the one-property-at-a-time pattern (consistent with register_method).
## Call define_class() first, then add methods/getters/setters to the returned
## constructor napi_value. Instance properties go on the prototype (retrieved
## via constructor.prototype).

from napi.types import NapiEnv, NapiValue, NapiPropertyDescriptor
from napi.raw import raw_define_class, raw_define_properties, raw_get_named_property
from napi.error import check_status
from napi.module import define_property

## _get_prototype — get constructor.prototype as a napi_value
fn _get_prototype(env: NapiEnv, constructor: NapiValue) raises -> NapiValue:
    var proto = NapiValue()
    check_status(raw_get_named_property(
        env, constructor,
        "prototype".unsafe_ptr().bitcast[NoneType](),
        UnsafePointer(to=proto).bitcast[NoneType](),
    ))
    return proto

## define_class — register a class, returning the constructor napi_value
##
## Calls napi_define_class with property_count=0 (bare constructor).
## Instance methods/getters are added afterward via register_instance_method().
fn define_class(
    env: NapiEnv,
    name: StringLiteral,
    constructor_ptr: OpaquePointer[MutAnyOrigin],
) raises -> NapiValue:
    var result = NapiValue()
    # NAPI_AUTO_LENGTH = SIZE_MAX tells N-API to use strlen on the name
    var auto_length: UInt = ~UInt(0)
    check_status(raw_define_class(
        env,
        name.unsafe_ptr().bitcast[NoneType](),
        auto_length,
        constructor_ptr,
        OpaquePointer[MutAnyOrigin](),    # data = NULL
        0,                                 # property_count = 0
        OpaquePointer[ImmutAnyOrigin](),  # properties = NULL
        UnsafePointer(to=result).bitcast[NoneType](),
    ))
    return result

## register_instance_method — add an instance method to a class's prototype
fn register_instance_method(
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

## register_getter — add a read-only getter to a class's prototype
fn register_getter(
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

## register_getter_setter — add a getter+setter pair to a class's prototype
fn register_getter_setter(
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

## register_static_method — add a static method directly to the constructor
##
## Unlike register_instance_method (which targets the prototype), this applies
## the property descriptor to the constructor itself. The method appears as
## Class.method() and is NOT available on instances.
fn register_static_method(
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

## register_static_getter — add a read-only static getter to a class
fn register_static_getter(
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

## register_static_getter_setter — add a static getter+setter pair to a class
fn register_static_getter_setter(
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
