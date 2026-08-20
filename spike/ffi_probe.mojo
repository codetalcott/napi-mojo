## ffi_probe.mojo — N-API FFI Spike
##
## PURPOSE: throwaway validation code. It is the canonical *runnable* statement
## of napi-mojo's FFI contract. Run it on a new machine, or before mass-editing
## call sites after a Mojo nightly changes the FFI surface — it fails loudly and
## in seconds, where the same mistake in src/ is a SIGSEGV inside Node.
##
## QUESTIONS THIS ANSWERS (each step builds on the previous):
##
##   1. Does @export("napi_register_module_v1", ABI="C") produce the C-linkage
##      symbol Node.js finds via dlsym?
##   2. Does OwnedDLHandle() open the host Node.js process symbol table?
##   3. Is NapiPropertyDescriptor's layout compatible with the C definition?
##   4. Can we register a method on exports via napi_define_properties?
##   5. Does `OwnedDLHandle.get_symbol[NoneType](name)` resolve an N-API symbol,
##      and is the returned address callable once reinterpreted as a thin
##      abi("C") function pointer? (the `_sym[F]` helper)
##   6. Is a thin fn ptr exactly one machine word — i.e. is it sound to type-erase
##      it into an OpaquePointer[MutAnyOrigin] cache slot? (comptime assert)
##   7. Does `.as_unsafe_any_origin()` convert get_symbol's MutUntrackedOrigin
##      result into the MutAnyOrigin a NapiBindings field is typed as?
##   8. End-to-end: resolve → store in a struct field → read back → call.
##      That is the whole NapiBindings cache mechanism in miniature.
##   9. Can a struct field drop `@__allow_legacy_any_origin_fields` by moving to
##      MutUntrackedOrigin, while the FFI function-pointer types keep
##      MutAnyOrigin? (the decorator-removal recipe — see below)
##  10. Is that change layout-neutral, i.e. is OpaquePointer[MutUntrackedOrigin]
##      the same size as OpaquePointer[MutAnyOrigin] and is
##      NapiPropertyDescriptor still 64 bytes? (comptime assert)
##
## ⚠ THE ORIGIN MIGRATION — TWO POPULATIONS, NOT ONE
##
## `@__allow_legacy_any_origin_fields` is an unstable escape hatch upstream has
## slated for removal, so this migration is not optional — only unscheduled.
## CLAUDE.md warns that a naive global MutAnyOrigin → MutUntrackedOrigin rename
## caused confirmed SIGSEGVs. That warning is correct, and it is about a
## DIFFERENT population than the decorator's. Keeping them apart is the whole
## recipe:
##
##   POPULATION A — STRUCT FIELDS (243 decorator sites, 40 files).
##     Every one points at a V8-owned opaque handle, a static code address, or
##     a heap allocation. NOT ONE is ever assigned from `Pointer(to=<local>)`
##     (verified by grep across src/ and examples/). There is therefore no Mojo
##     stack slot whose lifetime AnyOrigin is silently extending, and
##     MutUntrackedOrigin is not merely safe here but more honest: the lifetime
##     really is managed explicitly, by V8 or by unsafe_alloc.
##
##   POPULATION B — TRANSIENT SLOT CASTS (159 sites).
##     `Pointer(to=<local>).unsafe_bitcast[NoneType]().as_unsafe_any_origin()`
##     passed inline to an FFI call. HERE the widening to AnyOrigin is
##     load-bearing: it keeps a register-passable local's spill slot alive
##     across the call while N-API reads or writes through it. This is the
##     population that SIGSEGV'd.
##
## The two are independent, and that is the finding that makes the migration
## tractable: removing the decorator does NOT require touching population B,
## PROVIDED the FFI function-pointer types keep MutAnyOrigin. A field handed to
## such a signature just gains an explicit `.as_unsafe_any_origin()` — the same
## concrete→Any widening already spelled at 159 other sites today.
##
## THE RULE THAT MUST NOT BE BROKEN: do not "simplify" by also moving the
## `comptime *Fn = def(...) thin abi("C")` parameter origins to Untracked. That
## is exactly the global rename that severs population B's lifetime extension,
## and nothing in the type system will stop you.
##
## This file is the runnable proof of the recipe: its structs carry NO
## decorator, its FFI types still say MutAnyOrigin, and `originProbe()` does a
## create→read-back round trip through four separate output slots so a
## clobbered slot shows up as a content mismatch rather than a lucky pass.
##
## THE FFI CONTRACT (what src/ relies on, stated once):
##
##   - N-API symbols live in the host process, not a library we load. Resolve
##     them with OwnedDLHandle() == dlopen(NULL). Never unmapped, so the
##     handle's lifetime does not constrain the resolved pointers. (A *named*
##     library — see src/napi/framework/runtime.mojo — is the opposite case and
##     must keep its handle alive across the call with `_ = lib^`.)
##   - Function types crossing the boundary MUST carry `thin abi("C")`. The
##     `thin` effect makes it a bare function pointer (satisfying
##     TrivialRegisterPassable); `abi("C")` makes argument passing correct.
##   - get_symbol returns the symbol's ADDRESS AS A VALUE. To call it you must
##     reinterpret the machine word, NOT dereference the pointer:
##         Pointer(to=addr).unsafe_bitcast[F]()[]   # correct
##         addr.unsafe_bitcast[F]()[]                     # WRONG — loads the first 8
##                                                 # bytes of machine code and
##                                                 # calls THAT as a pointer
##     Both compile. Only the first is right. This is why `_sym[F]` exists and
##     why call sites must never spell the bitcast inline.
##
## HOW TO RUN:
##   pixi run mojo build --emit shared-lib spike/ffi_probe.mojo -o build/probe.dylib
##   cp build/probe.dylib build/probe.node
##   nm -gU build/probe.dylib | grep napi_register_module_v1
##   node -e "console.log(require('./build/probe.node').hello())"
##   node -e "console.log(require('./build/probe.node').originProbe())"

