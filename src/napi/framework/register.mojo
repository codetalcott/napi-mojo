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

from memory import alloc
from napi.types import NapiEnv, NapiValue, NapiPropertyDescriptor, NapiRef
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
from napi.framework.js_ref import JsRef
from napi.raw import raw_new_instance, raw_define_properties
from napi.error import check_status

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


## ModuleBuilder — chainable module registration with batched flush
##
## Wraps env + exports + optional data pointer. When data is set (e.g., to
## a NapiBindings pointer), it is attached to every property descriptor so
## callbacks can retrieve it via CbArgs.get_bindings(env, info).
##
## method() accumulates NapiPropertyDescriptors into a heap array instead of
## calling napi_define_properties immediately. Call flush() once after all
## method() calls to register everything in a single N-API call — reducing
## ~90 individual napi_define_properties calls to 1 during module init.
## Maximum descriptors ModuleBuilder can hold before flush().
## Increase if a single module registers more than this many exports.
alias MAX_DESCRIPTORS: Int = 128

struct ModuleBuilder(Movable):
    var env: NapiEnv
    var exports: NapiValue
    var data: OpaquePointer[MutAnyOrigin]
    var _descs: UnsafePointer[NapiPropertyDescriptor, MutAnyOrigin]
    var _count: Int
    var _capacity: Int

    fn __init__(out self, env: NapiEnv, exports: NapiValue):
        self.env = env
        self.exports = exports
        self.data = OpaquePointer[MutAnyOrigin]()
        self._descs = alloc[NapiPropertyDescriptor](MAX_DESCRIPTORS)
        self._count = 0
        self._capacity = MAX_DESCRIPTORS

    fn __init__(out self, env: NapiEnv, exports: NapiValue, data: OpaquePointer[MutAnyOrigin]):
        self.env = env
        self.exports = exports
        self.data = data
        self._descs = alloc[NapiPropertyDescriptor](MAX_DESCRIPTORS)
        self._count = 0
        self._capacity = MAX_DESCRIPTORS

    fn __moveinit__(out self, deinit take: Self):
        self.env = take.env
        self.exports = take.exports
        self.data = take.data
        self._descs = take._descs
        self._count = take._count
        self._capacity = take._capacity

    ## method — accumulate a named method descriptor (flushed by flush())
    ##
    ## Sets desc.data = self.data so the callback can retrieve bindings.
    fn method(mut self, name: StringLiteral, ptr: OpaquePointer[MutAnyOrigin]) raises:
        if self._count >= self._capacity:
            raise Error("ModuleBuilder: descriptor capacity exceeded (max " + String(MAX_DESCRIPTORS) + ")")
        var desc = NapiPropertyDescriptor()
        desc.utf8name = name.unsafe_ptr().bitcast[NoneType]()
        desc.method = ptr
        desc.data = self.data
        desc.attributes = 0
        (self._descs + self._count).init_pointee_move(desc^)
        self._count += 1

    fn method(mut self, b: Bindings, name: StringLiteral, ptr: OpaquePointer[MutAnyOrigin]) raises:
        if self._count >= self._capacity:
            raise Error("ModuleBuilder: descriptor capacity exceeded (max " + String(MAX_DESCRIPTORS) + ")")
        var desc = NapiPropertyDescriptor()
        desc.utf8name = name.unsafe_ptr().bitcast[NoneType]()
        desc.method = ptr
        desc.data = self.data
        desc.attributes = 0
        (self._descs + self._count).init_pointee_move(desc^)
        self._count += 1

    ## flush — register all accumulated method descriptors in one N-API call
    ##
    ## Must be called exactly once after all method() calls. Frees the internal
    ## heap array. The fn_ref vars in the caller must remain alive until after
    ## flush() returns (ASAP safety — StringLiteral names are static lifetime).
    fn flush(mut self) raises:
        if self._count == 0:
            self._descs.free()
            return
        check_status(raw_define_properties(
            self.env, self.exports, UInt(self._count),
            UnsafePointer(to=self._descs[0]).bitcast[NoneType](),
        ))
        self._descs.free()
        self._count = 0

    fn flush(mut self, b: Bindings) raises:
        if self._count == 0:
            self._descs.free()
            return
        check_status(raw_define_properties(
            b, self.env, self.exports, UInt(self._count),
            UnsafePointer(to=self._descs[0]).bitcast[NoneType](),
        ))
        self._descs.free()
        self._count = 0

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


