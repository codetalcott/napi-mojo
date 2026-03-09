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
# Async context type (C2)
#
# napi_async_context tracks an async operation for async_hooks integration.
# Created by napi_async_init, destroyed by napi_async_destroy.
# Used with napi_make_callback to call JS in the correct async context.
# ---------------------------------------------------------------------------
comptime NapiAsyncContext = OpaquePointer[MutAnyOrigin]

# ---------------------------------------------------------------------------
# Callback scope type (C3)
#
# napi_callback_scope wraps the async context for a synchronous JS call.
# Created by napi_open_callback_scope, closed by napi_close_callback_scope.
# ---------------------------------------------------------------------------
comptime NapiCallbackScope = OpaquePointer[MutAnyOrigin]

# ---------------------------------------------------------------------------
# Reference type
#
# napi_ref is an opaque handle to a persistent reference to a napi_value.
# Created by napi_create_reference, allows preventing GC of a value.
# ---------------------------------------------------------------------------
comptime NapiRef = OpaquePointer[MutAnyOrigin]

# ---------------------------------------------------------------------------
# Escapable handle scope type
#
# napi_escapable_handle_scope allows one value to be "escaped" (promoted)
# to the outer scope.
# ---------------------------------------------------------------------------
comptime NapiEscapableHandleScope = OpaquePointer[MutAnyOrigin]

# ---------------------------------------------------------------------------
# Threadsafe function type
#
# napi_threadsafe_function is an opaque handle for calling JS functions
# from any thread. Created by napi_create_threadsafe_function.
# ---------------------------------------------------------------------------
comptime NapiThreadsafeFunction = OpaquePointer[MutAnyOrigin]

# ---------------------------------------------------------------------------
# napi_threadsafe_function_call_mode enum constants
# ---------------------------------------------------------------------------
comptime NAPI_TSFN_NONBLOCKING: Int32 = 0
comptime NAPI_TSFN_BLOCKING: Int32 = 1

# ---------------------------------------------------------------------------
# napi_threadsafe_function_release_mode enum constants
# ---------------------------------------------------------------------------
comptime NAPI_TSFN_RELEASE: Int32 = 0
comptime NAPI_TSFN_ABORT: Int32 = 1

# ---------------------------------------------------------------------------
# napi_typedarray_type enum constants
#
# Matches the C napi_typedarray_type enum in node_api.h.
# Used by napi_create_typedarray and napi_get_typedarray_info.
# ---------------------------------------------------------------------------
comptime NAPI_INT8_ARRAY: Int32 = 0
comptime NAPI_UINT8_ARRAY: Int32 = 1
comptime NAPI_UINT8_CLAMPED_ARRAY: Int32 = 2
comptime NAPI_INT16_ARRAY: Int32 = 3
comptime NAPI_UINT16_ARRAY: Int32 = 4
comptime NAPI_INT32_ARRAY: Int32 = 5
comptime NAPI_UINT32_ARRAY: Int32 = 6
comptime NAPI_FLOAT32_ARRAY: Int32 = 7
comptime NAPI_FLOAT64_ARRAY: Int32 = 8
comptime NAPI_BIGINT64_ARRAY: Int32 = 9
comptime NAPI_BIGUINT64_ARRAY: Int32 = 10

# ---------------------------------------------------------------------------
# napi_property_attributes constants
# ---------------------------------------------------------------------------
comptime NAPI_PROPERTY_WRITABLE: UInt32 = 1
comptime NAPI_PROPERTY_ENUMERABLE: UInt32 = 2
comptime NAPI_PROPERTY_CONFIGURABLE: UInt32 = 4
comptime NAPI_PROPERTY_STATIC: UInt32 = 1024

# ---------------------------------------------------------------------------
# napi_key_collection_mode enum constants
#
# Controls whether property enumeration includes prototype chain.
# Used by napi_get_all_property_names.
# ---------------------------------------------------------------------------
comptime NAPI_KEY_INCLUDE_PROTOTYPES: Int32 = 0
comptime NAPI_KEY_OWN_ONLY: Int32 = 1

# ---------------------------------------------------------------------------
# napi_key_filter bitmask constants
#
# Bitmask flags for filtering properties in napi_get_all_property_names.
# Combine with | (e.g., NAPI_KEY_ENUMERABLE | NAPI_KEY_SKIP_SYMBOLS = 18
# for Object.keys() behavior).
# ---------------------------------------------------------------------------
comptime NAPI_KEY_ALL_PROPERTIES: Int32 = 0
comptime NAPI_KEY_WRITABLE: Int32 = 1
comptime NAPI_KEY_ENUMERABLE: Int32 = 2
comptime NAPI_KEY_CONFIGURABLE: Int32 = 4
comptime NAPI_KEY_SKIP_STRINGS: Int32 = 8
comptime NAPI_KEY_SKIP_SYMBOLS: Int32 = 16

# ---------------------------------------------------------------------------
# napi_key_conversion enum constants
# ---------------------------------------------------------------------------
comptime NAPI_KEY_KEEP_NUMBERS: Int32 = 0
comptime NAPI_KEY_NUMBERS_TO_STRINGS: Int32 = 1

# ---------------------------------------------------------------------------
# napi_type_tag struct (N-API v8)
#
# Matches the C definition:
#   typedef struct { uint64_t lower; uint64_t upper; } napi_type_tag;
#
# Used with napi_type_tag_object / napi_check_object_type_tag for
# tamper-proof type identification of wrapped objects.
# ---------------------------------------------------------------------------
struct NapiTypeTag(Movable):
    var lower: UInt64
    var upper: UInt64

    fn __init__(out self):
        self.lower = 0
        self.upper = 0

    fn __init__(out self, lower: UInt64, upper: UInt64):
        self.lower = lower
        self.upper = upper

    fn __copyinit__(out self, copy: Self):
        self.lower = copy.lower
        self.upper = copy.upper

    fn __moveinit__(out self, deinit take: Self):
        self.lower = take.lower
        self.upper = take.upper

# ---------------------------------------------------------------------------
# napi_node_version struct
#
# Matches the C struct returned by napi_get_node_version:
#   typedef struct {
#     uint32_t major;
#     uint32_t minor;
#     uint32_t patch;
#     const char* release;
#   } napi_node_version;
#
# napi_get_node_version returns a pointer to a statically-allocated instance
# of this struct. Fields are read directly from the pointer.
# ---------------------------------------------------------------------------
struct NapiNodeVersion:
    var major: UInt32
    var minor: UInt32
    var patch: UInt32
    var release: OpaquePointer[ImmutAnyOrigin]  # const char*

    fn __init__(out self):
        self.major = 0
        self.minor = 0
        self.patch = 0
        self.release = OpaquePointer[ImmutAnyOrigin]()

    fn __init__(out self, major: UInt32, minor: UInt32, patch: UInt32, release: OpaquePointer[ImmutAnyOrigin]):
        self.major = major
        self.minor = minor
        self.patch = patch
        self.release = release

    fn __copyinit__(out self, copy: Self):
        self.major = copy.major
        self.minor = copy.minor
        self.patch = copy.patch
        self.release = copy.release

    fn __moveinit__(out self, deinit take: Self):
        self.major = take.major
        self.minor = take.minor
        self.patch = take.patch
        self.release = take.release

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
struct NapiPropertyDescriptor(Movable):
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

    fn __moveinit__(out self, deinit take: Self):
        self.utf8name = take.utf8name
        self.name = take.name
        self.method = take.method
        self.getter = take.getter
        self.setter = take.setter
        self.value = take.value
        self.attributes = take.attributes
        self.data = take.data