from std.ffi import OwnedDLHandle
from std.sys.info import size_of
from std.memory.alloc import unsafe_alloc

# ---------------------------------------------------------------------------
# Opaque handle types
#
# N-API's napi_env and napi_value are opaque pointers (void*) in C.
# OpaquePointer[MutAnyOrigin] is Mojo's void*. MutAnyOrigin is fully concrete
# (non-parameterized) — required for @export functions and for non-parametric
# function types crossing the FFI boundary.
# ---------------------------------------------------------------------------
comptime NapiEnv = OpaquePointer[MutAnyOrigin]
comptime NapiValue = OpaquePointer[MutAnyOrigin]
comptime NapiStatus = Int32
comptime NAPI_OK: NapiStatus = 0

# STORAGE-facing spellings. These are what struct fields use once
# @__allow_legacy_any_origin_fields is gone. Deliberately distinct from the
# FFI-facing NapiEnv/NapiValue above, which must stay AnyOrigin — see the
# TWO POPULATIONS note in the header.
comptime NapiValueStore = OpaquePointer[MutUntrackedOrigin]
comptime NapiConstStore = OpaquePointer[ImmUntrackedOrigin]

# Concrete N-API function types used below.
comptime GetUndefinedFn = def(
    NapiEnv, OpaquePointer[MutAnyOrigin]
) thin abi("C") -> NapiStatus
comptime CreateStringFn = def(
    NapiEnv, OpaquePointer[ImmutAnyOrigin], UInt, OpaquePointer[MutAnyOrigin]
) thin abi("C") -> NapiStatus
comptime DefinePropsFn = def(
    NapiEnv, NapiValue, UInt, OpaquePointer[ImmutAnyOrigin]
) thin abi("C") -> NapiStatus
comptime GetValueStringFn = def(
    NapiEnv,
    NapiValue,
    OpaquePointer[MutAnyOrigin],
    UInt,
    OpaquePointer[MutAnyOrigin],
) thin abi("C") -> NapiStatus


# ---------------------------------------------------------------------------
# Q6: is a thin abi("C") fn ptr a single machine word?
#
# This is the compile-time guard for the NapiBindings cache: 143 resolved
# function pointers are stored in OpaquePointer[MutAnyOrigin] slots. If a
# nightly ever made a function reference fat (a wrapper struct carrying an
# origin, say), that type-erasure would silently store the wrong word and the
# failure would be a jump to garbage at runtime. Assert it instead.
# ---------------------------------------------------------------------------
@always_inline
def assert_fn_ptr_is_one_word():
    comptime assert size_of[GetUndefinedFn]() == size_of[
        OpaquePointer[MutAnyOrigin]
    ](), (
        "thin abi(C) fn ptr is not one machine word — the NapiBindings cache"
        " design (fn ptr erased to OpaquePointer) is no longer sound"
    )


