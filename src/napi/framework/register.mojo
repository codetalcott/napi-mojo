## src/napi/framework/register.mojo — ergonomic helpers for module & class registration
##
## Provides fn_ptr(), ModuleBuilder, and ClassBuilder to reduce the per-function
## boilerplate in register_module from ~4 lines to ~2 lines.
##
## Usage:
##   var bindings_ptr = unsafe_alloc[NapiBindings](1)
##   init_bindings(bindings_ptr[])
##   var data = bindings_ptr.unsafe_bitcast[NoneType]()
##   var m = ModuleBuilder(env, exports, data)
##   var hello_ref = hello_fn
##   m.method("hello", fn_ptr(hello_ref))
##
##   var ctor_ref = counter_constructor_fn
##   var c = m.class_def("Counter", fn_ptr(ctor_ref))
##   var inc_ref = counter_increment_fn
##   c.instance_method("increment", fn_ptr(inc_ref))

from std.memory.alloc import unsafe_alloc
from napi.types import NapiEnv, NapiValue, NapiPropertyDescriptor, NapiRef
from napi.bindings import Bindings
from napi.framework.args import bindings_from_context
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
##   Pointer(to=ref).unsafe_bitcast[OpaquePointer[MutAnyOrigin]]()[]
## with:
##   fn_ptr(ref)
##
## The caller's var binding keeps the reference alive (ASAP safety).
def fn_ptr[T: AnyType](func: T) -> OpaquePointer[MutAnyOrigin]:
    return Pointer(to=func).unsafe_bitcast[OpaquePointer[MutAnyOrigin]]()[]


## ModuleBuilder — chainable module registration with batched flush
##
## Wraps env + exports + the NapiBindings data pointer. `data` MUST be the
## bindings pointer: it is attached to every property descriptor so callbacks
## can retrieve it via CbArgs.get_bindings(env, info), and flush()/class_def()
## and every ClassBuilder member derive cached bindings from it via
## bindings_from_context() (magic-checked; registration is init-time, so the
## one extra word read per call is free).
##
## method() accumulates NapiPropertyDescriptors into a heap array instead of
## calling napi_define_properties immediately. Call flush() once after all
## method() calls to register everything in a single N-API call — reducing
## ~90 individual napi_define_properties calls to 1 during module init.
## Maximum descriptors ModuleBuilder can hold before flush().
## Increase if a single module registers more than this many exports.
comptime MAX_DESCRIPTORS: Int = 192


struct ModuleBuilder(Movable):
    @__allow_legacy_any_origin_fields
    var env: NapiEnv
    @__allow_legacy_any_origin_fields
    var exports: NapiValue
    @__allow_legacy_any_origin_fields
    var data: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var _descs: Pointer[NapiPropertyDescriptor, MutAnyOrigin]
    var _count: Int
    var _capacity: Int

    def __init__(
        out self,
        env: NapiEnv,
        exports: NapiValue,
        data: OpaquePointer[MutAnyOrigin],
    ):
        self.env = env
        self.exports = exports
        self.data = data
        self._descs = unsafe_alloc[NapiPropertyDescriptor](MAX_DESCRIPTORS).as_unsafe_any_origin()
        self._count = 0
        self._capacity = MAX_DESCRIPTORS

    def __moveinit__(out self, deinit take: Self):
        self.env = take.env
        self.exports = take.exports
        self.data = take.data
        self._descs = take._descs
        self._count = take._count
        self._capacity = take._capacity

    ## method — accumulate a named method descriptor (flushed by flush())
    ##
    ## Sets desc.data = self.data so the callback can retrieve bindings.
    def method(
        mut self, name: StringLiteral, ptr: OpaquePointer[MutAnyOrigin]
    ) raises:
        if self._count >= self._capacity:
            raise Error(
                "ModuleBuilder: descriptor capacity exceeded (max "
                + String(MAX_DESCRIPTORS)
                + ")"
            )
        var desc = NapiPropertyDescriptor()
        desc.utf8name = name.unsafe_ptr().unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        desc.method = ptr
        desc.data = self.data
        desc.attributes = 0
        self._descs.unsafe_offset(self._count).unsafe_write(desc^)
        self._count += 1

    ## _free_descs — free the descriptor array exactly once
    ##
    ## Nulls the pointer afterwards so a second flush() (or __deinit__ after
    ## flush) is a no-op instead of a double-free. Pointers can't be
    ## null-checked with `if not ptr` anymore — use Int(ptr) == 0.
    def _free_descs(mut self):
        if Int(self._descs) != 0:
            self._descs.unsafe_free()
            self._descs = Pointer[NapiPropertyDescriptor, MutAnyOrigin](
                unsafe_from_address=Int(0)
            )

    ## flush — register all accumulated method descriptors in one N-API call
    ##
    ## Safe to call at most once meaningfully; a repeat call is a no-op.
    ## The descriptor array is freed on every exit path (including a failed
    ## napi_define_properties), and __deinit__ backstops the case where a
    ## register_* call raises before flush() is ever reached. The fn_ref vars
    ## in the caller must remain alive until after flush() returns (ASAP
    ## safety — StringLiteral names are static lifetime).
    def flush(mut self) raises:
        if Int(self._descs) == 0:
            return  # already flushed
        if self._count == 0:
            self._free_descs()
            return
        try:
            var b = bindings_from_context(self.data)
            check_status(
                raw_define_properties(
                    b,
                    self.env,
                    self.exports,
                    UInt(self._count),
                    Pointer(to=self._descs[unsafe_offset=0]).unsafe_bitcast[NoneType](),
                )
            )
        except e:
            self._free_descs()
            raise e^
        self._free_descs()
        self._count = 0

    ## __deinit__ — backstop: free the descriptor array if flush() never ran
    ## (e.g. a register_* call raised during module init). Descriptors are
    ## trivial (pointers + UInt32), so freeing without per-element deinit is
    ## correct.
    def __deinit__(deinit self):
        if Int(self._descs) != 0:
            self._descs.unsafe_free()

    ## class_def — define a class and attach it to exports, returns ClassBuilder
    def class_def(
        self, name: StringLiteral, ctor_ptr: OpaquePointer[MutAnyOrigin]
    ) raises -> ClassBuilder:
        var b = bindings_from_context(self.data)
        var ctor = define_class(b, self.env, name, ctor_ptr, self.data)
        JsObject(self.exports).set_property(b, self.env, name, ctor)
        return ClassBuilder(self.env, ctor, self.data)


