## src/napi/framework/register.mojo — ergonomic helpers for module & class registration
##
## Provides fn_ptr(), ModuleBuilder, and ClassBuilder to reduce the per-function
## boilerplate in register_module from ~4 lines to ~2 lines.
##
## Usage:
##   var m = ModuleBuilder(env, exports)
##   var hello_ref = hello_fn
##   m.method("hello", fn_ptr(hello_ref))
##
##   var ctor_ref = counter_constructor_fn
##   var c = m.class_def("Counter", fn_ptr(ctor_ref))
##   var inc_ref = counter_increment_fn
##   c.instance_method("increment", fn_ptr(inc_ref))

from napi.types import NapiEnv, NapiValue
from napi.bindings import Bindings
from napi.module import register_method
from napi.framework.js_class import (
    define_class,
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
## Wraps env + exports and provides a clean .method() call for each export.
struct ModuleBuilder:
    var env: NapiEnv
    var exports: NapiValue

    fn __init__(out self, env: NapiEnv, exports: NapiValue):
        self.env = env
        self.exports = exports

    ## method — register a named method on exports
    fn method(self, name: StringLiteral, ptr: OpaquePointer[MutAnyOrigin]) raises:
        register_method(self.env, self.exports, name, ptr)

    fn method(self, b: Bindings, name: StringLiteral, ptr: OpaquePointer[MutAnyOrigin]) raises:
        register_method(b, self.env, self.exports, name, ptr)

    ## class_def — define a class and attach it to exports, returns ClassBuilder
    fn class_def(self, name: StringLiteral, ctor_ptr: OpaquePointer[MutAnyOrigin]) raises -> ClassBuilder:
        var ctor = define_class(self.env, name, ctor_ptr)
        JsObject(self.exports).set_property(self.env, name, ctor)
        return ClassBuilder(self.env, ctor)

    fn class_def(self, b: Bindings, name: StringLiteral, ctor_ptr: OpaquePointer[MutAnyOrigin]) raises -> ClassBuilder:
        var ctor = define_class(b, self.env, name, ctor_ptr)
        JsObject(self.exports).set_property(self.env, name, ctor)
        return ClassBuilder(self.env, ctor)


## ClassBuilder — chainable class member registration
##
## Returned by ModuleBuilder.class_def(). Provides methods to add instance
## methods, getters, setters, and static members to a class.
struct ClassBuilder:
    var env: NapiEnv
    var ctor: NapiValue

    fn __init__(out self, env: NapiEnv, ctor: NapiValue):
        self.env = env
        self.ctor = ctor

    ## instance_method — add an instance method to the class prototype
    fn instance_method(self, name: StringLiteral, ptr: OpaquePointer[MutAnyOrigin]) raises:
        register_instance_method(self.env, self.ctor, name, ptr)

    fn instance_method(self, b: Bindings, name: StringLiteral, ptr: OpaquePointer[MutAnyOrigin]) raises:
        register_instance_method(b, self.env, self.ctor, name, ptr)

    ## getter — add a read-only getter to the class prototype
    fn getter(self, name: StringLiteral, ptr: OpaquePointer[MutAnyOrigin]) raises:
        register_getter(self.env, self.ctor, name, ptr)

    fn getter(self, b: Bindings, name: StringLiteral, ptr: OpaquePointer[MutAnyOrigin]) raises:
        register_getter(b, self.env, self.ctor, name, ptr)

    ## getter_setter — add a getter+setter pair to the class prototype
    fn getter_setter(
        self,
        name: StringLiteral,
        get_ptr: OpaquePointer[MutAnyOrigin],
        set_ptr: OpaquePointer[MutAnyOrigin],
    ) raises:
        register_getter_setter(self.env, self.ctor, name, get_ptr, set_ptr)

    fn getter_setter(
        self,
        b: Bindings,
        name: StringLiteral,
        get_ptr: OpaquePointer[MutAnyOrigin],
        set_ptr: OpaquePointer[MutAnyOrigin],
    ) raises:
        register_getter_setter(b, self.env, self.ctor, name, get_ptr, set_ptr)

    ## static_method — add a static method to the constructor
    fn static_method(self, name: StringLiteral, ptr: OpaquePointer[MutAnyOrigin]) raises:
        register_static_method(self.env, self.ctor, name, ptr)

    fn static_method(self, b: Bindings, name: StringLiteral, ptr: OpaquePointer[MutAnyOrigin]) raises:
        register_static_method(b, self.env, self.ctor, name, ptr)

    ## static_getter — add a read-only static getter to the constructor
    fn static_getter(self, name: StringLiteral, ptr: OpaquePointer[MutAnyOrigin]) raises:
        register_static_getter(self.env, self.ctor, name, ptr)

    fn static_getter(self, b: Bindings, name: StringLiteral, ptr: OpaquePointer[MutAnyOrigin]) raises:
        register_static_getter(b, self.env, self.ctor, name, ptr)

    ## static_getter_setter — add a static getter+setter pair to the constructor
    fn static_getter_setter(
        self,
        name: StringLiteral,
        get_ptr: OpaquePointer[MutAnyOrigin],
        set_ptr: OpaquePointer[MutAnyOrigin],
    ) raises:
        register_static_getter_setter(self.env, self.ctor, name, get_ptr, set_ptr)

    fn static_getter_setter(
        self,
        b: Bindings,
        name: StringLiteral,
        get_ptr: OpaquePointer[MutAnyOrigin],
        set_ptr: OpaquePointer[MutAnyOrigin],
    ) raises:
        register_static_getter_setter(b, self.env, self.ctor, name, get_ptr, set_ptr)

    ## inherits — set up prototype chain inheritance from parent class
    fn inherits(self, parent: ClassBuilder) raises:
        set_class_prototype(self.env, self.ctor, parent.ctor)

    fn inherits(self, b: Bindings, parent: ClassBuilder) raises:
        set_class_prototype(b, self.env, self.ctor, parent.ctor)