# ---------------------------------------------------------------------------
# Q10: is the decorator-removal recipe LAYOUT-NEUTRAL?
#
# The recipe changes only each field's ORIGIN parameter. If that ever altered
# the machine representation, every napi_define_properties call in the
# framework would corrupt silently — the exact failure mode CLAUDE.md flags for
# a wrong descriptor layout. Assert it rather than assume it.
# ---------------------------------------------------------------------------
@always_inline
def assert_layout_is_c_compatible():
    comptime assert size_of[NapiValueStore]() == size_of[
        OpaquePointer[MutAnyOrigin]
    ](), (
        "OpaquePointer[MutUntrackedOrigin] is not the same size as"
        " OpaquePointer[MutAnyOrigin] — the decorator-removal recipe is NOT"
        " layout-neutral and every FFI struct must be re-checked by hand"
    )
    # node_api.h: 6 pointers + napi_property_attributes (int) + pad + void*
    comptime assert size_of[NapiPropertyDescriptor]() == 64, (
        "NapiPropertyDescriptor is not 64 bytes — it no longer matches"
        " napi_property_descriptor in node_api.h"
    )


# ---------------------------------------------------------------------------
# Q5: the _sym[F] helper — the ONLY place the reinterpret is spelled.
#
# Mirrors what src/napi/raw.mojo uses for its env-only fallback overloads.
# ---------------------------------------------------------------------------
@always_inline
def _sym[F: TrivialRegisterPassable](
    ref h: OwnedDLHandle, name: StaticString
) raises -> F:
    var opt = h.get_symbol[NoneType](name)
    if opt is None:
        raise Error("napi-mojo: symbol not found: ", name)
    var addr = opt.value()
    # Reinterpret the word holding the address — do NOT deref `addr` itself.
    return Pointer(to=addr).unsafe_bitcast[F]()[]


# ---------------------------------------------------------------------------
# Q7/Q8: a miniature NapiBindings — resolve once, erase to opaque slots,
# read back, call. This is the cache mechanism the real bindings.mojo uses.
# ---------------------------------------------------------------------------
struct ProbeBindings(Movable):
    # NO @__allow_legacy_any_origin_fields. A resolved symbol is a static code
    # address with no lifetime, so Untracked is the honest type — and this is
    # the 143-slot NapiBindings cache in miniature (population A).
    var get_undefined: NapiValueStore
    var create_string_utf8: NapiValueStore
    var get_value_string_utf8: NapiValueStore

    def __init__(out self):
        self.get_undefined = NapiValueStore(unsafe_from_address=Int(0))
        self.create_string_utf8 = NapiValueStore(unsafe_from_address=Int(0))
        self.get_value_string_utf8 = NapiValueStore(unsafe_from_address=Int(0))

    # NOTE: no explicit __moveinit__. Movable is auto-derived here, and an
    # explicit `def __moveinit__(out self, deinit take: Self)` currently fails
    # to compile in a *main-module* file ("'None' has no attributes" on `self`)
    # even though the identical spelling compiles inside the `napi` package.
    # src/napi/bindings.mojo still declares its own; don't "fix" it to match
    # this file without re-checking both contexts.


## Resolve a symbol straight into a cache slot.
##
## Note there is NO Pointer(to=...) here: get_symbol already hands back
## the address as a value, and the slot IS that address. The address-of-local
## reinterpret is only needed when you want a *callable* (see _sym above).
## The mut+origin cast is the explicit spelling of the widening the slot type
## requires (as of dev2026080905, get_symbol borrows the handle, so the
## returned pointer's origin/mutability follow `h`); it is sound here
## specifically because a symbol address is a static code address with no
## lifetime, and the handle is dlopen(NULL) — never unmapped.
@always_inline
def _slot(ref h: OwnedDLHandle, name: StaticString) raises -> NapiValueStore:
    var opt = h.get_symbol[NoneType](name)
    if opt is None:
        raise Error("napi-mojo: symbol not found: ", name)
    return opt.value().unsafe_mut_cast[True]().unsafe_origin_cast[
        MutUntrackedOrigin
    ]()


