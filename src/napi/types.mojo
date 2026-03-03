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
# napi_valuetype enum constants
#
# Matches the C napi_valuetype enum in node_api.h. Used by napi_typeof().
# ---------------------------------------------------------------------------
comptime NapiValueType = Int32
comptime NAPI_TYPE_UNDEFINED: NapiValueType = 0
comptime NAPI_TYPE_NULL: NapiValueType = 1
comptime NAPI_TYPE_BOOLEAN: NapiValueType = 2
comptime NAPI_TYPE_NUMBER: NapiValueType = 3
comptime NAPI_TYPE_STRING: NapiValueType = 4
comptime NAPI_TYPE_SYMBOL: NapiValueType = 5
comptime NAPI_TYPE_OBJECT: NapiValueType = 6
comptime NAPI_TYPE_FUNCTION: NapiValueType = 7
comptime NAPI_TYPE_EXTERNAL: NapiValueType = 8
comptime NAPI_TYPE_BIGINT: NapiValueType = 9

# ---------------------------------------------------------------------------
# Handle scope type
#
# napi_handle_scope is an opaque pointer. Opening a scope creates a new
# local handle context; closing it releases all handles created within.
# ---------------------------------------------------------------------------
comptime NapiHandleScope = OpaquePointer[MutAnyOrigin]

# ---------------------------------------------------------------------------
# Deferred type (for promises)
#
# napi_deferred is an opaque handle used to resolve or reject a promise.
# Created by napi_create_promise, consumed by napi_resolve_deferred or
# napi_reject_deferred. Each deferred can only be used once.
# ---------------------------------------------------------------------------
comptime NapiDeferred = OpaquePointer[MutAnyOrigin]

# ---------------------------------------------------------------------------
# Async work type
#
# napi_async_work is an opaque handle representing a unit of async work.
# Created by napi_create_async_work, queued by napi_queue_async_work,
# and cleaned up by napi_delete_async_work.
# ---------------------------------------------------------------------------
comptime NapiAsyncWork = OpaquePointer[MutAnyOrigin]

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
    # utf8name is const char* in C — immutable pointer to a null-terminated UTF-8
    # string. Must remain alive until napi_define_properties returns. Use string
    # literals (static lifetime) rather than Mojo heap Strings (ASAP-freed).
    var utf8name: OpaquePointer[ImmutAnyOrigin]
    var name: OpaquePointer[MutAnyOrigin]
    var method: OpaquePointer[MutAnyOrigin]   # napi_callback fn pointer
    var getter: OpaquePointer[MutAnyOrigin]
    var setter: OpaquePointer[MutAnyOrigin]
    var value: OpaquePointer[MutAnyOrigin]
    var attributes: UInt32                     # napi_property_attributes; 0 = napi_default
    var data: OpaquePointer[MutAnyOrigin]

    fn __init__(out self):
        self.utf8name = OpaquePointer[ImmutAnyOrigin]()
        self.name = OpaquePointer[MutAnyOrigin]()
        self.method = OpaquePointer[MutAnyOrigin]()
        self.getter = OpaquePointer[MutAnyOrigin]()
        self.setter = OpaquePointer[MutAnyOrigin]()
        self.value = OpaquePointer[MutAnyOrigin]()
        self.attributes = 0
        self.data = OpaquePointer[MutAnyOrigin]()
