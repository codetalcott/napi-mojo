## src/napi/types.mojo — N-API opaque handle types and property descriptor
##
## All fundamental type definitions for the N-API FFI boundary.
## These types are shared across all napi/* modules and by src/lib.mojo.
##
## v26.2 notes:
##   - OpaquePointer[MutAnyOrigin] = UnsafePointer[NoneType, MutAnyOrigin]
##     (fully concrete — no unbound type parameters; required for @export and
##      non-parametric get_function[] signatures)
##   - `comptime` replaces deprecated `alias`

# ---------------------------------------------------------------------------
# Opaque handle types
#
# napi_env and napi_value are opaque pointers (void*) in C.
# OpaquePointer[MutAnyOrigin] is fully concrete — required for @export
# functions and non-parametric function types in get_function[].
# ---------------------------------------------------------------------------
comptime NapiEnv = OpaquePointer[MutAnyOrigin]
comptime NapiValue = OpaquePointer[MutAnyOrigin]
comptime NapiStatus = Int32
comptime NAPI_OK: NapiStatus = 0

# ---------------------------------------------------------------------------
# napi_property_descriptor struct
#
# Must match the C definition in node_api.h EXACTLY (60 bytes on 64-bit,
# plus 4 bytes implicit padding = 64 bytes total):
#   const char* utf8name;              // 8 bytes (pointer)
#   napi_value name;                   // 8 bytes (pointer)
#   napi_callback method;              // 8 bytes (fn pointer)
#   napi_callback getter;              // 8 bytes (fn pointer)
#   napi_callback setter;              // 8 bytes (fn pointer)
#   napi_value value;                  // 8 bytes (pointer)
#   napi_property_attributes attributes; // 4 bytes (UInt32)
#   void* data;                        // 8 bytes (pointer)
#   // 4 bytes implicit padding
#
# Wrong field order causes silent memory corruption in napi_define_properties.
# ---------------------------------------------------------------------------
struct NapiPropertyDescriptor:
    var utf8name: OpaquePointer[MutAnyOrigin]
    var name: OpaquePointer[MutAnyOrigin]
    var method: OpaquePointer[MutAnyOrigin]   # napi_callback fn pointer
    var getter: OpaquePointer[MutAnyOrigin]
    var setter: OpaquePointer[MutAnyOrigin]
    var value: OpaquePointer[MutAnyOrigin]
    var attributes: UInt32                     # napi_property_attributes; 0 = napi_default
    var data: OpaquePointer[MutAnyOrigin]

    fn __init__(out self):
        self.utf8name = OpaquePointer[MutAnyOrigin]()
        self.name = OpaquePointer[MutAnyOrigin]()
        self.method = OpaquePointer[MutAnyOrigin]()
        self.getter = OpaquePointer[MutAnyOrigin]()
        self.setter = OpaquePointer[MutAnyOrigin]()
        self.value = OpaquePointer[MutAnyOrigin]()
        self.attributes = 0
        self.data = OpaquePointer[MutAnyOrigin]()