def probe_bindings() raises -> ProbeBindings:
    var h = OwnedDLHandle()
    var b = ProbeBindings()
    b.get_undefined = _slot(h, "napi_get_undefined")
    b.create_string_utf8 = _slot(h, "napi_create_string_utf8")
    b.get_value_string_utf8 = _slot(h, "napi_get_value_string_utf8")
    # Never let a null slot reach a call site as a jump to address 0.
    if Int(b.get_undefined) == 0:
        raise Error("napi-mojo: null slot for napi_get_undefined")
    if Int(b.create_string_utf8) == 0:
        raise Error("napi-mojo: null slot for napi_create_string_utf8")
    if Int(b.get_value_string_utf8) == 0:
        raise Error("napi-mojo: null slot for napi_get_value_string_utf8")
    return b^


# ---------------------------------------------------------------------------
# NapiPropertyDescriptor — must match node_api.h field-for-field (Q3).
# 8 fields, in order: utf8name, name, method, getter, setter, value,
# attributes, data. A wrong layout corrupts napi_define_properties silently.
# ---------------------------------------------------------------------------
struct NapiPropertyDescriptor(Movable):
    # NO decorator. Field ORDER and SIZE are what node_api.h constrains; the
    # origin parameter is invisible to the C ABI. assert_layout_is_c_compatible
    # below pins that down rather than trusting it.
    var utf8name: NapiConstStore
    var name: NapiValueStore
    var method: NapiValueStore
    var getter: NapiValueStore
    var setter: NapiValueStore
    var value: NapiValueStore
    var attributes: UInt32
    var data: NapiValueStore

    def __init__(out self):
        self.utf8name = NapiConstStore(unsafe_from_address=Int(0))
        self.name = NapiValueStore(unsafe_from_address=Int(0))
        self.method = NapiValueStore(unsafe_from_address=Int(0))
        self.getter = NapiValueStore(unsafe_from_address=Int(0))
        self.setter = NapiValueStore(unsafe_from_address=Int(0))
        self.value = NapiValueStore(unsafe_from_address=Int(0))
        self.attributes = 0
        self.data = NapiValueStore(unsafe_from_address=Int(0))


# ---------------------------------------------------------------------------
# The exported callback: `hello()` returns a JS string.
#
# Exercises the cached-slot path end to end (Q8) — resolve, erase, read back,
# reinterpret, call.
# ---------------------------------------------------------------------------
def hello_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    var result = NapiValue(unsafe_from_address=Int(0))
    try:
        var b = probe_bindings()

        var msg = StaticString("FFI probe OK: get_symbol + thin abi(C) + cache")
        var create = Pointer(to=b.create_string_utf8).unsafe_bitcast[
            CreateStringFn
        ]()[]
        var status = create(
            env,
            msg.unsafe_ptr().unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            UInt(msg.byte_length()),
            Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
        )
        if status != NAPI_OK:
            return NapiValue(unsafe_from_address=Int(0))
        # Keep `result`'s stack slot alive across the FFI write-through.
        _ = result
        return result
    except:
        return NapiValue(unsafe_from_address=Int(0))


# ---------------------------------------------------------------------------
# Q9 (runtime): the migrated cache actually works, and a clobbered output slot
# would be VISIBLE.
#
# _roundtrip creates a JS string from `msg` through a local output slot, then
# reads it back through a second local slot and compares the bytes. A pass
# therefore requires the napi_value written into `result` to still be the
# handle N-API wrote — not a reused slot that happens to be non-null. Content
# comparison, not a null check, is the point: a null check passes on garbage.
#
# originProbe() runs four DISTINCT strings of different lengths so a slot
# clobbered by its neighbour shows up as a mismatch rather than a lucky pass.
# ---------------------------------------------------------------------------
def _roundtrip(b: ProbeBindings, env: NapiEnv, msg: StaticString) -> Bool:
    var n = msg.byte_length()
    var buf = unsafe_alloc[UInt8](n + 16)
    var ok = False
    try:
        var create = Pointer(to=b.create_string_utf8).unsafe_bitcast[
            CreateStringFn
        ]()[]
        var read = Pointer(to=b.get_value_string_utf8).unsafe_bitcast[
            GetValueStringFn
        ]()[]

        var handle = NapiValue(unsafe_from_address=Int(0))
        var st = create(
            env,
            msg.unsafe_ptr().unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            UInt(n),
            Pointer(to=handle).unsafe_bitcast[
                NoneType
            ]().as_unsafe_any_origin(),
        )
        # Population B: keep the spill slot alive across the FFI write-through.
        _ = handle
        if st == NAPI_OK:
            var written = UInt(0)
            var st2 = read(
                env,
                handle,
                buf.unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                UInt(n + 16),
                Pointer(to=written).unsafe_bitcast[
                    NoneType
                ]().as_unsafe_any_origin(),
            )
            _ = written
            if st2 == NAPI_OK and written == UInt(n):
                var same = True
                var src = msg.unsafe_ptr()
                for i in range(n):
                    if buf[unsafe_offset=i] != src[unsafe_offset=i]:
                        same = False
                ok = same
    except:
        ok = False
    buf.unsafe_free()
    return ok