## ClassBuilder — chainable class member registration
##
## Returned by ModuleBuilder.class_def(). Provides methods to add instance
## methods, getters, setters, and static members to a class. Sets desc.data
## on all property descriptors so callbacks get the bindings pointer.
struct ClassBuilder:
    @__allow_legacy_any_origin_fields
    var env: NapiEnv
    @__allow_legacy_any_origin_fields
    var ctor: NapiValue
    @__allow_legacy_any_origin_fields
    var data: OpaquePointer[MutAnyOrigin]

    def __init__(
        out self,
        env: NapiEnv,
        ctor: NapiValue,
        data: OpaquePointer[MutAnyOrigin],
    ):
        self.env = env
        self.ctor = ctor
        self.data = data

    ## instance_method — add an instance method to the class prototype
    def instance_method(
        self, name: StringLiteral, ptr: OpaquePointer[MutAnyOrigin]
    ) raises:
        var b = bindings_from_context(self.data)
        var proto = _get_prototype(b, self.env, self.ctor)
        var desc = NapiPropertyDescriptor()
        desc.utf8name = name.unsafe_ptr().unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        desc.method = ptr
        desc.data = self.data
        desc.attributes = 0
        define_property(b, self.env, proto, desc)

    ## getter — add a read-only getter to the class prototype
    def getter(
        self, name: StringLiteral, ptr: OpaquePointer[MutAnyOrigin]
    ) raises:
        var b = bindings_from_context(self.data)
        var proto = _get_prototype(b, self.env, self.ctor)
        var desc = NapiPropertyDescriptor()
        desc.utf8name = name.unsafe_ptr().unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        desc.getter = ptr
        desc.data = self.data
        desc.attributes = 0
        define_property(b, self.env, proto, desc)

    ## getter_setter — add a getter+setter pair to the class prototype
    def getter_setter(
        self,
        name: StringLiteral,
        get_ptr: OpaquePointer[MutAnyOrigin],
        set_ptr: OpaquePointer[MutAnyOrigin],
    ) raises:
        var b = bindings_from_context(self.data)
        var proto = _get_prototype(b, self.env, self.ctor)
        var desc = NapiPropertyDescriptor()
        desc.utf8name = name.unsafe_ptr().unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        desc.getter = get_ptr
        desc.setter = set_ptr
        desc.data = self.data
        desc.attributes = 0
        define_property(b, self.env, proto, desc)

    ## static_method — add a static method to the constructor
    def static_method(
        self, name: StringLiteral, ptr: OpaquePointer[MutAnyOrigin]
    ) raises:
        var b = bindings_from_context(self.data)
        var desc = NapiPropertyDescriptor()
        desc.utf8name = name.unsafe_ptr().unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        desc.method = ptr
        desc.data = self.data
        desc.attributes = 0
        define_property(b, self.env, self.ctor, desc)

    ## static_getter — add a read-only static getter to the constructor
    def static_getter(
        self, name: StringLiteral, ptr: OpaquePointer[MutAnyOrigin]
    ) raises:
        var b = bindings_from_context(self.data)
        var desc = NapiPropertyDescriptor()
        desc.utf8name = name.unsafe_ptr().unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        desc.getter = ptr
        desc.data = self.data
        desc.attributes = 0
        define_property(b, self.env, self.ctor, desc)

    ## static_getter_setter — add a static getter+setter pair to the constructor
    def static_getter_setter(
        self,
        name: StringLiteral,
        get_ptr: OpaquePointer[MutAnyOrigin],
        set_ptr: OpaquePointer[MutAnyOrigin],
    ) raises:
        var b = bindings_from_context(self.data)
        var desc = NapiPropertyDescriptor()
        desc.utf8name = name.unsafe_ptr().unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        desc.getter = get_ptr
        desc.setter = set_ptr
        desc.data = self.data
        desc.attributes = 0
        define_property(b, self.env, self.ctor, desc)

    ## inherits — set up prototype chain inheritance from parent class
    def inherits(self, parent: ClassBuilder) raises:
        var b = bindings_from_context(self.data)
        set_class_prototype(b, self.env, self.ctor, parent.ctor)


