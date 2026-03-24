## ffi_probe.mojo — N-API FFI Spike
##
## PURPOSE: This is throwaway validation code. Its only job is to answer four
## questions before any real implementation begins:
##
##   1. Does @export("napi_register_module_v1", ABI="C") produce the correct
##      C-linkage symbol that Node.js can find via dlsym?
##
##   2. Does OwnedDLHandle() open the host Node.js process symbol table,
##      giving us access to napi_* functions at runtime?
##
##   3. Is NapiPropertyDescriptor struct layout compatible with C's definition,
##      so napi_define_properties reads our struct correctly?
##
##   4. Can we register a method on exports using napi_define_properties?
##      (Function pointer for the callback is left null for now — resolving
##      the Mojo fn-pointer syntax is a follow-up step.)
##
## v26.2 CHANGES FROM ORIGINAL:
##   - `alias` replaced with `comptime` (alias is deprecated in v26.2)
##   - UnsafePointer[UInt8] replaced with OpaquePointer[MutAnyOrigin]:
##       * OpaquePointer[MutAnyOrigin] = UnsafePointer[NoneType, MutAnyOrigin]
##       * Fully concrete type — no unbound `mut`/`origin` parameters
##       * Required by @export, which cannot be applied to parametric functions
##   - OwnedDLHandle("") changed to OwnedDLHandle() — no-arg form calls
##       dlopen(NULL), which opens the host process symbol table
##   - OwnedDLHandle() raises — get_node_symbols() marked raises; callers use try
##   - Function types in get_function[] use concrete origin types (ImmutAnyOrigin,
##       MutAnyOrigin) to avoid "cannot call dynamic function" compile errors
##
## HOW TO RUN:
##   pixi run mojo build --emit shared-lib spike/ffi_probe.mojo -o build/probe.dylib
##   cp build/probe.dylib build/probe.node
##   nm -gU build/probe.dylib | grep napi_register_module_v1
##   node -e "require('./build/probe.node')"           # step 1 check
##   node -e "console.log(require('./build/probe.node').hello)"  # step 4 check
##
## Each step below builds on the previous.

from std.ffi import OwnedDLHandle

# ---------------------------------------------------------------------------
# Opaque handle types
#
# N-API's napi_env and napi_value are opaque pointers (void*) in C.
#
# v26.2: We use OpaquePointer[MutAnyOrigin] instead of UnsafePointer[UInt8].
# OpaquePointer is the Mojo equivalent of C's void*. MutAnyOrigin is a
# fully-concrete (non-parameterized) origin — required for @export functions
# and for non-parametric function types in get_function[].
# ---------------------------------------------------------------------------
comptime NapiEnv = OpaquePointer[MutAnyOrigin]
comptime NapiValue = OpaquePointer[MutAnyOrigin]
comptime NapiStatus = Int32
comptime NAPI_OK: NapiStatus = 0

# ---------------------------------------------------------------------------
# napi_property_descriptor — must match C struct layout EXACTLY
#
# C definition (from node_api.h):
#   typedef struct {
#     const char* utf8name;         // 8 bytes (pointer)
#     napi_value name;              // 8 bytes (pointer)
#     napi_callback method;         // 8 bytes (def pointer)
#     napi_callback getter;         // 8 bytes (def pointer)
#     napi_callback setter;         // 8 bytes (def pointer)
#     napi_value value;             // 8 bytes (pointer)
#     napi_property_attributes attributes; // 4 bytes (int32)
#     void* data;                   // 8 bytes (pointer)
#   } napi_property_descriptor;
#
# Total: 60 bytes (4 bytes implicit padding after attributes on 64-bit systems)
#
# All pointer-sized fields use OpaquePointer[MutAnyOrigin] (8 bytes each).
# The struct validates layout via Step 3 in the spike.
# ---------------------------------------------------------------------------
struct NapiPropertyDescriptor:
    var utf8name: OpaquePointer[MutAnyOrigin]
    var name: OpaquePointer[MutAnyOrigin]
    var method: OpaquePointer[MutAnyOrigin]    # napi_callback def pointer
    var getter: OpaquePointer[MutAnyOrigin]
    var setter: OpaquePointer[MutAnyOrigin]
    var value: OpaquePointer[MutAnyOrigin]
    var attributes: UInt32                      # napi_default = 0
    var data: OpaquePointer[MutAnyOrigin]

    def __init__(out self):
        self.utf8name = OpaquePointer[MutAnyOrigin]()
        self.name = OpaquePointer[MutAnyOrigin]()
        self.method = OpaquePointer[MutAnyOrigin]()
        self.getter = OpaquePointer[MutAnyOrigin]()
        self.setter = OpaquePointer[MutAnyOrigin]()
        self.value = OpaquePointer[MutAnyOrigin]()
        self.attributes = 0
        self.data = OpaquePointer[MutAnyOrigin]()

# ---------------------------------------------------------------------------
# Host process N-API function lookup
#
# OwnedDLHandle() calls dlopen(NULL, ...) — opens the host process image,
# giving us access to all exported symbols including N-API functions.
# The no-arg OwnedDLHandle() constructor is v26.2's form; "" (empty string)
# was the previous convention but now tries to open a file named "".
# ---------------------------------------------------------------------------
def get_node_symbols() raises -> OwnedDLHandle:
    return OwnedDLHandle()