def origin_probe_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    var result = NapiValue(unsafe_from_address=Int(0))
    try:
        var b = probe_bindings()
        var passed = 0
        if _roundtrip(b, env, StaticString("a")):
            passed += 1
        if _roundtrip(b, env, StaticString("origin")):
            passed += 1
        if _roundtrip(b, env, StaticString("untracked-origin-field-storage")):
            passed += 1
        if _roundtrip(
            b,
            env,
            StaticString(
                "a longer payload so a short slot cannot masquerade as this one"
            ),
        ):
            passed += 1

        var create = Pointer(to=b.create_string_utf8).unsafe_bitcast[
            CreateStringFn
        ]()[]
        var msg = StaticString("originProbe FAIL")
        if passed == 4:
            msg = StaticString("originProbe PASS 4/4")
        var status = create(
            env,
            msg.unsafe_ptr().unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            UInt(msg.byte_length()),
            Pointer(to=result).unsafe_bitcast[
                NoneType
            ]().as_unsafe_any_origin(),
        )
        _ = result
        if status != NAPI_OK:
            return NapiValue(unsafe_from_address=Int(0))
        return result
    except:
        return NapiValue(unsafe_from_address=Int(0))


@export("napi_register_module_v1")
def register_module(env: NapiEnv, exports: NapiValue) abi("C") -> NapiValue:
    # Mojo elaborates a def body only when something calls it, so an
    # UNCALLED comptime assert never fires. This file defined
    # assert_fn_ptr_is_one_word and never called it — the guard had never
    # actually run. Both are invoked here.
    assert_fn_ptr_is_one_word()
    assert_layout_is_c_compatible()
    try:
        var h = OwnedDLHandle()

        # Q5: resolve-and-call through the helper, no cache involved.
        var get_undefined = _sym[GetUndefinedFn](h, "napi_get_undefined")
        var undef = NapiValue(unsafe_from_address=Int(0))
        var st = get_undefined(
            env,
            Pointer(to=undef).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
        )
        _ = undef
        if st != NAPI_OK:
            return exports

        # Q3/Q4: register `hello` via napi_define_properties.
        var cb = hello_fn
        var desc = NapiPropertyDescriptor()
        var name = StaticString("hello")
        # Field is Untracked storage now, so this is an origin_cast rather
        # than the as_unsafe_any_origin() widening it used to need.
        desc.utf8name = name.unsafe_ptr().unsafe_bitcast[
            NoneType
        ]().unsafe_origin_cast[ImmUntrackedOrigin]()
        desc.method = Pointer(to=cb).unsafe_bitcast[NapiValueStore]()[]
        desc.attributes = 0

        var define_props = _sym[DefinePropsFn](h, "napi_define_properties")
        _ = define_props(
            env,
            exports,
            UInt(1),
            Pointer(to=desc).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
        )
        _ = desc
        _ = cb

        # Second export: the migrated-recipe round trip.
        var cb2 = origin_probe_fn
        var desc2 = NapiPropertyDescriptor()
        var name2 = StaticString("originProbe")
        desc2.utf8name = name2.unsafe_ptr().unsafe_bitcast[
            NoneType
        ]().unsafe_origin_cast[ImmUntrackedOrigin]()
        desc2.method = Pointer(to=cb2).unsafe_bitcast[NapiValueStore]()[]
        desc2.attributes = 0
        _ = define_props(
            env,
            exports,
            UInt(1),
            Pointer(to=desc2).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
        )
        _ = desc2
        _ = cb2
        _ = name2
    except:
        pass
    return exports