## ClassEntry — one slot in a ClassRegistry
##
## Stores the .rodata pointer + byte length from a StringLiteral name,
## plus a NapiRef handle that keeps the constructor alive.
## Fields are all primitive types (pointers + Int) so no destructor needed.
struct ClassEntry(Movable):
    var name_ptr: OpaquePointer[ImmutAnyOrigin]  # StringLiteral .rodata pointer
    var name_len: Int
    var ctor_ref: NapiRef

    fn __init__(out self):
        self.name_ptr = OpaquePointer[ImmutAnyOrigin]()
        self.name_len = 0
        self.ctor_ref = NapiRef()

    fn __moveinit__(out self, deinit take: Self):
        self.name_ptr = take.name_ptr
        self.name_len = take.name_len
        self.ctor_ref = take.ctor_ref


## ClassRegistry — stores class constructor refs keyed by StringLiteral name
##
## Allocates a fixed-capacity heap array (16 slots) at init time.
## Use register() after each class_def() call, then new_instance() in callbacks.
##
## Intended for module-lifetime usage — the backing array and NapiRefs are
## never freed (process exit handles cleanup).
##
## Usage:
##   var reg = ClassRegistry()
##   reg.register(b, env, "Counter", counter_builder.ctor)
##   # ... in a callback:
##   var inst = reg.new_instance(b, env, "Counter", 1, argv_ptr)
struct ClassRegistry(Movable):
    var _entries: UnsafePointer[ClassEntry, MutAnyOrigin]
    var _count: Int

    fn __init__(out self):
        self._entries = alloc[ClassEntry](16)
        self._count = 0

    fn __moveinit__(out self, deinit take: Self):
        self._entries = take._entries
        self._count = take._count

    ## register — store a strong NapiRef to a constructor, keyed by name
    fn register(mut self, b: Bindings, env: NapiEnv, name: StringLiteral, ctor: NapiValue) raises:
        if self._count >= 16:
            raise Error("ClassRegistry: capacity exceeded (max 16 classes)")
        var entry = ClassEntry()
        entry.name_ptr = name.unsafe_ptr().bitcast[NoneType]()
        entry.name_len = name.byte_length()
        entry.ctor_ref = JsRef.create(b, env, ctor, 1).handle
        (self._entries + self._count).init_pointee_move(entry^)
        self._count += 1

    ## new_instance — call `new ClassName(args)` from Mojo code
    ##
    ## Looks up the constructor by byte-comparing the StringLiteral name,
    ## then calls napi_new_instance. Raises if the class is not registered.
    fn new_instance(
        self,
        b: Bindings,
        env: NapiEnv,
        name: StringLiteral,
        argc: UInt,
        argv: OpaquePointer[ImmutAnyOrigin],
    ) raises -> NapiValue:
        var target_len = name.byte_length()
        var target_ptr = name.unsafe_ptr()
        for i in range(self._count):
            var stored_len = (self._entries + i)[].name_len
            var stored_ptr = (self._entries + i)[].name_ptr
            if stored_len == target_len:
                var name_match = True
                var s_bytes = stored_ptr.bitcast[UInt8]()
                for j in range(stored_len):
                    if s_bytes[j] != target_ptr[j]:
                        name_match = False
                        break
                if name_match:
                    var stored_ref = (self._entries + i)[].ctor_ref
                    var ctor_val = JsRef(stored_ref).get(b, env)
                    var result = NapiValue()
                    check_status(raw_new_instance(
                        b, env, ctor_val, argc, argv,
                        UnsafePointer(to=result).bitcast[NoneType](),
                    ))
                    return result
        raise Error("ClassRegistry: class not found")