## _bytes_equal — compare two byte buffers of known equal length
def _bytes_equal(
    a: OpaquePointer[ImmutAnyOrigin],
    b: OpaquePointer[ImmutAnyOrigin],
    length: Int,
) -> Bool:
    var a_bytes = a.unsafe_bitcast[UInt8]()
    var b_bytes = b.unsafe_bitcast[UInt8]()
    for i in range(length):
        if a_bytes[unsafe_offset=i] != b_bytes[unsafe_offset=i]:
            return False
    return True


## ClassEntry — one slot in a ClassRegistry
##
## Stores the .rodata pointer + byte length from a StringLiteral name,
## plus a NapiRef handle that keeps the constructor alive.
## Fields are all primitive types (pointers + Int) so no destructor needed.
struct ClassEntry(Movable):
    @__allow_legacy_any_origin_fields
    var name_ptr: OpaquePointer[ImmutAnyOrigin]  # StringLiteral .rodata pointer
    var name_len: Int
    @__allow_legacy_any_origin_fields
    var ctor_ref: NapiRef

    def __init__(out self):
        self.name_ptr = OpaquePointer[ImmutAnyOrigin](unsafe_from_address=Int(0))
        self.name_len = 0
        self.ctor_ref = NapiRef(unsafe_from_address=Int(0))

    def __moveinit__(out self, deinit take: Self):
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
    @__allow_legacy_any_origin_fields
    var _entries: Pointer[ClassEntry, MutAnyOrigin]
    var _count: Int

    def __init__(out self):
        self._entries = unsafe_alloc[ClassEntry](16).as_unsafe_any_origin()
        self._count = 0

    def __moveinit__(out self, deinit take: Self):
        self._entries = take._entries
        self._count = take._count

    ## register — store a strong NapiRef to a constructor, keyed by name
    def register(
        mut self,
        b: Bindings,
        env: NapiEnv,
        name: StringLiteral,
        ctor: NapiValue,
    ) raises:
        if self._count >= 16:
            raise Error("ClassRegistry: capacity exceeded (max 16 classes)")
        var entry = ClassEntry()
        entry.name_ptr = name.unsafe_ptr().unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        entry.name_len = name.byte_length()
        entry.ctor_ref = JsRef.create(b, env, ctor, 1).handle
        self._entries.unsafe_offset(self._count).unsafe_write(entry^)
        self._count += 1

    ## new_instance — call `new ClassName(args)` from Mojo code
    ##
    ## Looks up the constructor by byte-comparing the StringLiteral name,
    ## then calls napi_new_instance. Raises if the class is not registered.
    def new_instance(
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
            var ep = self._entries.unsafe_offset(i)
            if ep[].name_len == target_len and _bytes_equal(
                ep[].name_ptr, target_ptr.unsafe_bitcast[NoneType]().as_unsafe_any_origin(), target_len
            ):
                var ctor_val = JsRef(ep[].ctor_ref).get(b, env)
                var result = NapiValue(unsafe_from_address=Int(0))
                check_status(
                    raw_new_instance(
                        b,
                        env,
                        ctor_val,
                        argc,
                        argv,
                        Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                    )
                )
                return result
        raise Error("ClassRegistry: class not found")
