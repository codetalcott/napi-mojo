## src/napi/framework/register.mojo — ergonomic helpers for module & class registration
##
## Provides fn_ptr(), ModuleBuilder, and ClassBuilder to reduce the per-function
## boilerplate in register_module from ~4 lines to ~2 lines.
##
## Usage:
##   var bindings_ptr = alloc[NapiBindings](1)
##   init_bindings(bindings_ptr[])
##   var data = bindings_ptr.bitcast[NoneType]()
##   var m = ModuleBuilder(env, exports, data)
##   var hello_ref = hello_fn
##   m.method("hello", fn_ptr(hello_ref))
##
##   var ctor_ref = counter_constructor_fn
##   var c = m.class_def("Counter", fn_ptr(ctor_ref))
##   var inc_ref = counter_increment_fn
##   c.instance_method("increment", fn_ptr(inc_ref))

from napi.types import NapiEnv, NapiValue, NapiPropertyDescriptor
from napi.bindings import Bindings
from napi.module import register_method, define_property
from napi.framework.js_class import (
    define_class,
    _get_prototype,
    register_instance_method,
    register_getter,
    register_getter_setter,
    register_static_method,
    register_static_getter,
    register_static_getter_setter,
    set_class_prototype,
)
from napi.framework.js_object import JsObject

## fn_ptr — extract a callable function pointer from a function reference
##
## Replaces the verbose:
##   UnsafePointer(to=ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
## with:
##   fn_ptr(ref)
##
## The caller's var binding keeps the reference alive (ASAP safety).
fn fn_ptr[T: AnyType](func: T) -> OpaquePointer[MutAnyOrigin]:
    return UnsafePointer(to=func).bitcast[OpaquePointer[MutAnyOrigin]]()[]


## ModuleBuilder — chainable module registration
##
## Wraps env + exports + optional data pointer. When data is set (e.g., to
## a NapiBindings pointer), it is attached to every property descriptor so
## callbacks can retrieve it via CbArgs.get_bindings(env, info).
struct ModuleBuilder:
    var env: NapiEnv
    var exports: NapiValue
    var data: OpaquePointer[MutAnyOrigin]

    fn __init__(out self, env: NapiEnv, exports: NapiValue):
        self.env = env
        self.exports = exports
        self.data = OpaquePointer[MutAnyOrigin]()

    fn __init__(out self, env: NapiEnv, exports: NapiValue, data: OpaquePointer[MutAnyOrigin]):
        self.env = env
        self.exports = exports
        self.data = data

    ## method — register a named method on exports
    ##
    ## Sets desc.data = self.data so the callback can retrieve bindings.
    fn method(self, name: StringLiteral, ptr: OpaquePointer[MutAnyOrigin]) raises:
        var desc = NapiPropertyDescriptor()
        desc.utf8name = name.unsafe_ptr().bitcast[NoneType]()
        desc.method = ptr
        desc.data = self.data
        desc.attributes = 0
        define_property(self.env, self.exports, desc)

    fn method(self, b: Bindings, name: StringLiteral, ptr: OpaquePointer[MutAnyOrigin]) raises:
        var desc = NapiPropertyDescriptor()
        desc.utf8name = name.unsafe_ptr().bitcast[NoneType]()
        desc.method = ptr
        desc.data = self.data
        desc.attributes = 0
        define_property(b, self.env, self.exports, desc)

    ## class_def — define a class and attach it to exports, returns ClassBuilder
    fn class_def(self, name: StringLiteral, ctor_ptr: OpaquePointer[MutAnyOrigin]) raises -> ClassBuilder:
        var ctor = define_class(self.env, name, ctor_ptr, self.data)
        JsObject(self.exports).set_property(self.env, name, ctor)
        return ClassBuilder(self.env, ctor, self.data)

    fn class_def(self, b: Bindings, name: StringLiteral, ctor_ptr: OpaquePointer[MutAnyOrigin]) raises -> ClassBuilder:
        var ctor = define_class(b, self.env, name, ctor_ptr, self.data)
        JsObject(self.exports).set_property(self.env, name, ctor)
        return ClassBuilder(self.env, ctor, self.data)