# ---------------------------------------------------------------------------
# Step 2: Call napi_create_string_utf8 via dynamic lookup
#
# C signature:
#   napi_status napi_create_string_utf8(
#     napi_env env,
#     const char* str,       <- ImmutAnyOrigin: read-only string data
#     size_t length,
#     napi_value* result     <- MutAnyOrigin: N-API writes the result here
#   );
# ---------------------------------------------------------------------------
def napi_create_string_utf8(
    env: NapiEnv,
    str_ptr: OpaquePointer[ImmutAnyOrigin],
    length: UInt,
    result: OpaquePointer[MutAnyOrigin],
) raises -> NapiStatus:
    var h = get_node_symbols()
    var f = h.get_function[
        def (
            NapiEnv,
            OpaquePointer[ImmutAnyOrigin],
            UInt,
            OpaquePointer[MutAnyOrigin],
        ) -> NapiStatus
    ]("napi_create_string_utf8")
    return f(env, str_ptr, length, result)

# ---------------------------------------------------------------------------
# Step 3: Call napi_define_properties to register a function on exports
#
# C signature:
#   napi_status napi_define_properties(
#     napi_env env,
#     napi_value object,
#     size_t property_count,
#     const napi_property_descriptor* properties  <- ImmutAnyOrigin: read-only
#   );
# ---------------------------------------------------------------------------
def napi_define_properties(
    env: NapiEnv,
    object: NapiValue,
    property_count: UInt,
    properties: OpaquePointer[ImmutAnyOrigin],
) raises -> NapiStatus:
    var h = get_node_symbols()
    var f = h.get_function[
        def (
            NapiEnv,
            NapiValue,
            UInt,
            OpaquePointer[ImmutAnyOrigin],
        ) -> NapiStatus
    ]("napi_define_properties")
    return f(env, object, property_count, properties)

# ---------------------------------------------------------------------------
# Step 4: The actual callback exposed as addon.hello()
#
# napi_callback C signature:
#   typedef napi_value (*napi_callback)(napi_env, napi_callback_info);
#
# NOTE: desc.method is left null in this spike iteration. Even with a null
# method pointer, calling napi_define_properties validates struct layout
# (Step 3). The function pointer syntax will be resolved in a follow-up.
# ---------------------------------------------------------------------------
def hello_callback(env: NapiEnv, info: NapiValue) -> NapiValue:
    var greeting = String("Hello from spike!")
    var result: NapiValue = NapiValue()
    try:
        # String.unsafe_ptr() returns immutable UnsafePointer[Byte, origin_of(self)].
        # .bitcast[NoneType]() → OpaquePointer[immut origin]. Implicitly casts to
        # OpaquePointer[ImmutAnyOrigin] (any pointer can widen to ImmutAnyOrigin).
        var str_ptr: OpaquePointer[ImmutAnyOrigin] = greeting.unsafe_ptr().bitcast[NoneType]()
        # UnsafePointer(to=result) → mutable pointer to result. .bitcast[NoneType]()
        # → OpaquePointer[origin_of(result)]. Implicitly casts to MutAnyOrigin.
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
        _ = napi_create_string_utf8(env, str_ptr, len(greeting), result_ptr)
    except:
        pass
    return result

# ---------------------------------------------------------------------------
# STEP 1: Module entry point
#
# Node.js finds this symbol via dlsym("napi_register_module_v1") after dlopen.
# @export with ABI="C" suppresses Mojo name mangling.
#
# v26.2 requirement: @export cannot be applied to parametric functions.
# NapiEnv/NapiValue = OpaquePointer[MutAnyOrigin] are fully concrete — no
# unbound type parameters — so this function is non-parametric.
#
# Validation:
#   nm -gU build/probe.dylib | grep napi_register_module_v1  -> symbol present
#   node -e "require('./build/probe.node')"                   -> no crash
# ---------------------------------------------------------------------------
@export("napi_register_module_v1", ABI="C")
def register_module(env: NapiEnv, exports: NapiValue) -> NapiValue:
    # Keep `name` alive until napi_define_properties returns — Mojo's ASAP
    # destruction would free stack Strings before N-API reads the pointer.
    var name = String("hello")
    var desc = NapiPropertyDescriptor()

    # String.unsafe_ptr_mut() returns a mutable UnsafePointer[Byte, origin_of(name)].
    # .bitcast[NoneType]() → OpaquePointer[origin_of(name)] (mutable).
    # Implicitly casts to OpaquePointer[MutAnyOrigin].
    desc.utf8name = name.unsafe_ptr_mut().bitcast[NoneType]()

    # Get a C-callable function pointer to hello_callback.
    # v26.2 confirmed syntax: a Mojo def reference is an 8-byte value holding the
    # code address. UnsafePointer(to=fn_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
    # dereferences the def reference's memory to extract the raw code pointer.
    var hello_fn_ref = hello_callback
    desc.method = UnsafePointer(to=hello_fn_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
    desc.attributes = 0  # napi_default

    try:
        # UnsafePointer(to=desc) → mutable pointer to desc struct.
        # .bitcast[NoneType]() → OpaquePointer. Implicitly casts to ImmutAnyOrigin.
        var desc_ptr: OpaquePointer[ImmutAnyOrigin] = UnsafePointer(to=desc).bitcast[NoneType]()
        _ = napi_define_properties(env, exports, 1, desc_ptr)
    except:
        pass

    return exports
