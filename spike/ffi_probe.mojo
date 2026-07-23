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
##         UnsafePointer(to=addr).bitcast[F]()[]   # correct
##         addr.bitcast[F]()[]                     # WRONG — loads the first 8
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

from std.ffi import OwnedDLHandle
from std.sys.info import size_of

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
    return UnsafePointer(to=addr).bitcast[F]()[]


# ---------------------------------------------------------------------------
# Q7/Q8: a miniature NapiBindings — resolve once, erase to opaque slots,
# read back, call. This is the cache mechanism the real bindings.mojo uses.
# ---------------------------------------------------------------------------
struct ProbeBindings(Movable):
    @__allow_legacy_any_origin_fields
    var get_undefined: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var create_string_utf8: OpaquePointer[MutAnyOrigin]

    def __init__(out self):
        self.get_undefined = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.create_string_utf8 = OpaquePointer[MutAnyOrigin](
            unsafe_from_address=Int(0)
        )

    # NOTE: no explicit __moveinit__. Movable is auto-derived here, and an
    # explicit `def __moveinit__(out self, deinit take: Self)` currently fails
    # to compile in a *main-module* file ("'None' has no attributes" on `self`)
    # even though the identical spelling compiles inside the `napi` package.
    # src/napi/bindings.mojo still declares its own; don't "fix" it to match
    # this file without re-checking both contexts.


## Resolve a symbol straight into a cache slot.
##
## Note there is NO UnsafePointer(to=...) here: get_symbol already hands back
## the address as a value, and the slot IS that address. The address-of-local
## reinterpret is only needed when you want a *callable* (see _sym above).
## `.as_unsafe_any_origin()` is the explicit spelling of the MutUntrackedOrigin
## -> MutAnyOrigin widening; it is sound here specifically because a symbol
## address is a static code address with no lifetime.
@always_inline
def _slot(ref h: OwnedDLHandle, name: StaticString) raises -> OpaquePointer[
    MutAnyOrigin
]:
    var opt = h.get_symbol[NoneType](name)
    if opt is None:
        raise Error("napi-mojo: symbol not found: ", name)
    return opt.value().as_unsafe_any_origin()


def probe_bindings() raises -> ProbeBindings:
    var h = OwnedDLHandle()
    var b = ProbeBindings()
    b.get_undefined = _slot(h, "napi_get_undefined")
    b.create_string_utf8 = _slot(h, "napi_create_string_utf8")
    # Never let a null slot reach a call site as a jump to address 0.
    if Int(b.get_undefined) == 0:
        raise Error("napi-mojo: null slot for napi_get_undefined")
    if Int(b.create_string_utf8) == 0:
        raise Error("napi-mojo: null slot for napi_create_string_utf8")
    return b^


# ---------------------------------------------------------------------------
# NapiPropertyDescriptor — must match node_api.h field-for-field (Q3).
# 8 fields, in order: utf8name, name, method, getter, setter, value,
# attributes, data. A wrong layout corrupts napi_define_properties silently.
# ---------------------------------------------------------------------------
struct NapiPropertyDescriptor(Movable):
    @__allow_legacy_any_origin_fields
    var utf8name: OpaquePointer[ImmutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var name: NapiValue
    @__allow_legacy_any_origin_fields
    var method: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var getter: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var setter: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var value: NapiValue
    var attributes: UInt32
    @__allow_legacy_any_origin_fields
    var data: OpaquePointer[MutAnyOrigin]

    def __init__(out self):
        self.utf8name = OpaquePointer[ImmutAnyOrigin](unsafe_from_address=Int(0))
        self.name = NapiValue(unsafe_from_address=Int(0))
        self.method = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.getter = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.setter = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.value = NapiValue(unsafe_from_address=Int(0))
        self.attributes = 0
        self.data = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))


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
        var create = UnsafePointer(to=b.create_string_utf8).bitcast[
            CreateStringFn
        ]()[]
        var status = create(
            env,
            msg.unsafe_ptr().bitcast[NoneType]().as_unsafe_any_origin(),
            UInt(msg.byte_length()),
            UnsafePointer(to=result).bitcast[NoneType]().as_unsafe_any_origin(),
        )
        if status != NAPI_OK:
            return NapiValue(unsafe_from_address=Int(0))
        # Keep `result`'s stack slot alive across the FFI write-through.
        _ = result
        return result
    except:
        return NapiValue(unsafe_from_address=Int(0))


@export("napi_register_module_v1")
def register_module(env: NapiEnv, exports: NapiValue) abi("C") -> NapiValue:
    try:
        var h = OwnedDLHandle()

        # Q5: resolve-and-call through the helper, no cache involved.
        var get_undefined = _sym[GetUndefinedFn](h, "napi_get_undefined")
        var undef = NapiValue(unsafe_from_address=Int(0))
        var st = get_undefined(
            env,
            UnsafePointer(to=undef).bitcast[NoneType]().as_unsafe_any_origin(),
        )
        _ = undef
        if st != NAPI_OK:
            return exports

        # Q3/Q4: register `hello` via napi_define_properties.
        var cb = hello_fn
        var desc = NapiPropertyDescriptor()
        var name = StaticString("hello")
        desc.utf8name = name.unsafe_ptr().bitcast[NoneType]().as_unsafe_any_origin()
        desc.method = UnsafePointer(to=cb).bitcast[
            OpaquePointer[MutAnyOrigin]
        ]()[]
        desc.attributes = 0

        var define_props = _sym[DefinePropsFn](h, "napi_define_properties")
        _ = define_props(
            env,
            exports,
            UInt(1),
            UnsafePointer(to=desc).bitcast[NoneType]().as_unsafe_any_origin(),
        )
        _ = desc
        _ = cb
    except:
        pass
    return exports