## ClassBuilder — chainable class member registration
##
## Returned by ModuleBuilder.class_def(). Provides methods to add instance
## methods, getters, setters, and static members to a class. Sets desc.data
## on all property descriptors so callbacks get the bindings pointer.
struct ClassBuilder:
    var env: NapiEnv
    var ctor: NapiValue
    var data: OpaquePointer[MutAnyOrigin]

    fn __init__(out self, env: NapiEnv, ctor: NapiValue):
        self.env = env
        self.ctor = ctor
        self.data = OpaquePointer[MutAnyOrigin]()

    fn __init__(out self, env: NapiEnv, ctor: NapiValue, data: OpaquePointer[MutAnyOrigin]):
        self.env = env
        self.ctor = ctor
        self.data = data

    ## instance_method — add an instance method to the class prototype
    fn instance_method(self, name: StringLiteral, ptr: OpaquePointer[MutAnyOrigin]) raises:
        var proto = _get_prototype(self.env, self.ctor)
        var desc = NapiPropertyDescriptor()
        desc.utf8name = name.unsafe_ptr().bitcast[NoneType]()
        desc.method = ptr
        desc.data = self.data
        desc.attributes = 0
        define_property(self.env, proto, desc)

    fn instance_method(self, b: Bindings, name: StringLiteral, ptr: OpaquePointer[MutAnyOrigin]) raises:
        var proto = _get_prototype(b, self.env, self.ctor)
        var desc = NapiPropertyDescriptor()
        desc.utf8name = name.unsafe_ptr().bitcast[NoneType]()
        desc.method = ptr
        desc.data = self.data
        desc.attributes = 0
        define_property(b, self.env, proto, desc)

    ## getter — add a read-only getter to the class prototype
    fn getter(self, name: StringLiteral, ptr: OpaquePointer[MutAnyOrigin]) raises:
        var proto = _get_prototype(self.env, self.ctor)
        var desc = NapiPropertyDescriptor()
        desc.utf8name = name.unsafe_ptr().bitcast[NoneType]()
        desc.getter = ptr
        desc.data = self.data
        desc.attributes = 0
        define_property(self.env, proto, desc)

    fn getter(self, b: Bindings, name: StringLiteral, ptr: OpaquePointer[MutAnyOrigin]) raises:
        var proto = _get_prototype(b, self.env, self.ctor)
        var desc = NapiPropertyDescriptor()
        desc.utf8name = name.unsafe_ptr().bitcast[NoneType]()
        desc.getter = ptr
        desc.data = self.data
        desc.attributes = 0
        define_property(b, self.env, proto, desc)

    ## getter_setter — add a getter+setter pair to the class prototype
    fn getter_setter(
        self,
        name: StringLiteral,
        get_ptr: OpaquePointer[MutAnyOrigin],
        set_ptr: OpaquePointer[MutAnyOrigin],
    ) raises:
        var proto = _get_prototype(self.env, self.ctor)
        var desc = NapiPropertyDescriptor()
        desc.utf8name = name.unsafe_ptr().bitcast[NoneType]()
        desc.getter = get_ptr
        desc.setter = set_ptr
        desc.data = self.data
        desc.attributes = 0
        define_property(self.env, proto, desc)

    fn getter_setter(
        self,
        b: Bindings,
        name: StringLiteral,
        get_ptr: OpaquePointer[MutAnyOrigin],
        set_ptr: OpaquePointer[MutAnyOrigin],
    ) raises:
        var proto = _get_prototype(b, self.env, self.ctor)
        var desc = NapiPropertyDescriptor()
        desc.utf8name = name.unsafe_ptr().bitcast[NoneType]()
        desc.getter = get_ptr
        desc.setter = set_ptr
        desc.data = self.data
        desc.attributes = 0
        define_property(b, self.env, proto, desc)

    ## static_method — add a static method to the constructor
    fn static_method(self, name: StringLiteral, ptr: OpaquePointer[MutAnyOrigin]) raises:
        var desc = NapiPropertyDescriptor()
        desc.utf8name = name.unsafe_ptr().bitcast[NoneType]()
        desc.method = ptr
        desc.data = self.data
        desc.attributes = 0
        define_property(self.env, self.ctor, desc)

    fn static_method(self, b: Bindings, name: StringLiteral, ptr: OpaquePointer[MutAnyOrigin]) raises:
        var desc = NapiPropertyDescriptor()
        desc.utf8name = name.unsafe_ptr().bitcast[NoneType]()
        desc.method = ptr
        desc.data = self.data
        desc.attributes = 0
        define_property(b, self.env, self.ctor, desc)

    ## static_getter — add a read-only static getter to the constructor
    fn static_getter(self, name: StringLiteral, ptr: OpaquePointer[MutAnyOrigin]) raises:
        var desc = NapiPropertyDescriptor()
        desc.utf8name = name.unsafe_ptr().bitcast[NoneType]()
        desc.getter = ptr
        desc.data = self.data
        desc.attributes = 0
        define_property(self.env, self.ctor, desc)

    fn static_getter(self, b: Bindings, name: StringLiteral, ptr: OpaquePointer[MutAnyOrigin]) raises:
        var desc = NapiPropertyDescriptor()
        desc.utf8name = name.unsafe_ptr().bitcast[NoneType]()
        desc.getter = ptr
        desc.data = self.data
        desc.attributes = 0
        define_property(b, self.env, self.ctor, desc)

    ## static_getter_setter — add a static getter+setter pair to the constructor
    fn static_getter_setter(
        self,
        name: StringLiteral,
        get_ptr: OpaquePointer[MutAnyOrigin],
        set_ptr: OpaquePointer[MutAnyOrigin],
    ) raises:
        var desc = NapiPropertyDescriptor()
        desc.utf8name = name.unsafe_ptr().bitcast[NoneType]()
        desc.getter = get_ptr
        desc.setter = set_ptr
        desc.data = self.data
        desc.attributes = 0
        define_property(self.env, self.ctor, desc)

    fn static_getter_setter(
        self,
        b: Bindings,
        name: StringLiteral,
        get_ptr: OpaquePointer[MutAnyOrigin],
        set_ptr: OpaquePointer[MutAnyOrigin],
    ) raises:
        var desc = NapiPropertyDescriptor()
        desc.utf8name = name.unsafe_ptr().bitcast[NoneType]()
        desc.getter = get_ptr
        desc.setter = set_ptr
        desc.data = self.data
        desc.attributes = 0
        define_property(b, self.env, self.ctor, desc)

    ## inherits — set up prototype chain inheritance from parent class
    fn inherits(self, parent: ClassBuilder) raises:
        set_class_prototype(self.env, self.ctor, parent.ctor)

    fn inherits(self, b: Bindings, parent: ClassBuilder) raises:
        set_class_prototype(b, self.env, self.ctor, parent.ctor)
