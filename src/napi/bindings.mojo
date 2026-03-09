## src/napi/bindings.mojo — pre-resolved N-API function pointers
##
## Instead of calling OwnedDLHandle() + get_function[] on every N-API call,
## this module resolves ALL symbols once at startup and stores them as opaque
## function pointers in a single struct.
##
## Usage:
##   var bindings = NapiBindings()
##   init_bindings(bindings)
##   # Store via napi_set_instance_data, retrieve via get_bindings()

from ffi import OwnedDLHandle
from napi.types import NapiEnv, NapiValue, NapiStatus

struct NapiBindings(Movable):
    # --- 118 fields, one per raw_* function ---
    var create_string_utf8: OpaquePointer[MutAnyOrigin]
    var create_object: OpaquePointer[MutAnyOrigin]
    var set_named_property: OpaquePointer[MutAnyOrigin]
    var get_cb_info: OpaquePointer[MutAnyOrigin]
    var get_value_string_utf8: OpaquePointer[MutAnyOrigin]
    var define_properties: OpaquePointer[MutAnyOrigin]
    var get_value_double: OpaquePointer[MutAnyOrigin]
    var create_double: OpaquePointer[MutAnyOrigin]
    var throw_error: OpaquePointer[MutAnyOrigin]
    var get_boolean: OpaquePointer[MutAnyOrigin]
    var get_value_bool: OpaquePointer[MutAnyOrigin]
    var typeof_: OpaquePointer[MutAnyOrigin]
    var get_null: OpaquePointer[MutAnyOrigin]
    var get_undefined: OpaquePointer[MutAnyOrigin]
    var create_array_with_length: OpaquePointer[MutAnyOrigin]
    var set_element: OpaquePointer[MutAnyOrigin]
    var get_element: OpaquePointer[MutAnyOrigin]
    var get_array_length: OpaquePointer[MutAnyOrigin]
    var get_property: OpaquePointer[MutAnyOrigin]
    var is_array: OpaquePointer[MutAnyOrigin]
    var get_named_property: OpaquePointer[MutAnyOrigin]
    var has_named_property: OpaquePointer[MutAnyOrigin]
    var call_function: OpaquePointer[MutAnyOrigin]
    var open_handle_scope: OpaquePointer[MutAnyOrigin]
    var close_handle_scope: OpaquePointer[MutAnyOrigin]
    var create_promise: OpaquePointer[MutAnyOrigin]
    var resolve_deferred: OpaquePointer[MutAnyOrigin]
    var reject_deferred: OpaquePointer[MutAnyOrigin]
    var create_error: OpaquePointer[MutAnyOrigin]
    var create_async_work: OpaquePointer[MutAnyOrigin]
    var queue_async_work: OpaquePointer[MutAnyOrigin]
    var delete_async_work: OpaquePointer[MutAnyOrigin]
    var create_int32: OpaquePointer[MutAnyOrigin]
    var get_value_int32: OpaquePointer[MutAnyOrigin]
    var create_uint32: OpaquePointer[MutAnyOrigin]
    var get_value_uint32: OpaquePointer[MutAnyOrigin]
    var create_int64: OpaquePointer[MutAnyOrigin]
    var get_value_int64: OpaquePointer[MutAnyOrigin]
    var throw_type_error: OpaquePointer[MutAnyOrigin]
    var throw_range_error: OpaquePointer[MutAnyOrigin]
    var create_type_error: OpaquePointer[MutAnyOrigin]
    var create_range_error: OpaquePointer[MutAnyOrigin]
    var create_arraybuffer: OpaquePointer[MutAnyOrigin]
    var get_arraybuffer_info: OpaquePointer[MutAnyOrigin]
    var is_arraybuffer: OpaquePointer[MutAnyOrigin]
    var detach_arraybuffer: OpaquePointer[MutAnyOrigin]
    var create_buffer: OpaquePointer[MutAnyOrigin]
    var create_buffer_copy: OpaquePointer[MutAnyOrigin]
    var get_buffer_info: OpaquePointer[MutAnyOrigin]
    var is_buffer: OpaquePointer[MutAnyOrigin]
    var create_typedarray: OpaquePointer[MutAnyOrigin]
    var get_typedarray_info: OpaquePointer[MutAnyOrigin]
    var is_typedarray: OpaquePointer[MutAnyOrigin]
    var define_class: OpaquePointer[MutAnyOrigin]
    var wrap: OpaquePointer[MutAnyOrigin]
    var unwrap: OpaquePointer[MutAnyOrigin]
    var remove_wrap: OpaquePointer[MutAnyOrigin]
    var new_instance: OpaquePointer[MutAnyOrigin]
    var create_function: OpaquePointer[MutAnyOrigin]
    var get_new_target: OpaquePointer[MutAnyOrigin]
    var get_global: OpaquePointer[MutAnyOrigin]
    var create_reference: OpaquePointer[MutAnyOrigin]
    var delete_reference: OpaquePointer[MutAnyOrigin]
    var reference_ref: OpaquePointer[MutAnyOrigin]
    var reference_unref: OpaquePointer[MutAnyOrigin]
    var get_reference_value: OpaquePointer[MutAnyOrigin]
    var open_escapable_handle_scope: OpaquePointer[MutAnyOrigin]
    var close_escapable_handle_scope: OpaquePointer[MutAnyOrigin]
    var escape_handle: OpaquePointer[MutAnyOrigin]
    var create_bigint_int64: OpaquePointer[MutAnyOrigin]
    var create_bigint_uint64: OpaquePointer[MutAnyOrigin]
    var get_value_bigint_int64: OpaquePointer[MutAnyOrigin]
    var get_value_bigint_uint64: OpaquePointer[MutAnyOrigin]
    var create_date: OpaquePointer[MutAnyOrigin]
    var get_date_value: OpaquePointer[MutAnyOrigin]
    var is_date: OpaquePointer[MutAnyOrigin]
    var create_symbol: OpaquePointer[MutAnyOrigin]
    var symbol_for: OpaquePointer[MutAnyOrigin]
    var get_property_names: OpaquePointer[MutAnyOrigin]
    var get_all_property_names: OpaquePointer[MutAnyOrigin]
    var has_own_property: OpaquePointer[MutAnyOrigin]
    var delete_property: OpaquePointer[MutAnyOrigin]
    var strict_equals: OpaquePointer[MutAnyOrigin]
    var instanceof_: OpaquePointer[MutAnyOrigin]
    var object_freeze: OpaquePointer[MutAnyOrigin]
    var object_seal: OpaquePointer[MutAnyOrigin]
    var has_element: OpaquePointer[MutAnyOrigin]
    var delete_element: OpaquePointer[MutAnyOrigin]
    var get_prototype: OpaquePointer[MutAnyOrigin]
    var create_threadsafe_function: OpaquePointer[MutAnyOrigin]
    var call_threadsafe_function: OpaquePointer[MutAnyOrigin]
    var acquire_threadsafe_function: OpaquePointer[MutAnyOrigin]
    var release_threadsafe_function: OpaquePointer[MutAnyOrigin]
    var create_external: OpaquePointer[MutAnyOrigin]
    var get_value_external: OpaquePointer[MutAnyOrigin]
    var get_version: OpaquePointer[MutAnyOrigin]
    var get_node_version: OpaquePointer[MutAnyOrigin]
    var set_property: OpaquePointer[MutAnyOrigin]
    var has_property: OpaquePointer[MutAnyOrigin]
    var throw_: OpaquePointer[MutAnyOrigin]
    var is_exception_pending: OpaquePointer[MutAnyOrigin]
    var get_and_clear_last_exception: OpaquePointer[MutAnyOrigin]
    var coerce_to_bool: OpaquePointer[MutAnyOrigin]
    var coerce_to_number: OpaquePointer[MutAnyOrigin]
    var coerce_to_string: OpaquePointer[MutAnyOrigin]
    var coerce_to_object: OpaquePointer[MutAnyOrigin]
    var create_dataview: OpaquePointer[MutAnyOrigin]
    var get_dataview_info: OpaquePointer[MutAnyOrigin]
    var is_dataview: OpaquePointer[MutAnyOrigin]
    var create_bigint_words: OpaquePointer[MutAnyOrigin]
    var get_value_bigint_words: OpaquePointer[MutAnyOrigin]
    var add_finalizer: OpaquePointer[MutAnyOrigin]
    var create_external_arraybuffer: OpaquePointer[MutAnyOrigin]
    var set_instance_data: OpaquePointer[MutAnyOrigin]
    var get_instance_data: OpaquePointer[MutAnyOrigin]
    var add_env_cleanup_hook: OpaquePointer[MutAnyOrigin]
    var remove_env_cleanup_hook: OpaquePointer[MutAnyOrigin]
    var cancel_async_work: OpaquePointer[MutAnyOrigin]
    # Phase 21-22 additions (119-127)
    var is_error: OpaquePointer[MutAnyOrigin]
    var adjust_external_memory: OpaquePointer[MutAnyOrigin]
    var run_script: OpaquePointer[MutAnyOrigin]
    var throw_syntax_error: OpaquePointer[MutAnyOrigin]
    var create_syntax_error: OpaquePointer[MutAnyOrigin]
    var is_detached_arraybuffer: OpaquePointer[MutAnyOrigin]
    var fatal_exception: OpaquePointer[MutAnyOrigin]
    var type_tag_object: OpaquePointer[MutAnyOrigin]
    var check_object_type_tag: OpaquePointer[MutAnyOrigin]
    # Non-function-pointer slot: ClassRegistry pointer (set after module init)
    var registry: OpaquePointer[MutAnyOrigin]

    fn __init__(out self):
        self.create_string_utf8 = OpaquePointer[MutAnyOrigin]()
        self.create_object = OpaquePointer[MutAnyOrigin]()
        self.set_named_property = OpaquePointer[MutAnyOrigin]()
        self.get_cb_info = OpaquePointer[MutAnyOrigin]()
        self.get_value_string_utf8 = OpaquePointer[MutAnyOrigin]()
        self.define_properties = OpaquePointer[MutAnyOrigin]()
        self.get_value_double = OpaquePointer[MutAnyOrigin]()
        self.create_double = OpaquePointer[MutAnyOrigin]()
        self.throw_error = OpaquePointer[MutAnyOrigin]()
        self.get_boolean = OpaquePointer[MutAnyOrigin]()
        self.get_value_bool = OpaquePointer[MutAnyOrigin]()
        self.typeof_ = OpaquePointer[MutAnyOrigin]()
        self.get_null = OpaquePointer[MutAnyOrigin]()
        self.get_undefined = OpaquePointer[MutAnyOrigin]()
        self.create_array_with_length = OpaquePointer[MutAnyOrigin]()
        self.set_element = OpaquePointer[MutAnyOrigin]()
        self.get_element = OpaquePointer[MutAnyOrigin]()
        self.get_array_length = OpaquePointer[MutAnyOrigin]()
        self.get_property = OpaquePointer[MutAnyOrigin]()
        self.is_array = OpaquePointer[MutAnyOrigin]()
        self.get_named_property = OpaquePointer[MutAnyOrigin]()
        self.has_named_property = OpaquePointer[MutAnyOrigin]()
        self.call_function = OpaquePointer[MutAnyOrigin]()
        self.open_handle_scope = OpaquePointer[MutAnyOrigin]()
        self.close_handle_scope = OpaquePointer[MutAnyOrigin]()
        self.create_promise = OpaquePointer[MutAnyOrigin]()
        self.resolve_deferred = OpaquePointer[MutAnyOrigin]()
        self.reject_deferred = OpaquePointer[MutAnyOrigin]()
        self.create_error = OpaquePointer[MutAnyOrigin]()
        self.create_async_work = OpaquePointer[MutAnyOrigin]()
        self.queue_async_work = OpaquePointer[MutAnyOrigin]()
        self.delete_async_work = OpaquePointer[MutAnyOrigin]()
        self.create_int32 = OpaquePointer[MutAnyOrigin]()
        self.get_value_int32 = OpaquePointer[MutAnyOrigin]()
        self.create_uint32 = OpaquePointer[MutAnyOrigin]()
        self.get_value_uint32 = OpaquePointer[MutAnyOrigin]()
        self.create_int64 = OpaquePointer[MutAnyOrigin]()
        self.get_value_int64 = OpaquePointer[MutAnyOrigin]()
        self.throw_type_error = OpaquePointer[MutAnyOrigin]()
        self.throw_range_error = OpaquePointer[MutAnyOrigin]()
        self.create_type_error = OpaquePointer[MutAnyOrigin]()
        self.create_range_error = OpaquePointer[MutAnyOrigin]()
        self.create_arraybuffer = OpaquePointer[MutAnyOrigin]()
        self.get_arraybuffer_info = OpaquePointer[MutAnyOrigin]()
        self.is_arraybuffer = OpaquePointer[MutAnyOrigin]()
        self.detach_arraybuffer = OpaquePointer[MutAnyOrigin]()
        self.create_buffer = OpaquePointer[MutAnyOrigin]()
        self.create_buffer_copy = OpaquePointer[MutAnyOrigin]()
        self.get_buffer_info = OpaquePointer[MutAnyOrigin]()
        self.is_buffer = OpaquePointer[MutAnyOrigin]()
        self.create_typedarray = OpaquePointer[MutAnyOrigin]()
        self.get_typedarray_info = OpaquePointer[MutAnyOrigin]()
        self.is_typedarray = OpaquePointer[MutAnyOrigin]()
        self.define_class = OpaquePointer[MutAnyOrigin]()
        self.wrap = OpaquePointer[MutAnyOrigin]()
        self.unwrap = OpaquePointer[MutAnyOrigin]()
        self.remove_wrap = OpaquePointer[MutAnyOrigin]()
        self.new_instance = OpaquePointer[MutAnyOrigin]()
        self.create_function = OpaquePointer[MutAnyOrigin]()
        self.get_new_target = OpaquePointer[MutAnyOrigin]()
        self.get_global = OpaquePointer[MutAnyOrigin]()
        self.create_reference = OpaquePointer[MutAnyOrigin]()
        self.delete_reference = OpaquePointer[MutAnyOrigin]()
        self.reference_ref = OpaquePointer[MutAnyOrigin]()
        self.reference_unref = OpaquePointer[MutAnyOrigin]()
        self.get_reference_value = OpaquePointer[MutAnyOrigin]()
        self.open_escapable_handle_scope = OpaquePointer[MutAnyOrigin]()
        self.close_escapable_handle_scope = OpaquePointer[MutAnyOrigin]()
        self.escape_handle = OpaquePointer[MutAnyOrigin]()
        self.create_bigint_int64 = OpaquePointer[MutAnyOrigin]()
        self.create_bigint_uint64 = OpaquePointer[MutAnyOrigin]()
        self.get_value_bigint_int64 = OpaquePointer[MutAnyOrigin]()
        self.get_value_bigint_uint64 = OpaquePointer[MutAnyOrigin]()
        self.create_date = OpaquePointer[MutAnyOrigin]()
        self.get_date_value = OpaquePointer[MutAnyOrigin]()
        self.is_date = OpaquePointer[MutAnyOrigin]()
        self.create_symbol = OpaquePointer[MutAnyOrigin]()
        self.symbol_for = OpaquePointer[MutAnyOrigin]()
        self.get_property_names = OpaquePointer[MutAnyOrigin]()
        self.get_all_property_names = OpaquePointer[MutAnyOrigin]()
        self.has_own_property = OpaquePointer[MutAnyOrigin]()
        self.delete_property = OpaquePointer[MutAnyOrigin]()
        self.strict_equals = OpaquePointer[MutAnyOrigin]()
        self.instanceof_ = OpaquePointer[MutAnyOrigin]()
        self.object_freeze = OpaquePointer[MutAnyOrigin]()
        self.object_seal = OpaquePointer[MutAnyOrigin]()
        self.has_element = OpaquePointer[MutAnyOrigin]()
        self.delete_element = OpaquePointer[MutAnyOrigin]()
        self.get_prototype = OpaquePointer[MutAnyOrigin]()
        self.create_threadsafe_function = OpaquePointer[MutAnyOrigin]()
        self.call_threadsafe_function = OpaquePointer[MutAnyOrigin]()
        self.acquire_threadsafe_function = OpaquePointer[MutAnyOrigin]()
        self.release_threadsafe_function = OpaquePointer[MutAnyOrigin]()
        self.create_external = OpaquePointer[MutAnyOrigin]()
        self.get_value_external = OpaquePointer[MutAnyOrigin]()
        self.get_version = OpaquePointer[MutAnyOrigin]()
        self.get_node_version = OpaquePointer[MutAnyOrigin]()
        self.set_property = OpaquePointer[MutAnyOrigin]()
        self.has_property = OpaquePointer[MutAnyOrigin]()
        self.throw_ = OpaquePointer[MutAnyOrigin]()
        self.is_exception_pending = OpaquePointer[MutAnyOrigin]()
        self.get_and_clear_last_exception = OpaquePointer[MutAnyOrigin]()
        self.coerce_to_bool = OpaquePointer[MutAnyOrigin]()
        self.coerce_to_number = OpaquePointer[MutAnyOrigin]()
        self.coerce_to_string = OpaquePointer[MutAnyOrigin]()
        self.coerce_to_object = OpaquePointer[MutAnyOrigin]()
        self.create_dataview = OpaquePointer[MutAnyOrigin]()
        self.get_dataview_info = OpaquePointer[MutAnyOrigin]()
        self.is_dataview = OpaquePointer[MutAnyOrigin]()
        self.create_bigint_words = OpaquePointer[MutAnyOrigin]()
        self.get_value_bigint_words = OpaquePointer[MutAnyOrigin]()
        self.add_finalizer = OpaquePointer[MutAnyOrigin]()
        self.create_external_arraybuffer = OpaquePointer[MutAnyOrigin]()
        self.set_instance_data = OpaquePointer[MutAnyOrigin]()
        self.get_instance_data = OpaquePointer[MutAnyOrigin]()
        self.add_env_cleanup_hook = OpaquePointer[MutAnyOrigin]()
        self.remove_env_cleanup_hook = OpaquePointer[MutAnyOrigin]()
        self.cancel_async_work = OpaquePointer[MutAnyOrigin]()
        self.is_error = OpaquePointer[MutAnyOrigin]()
        self.adjust_external_memory = OpaquePointer[MutAnyOrigin]()
        self.run_script = OpaquePointer[MutAnyOrigin]()
        self.throw_syntax_error = OpaquePointer[MutAnyOrigin]()
        self.create_syntax_error = OpaquePointer[MutAnyOrigin]()
        self.is_detached_arraybuffer = OpaquePointer[MutAnyOrigin]()
        self.fatal_exception = OpaquePointer[MutAnyOrigin]()
        self.type_tag_object = OpaquePointer[MutAnyOrigin]()
        self.check_object_type_tag = OpaquePointer[MutAnyOrigin]()
        self.registry = OpaquePointer[MutAnyOrigin]()

    fn __moveinit__(out self, deinit take: Self):
        self.create_string_utf8 = take.create_string_utf8
        self.create_object = take.create_object
        self.set_named_property = take.set_named_property
        self.get_cb_info = take.get_cb_info
        self.get_value_string_utf8 = take.get_value_string_utf8
        self.define_properties = take.define_properties
        self.get_value_double = take.get_value_double
        self.create_double = take.create_double
        self.throw_error = take.throw_error
        self.get_boolean = take.get_boolean
        self.get_value_bool = take.get_value_bool
        self.typeof_ = take.typeof_
        self.get_null = take.get_null
        self.get_undefined = take.get_undefined
        self.create_array_with_length = take.create_array_with_length
        self.set_element = take.set_element
        self.get_element = take.get_element
        self.get_array_length = take.get_array_length
        self.get_property = take.get_property
        self.is_array = take.is_array
        self.get_named_property = take.get_named_property
        self.has_named_property = take.has_named_property
        self.call_function = take.call_function
        self.open_handle_scope = take.open_handle_scope
        self.close_handle_scope = take.close_handle_scope
        self.create_promise = take.create_promise
        self.resolve_deferred = take.resolve_deferred
        self.reject_deferred = take.reject_deferred
        self.create_error = take.create_error
        self.create_async_work = take.create_async_work
        self.queue_async_work = take.queue_async_work
        self.delete_async_work = take.delete_async_work
        self.create_int32 = take.create_int32
        self.get_value_int32 = take.get_value_int32
        self.create_uint32 = take.create_uint32
        self.get_value_uint32 = take.get_value_uint32
        self.create_int64 = take.create_int64
        self.get_value_int64 = take.get_value_int64
        self.throw_type_error = take.throw_type_error
        self.throw_range_error = take.throw_range_error
        self.create_type_error = take.create_type_error
        self.create_range_error = take.create_range_error
        self.create_arraybuffer = take.create_arraybuffer
        self.get_arraybuffer_info = take.get_arraybuffer_info
        self.is_arraybuffer = take.is_arraybuffer
        self.detach_arraybuffer = take.detach_arraybuffer
        self.create_buffer = take.create_buffer
        self.create_buffer_copy = take.create_buffer_copy
        self.get_buffer_info = take.get_buffer_info
        self.is_buffer = take.is_buffer
        self.create_typedarray = take.create_typedarray
        self.get_typedarray_info = take.get_typedarray_info
        self.is_typedarray = take.is_typedarray
        self.define_class = take.define_class
        self.wrap = take.wrap
        self.unwrap = take.unwrap
        self.remove_wrap = take.remove_wrap
        self.new_instance = take.new_instance
        self.create_function = take.create_function
        self.get_new_target = take.get_new_target
        self.get_global = take.get_global
        self.create_reference = take.create_reference
        self.delete_reference = take.delete_reference
        self.reference_ref = take.reference_ref
        self.reference_unref = take.reference_unref
        self.get_reference_value = take.get_reference_value
        self.open_escapable_handle_scope = take.open_escapable_handle_scope
        self.close_escapable_handle_scope = take.close_escapable_handle_scope
        self.escape_handle = take.escape_handle
        self.create_bigint_int64 = take.create_bigint_int64
        self.create_bigint_uint64 = take.create_bigint_uint64
        self.get_value_bigint_int64 = take.get_value_bigint_int64
        self.get_value_bigint_uint64 = take.get_value_bigint_uint64
        self.create_date = take.create_date
        self.get_date_value = take.get_date_value
        self.is_date = take.is_date
        self.create_symbol = take.create_symbol
        self.symbol_for = take.symbol_for
        self.get_property_names = take.get_property_names
        self.get_all_property_names = take.get_all_property_names
        self.has_own_property = take.has_own_property
        self.delete_property = take.delete_property
        self.strict_equals = take.strict_equals
        self.instanceof_ = take.instanceof_
        self.object_freeze = take.object_freeze
        self.object_seal = take.object_seal
        self.has_element = take.has_element
        self.delete_element = take.delete_element
        self.get_prototype = take.get_prototype
        self.create_threadsafe_function = take.create_threadsafe_function
        self.call_threadsafe_function = take.call_threadsafe_function
        self.acquire_threadsafe_function = take.acquire_threadsafe_function
        self.release_threadsafe_function = take.release_threadsafe_function
        self.create_external = take.create_external
        self.get_value_external = take.get_value_external
        self.get_version = take.get_version
        self.get_node_version = take.get_node_version
        self.set_property = take.set_property
        self.has_property = take.has_property
        self.throw_ = take.throw_
        self.is_exception_pending = take.is_exception_pending
        self.get_and_clear_last_exception = take.get_and_clear_last_exception
        self.coerce_to_bool = take.coerce_to_bool
        self.coerce_to_number = take.coerce_to_number
        self.coerce_to_string = take.coerce_to_string
        self.coerce_to_object = take.coerce_to_object
        self.create_dataview = take.create_dataview
        self.get_dataview_info = take.get_dataview_info
        self.is_dataview = take.is_dataview
        self.create_bigint_words = take.create_bigint_words
        self.get_value_bigint_words = take.get_value_bigint_words
        self.add_finalizer = take.add_finalizer
        self.create_external_arraybuffer = take.create_external_arraybuffer
        self.set_instance_data = take.set_instance_data
        self.get_instance_data = take.get_instance_data
        self.add_env_cleanup_hook = take.add_env_cleanup_hook
        self.remove_env_cleanup_hook = take.remove_env_cleanup_hook
        self.cancel_async_work = take.cancel_async_work
        self.is_error = take.is_error
        self.adjust_external_memory = take.adjust_external_memory
        self.run_script = take.run_script
        self.throw_syntax_error = take.throw_syntax_error
        self.create_syntax_error = take.create_syntax_error
        self.is_detached_arraybuffer = take.is_detached_arraybuffer
        self.fatal_exception = take.fatal_exception
        self.type_tag_object = take.type_tag_object
        self.check_object_type_tag = take.check_object_type_tag
        self.registry = take.registry


comptime Bindings = UnsafePointer[NapiBindings, MutAnyOrigin]

fn init_bindings(mut bindings: NapiBindings) raises:
    """Resolve all 118 N-API symbols from the host process once."""
    var h = OwnedDLHandle()

    # 1. napi_create_string_utf8
    var _create_string_utf8 = h.get_function[
        fn (NapiEnv, OpaquePointer[ImmutAnyOrigin], UInt, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_string_utf8")
    bindings.create_string_utf8 = UnsafePointer(to=_create_string_utf8).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 2. napi_create_object
    var _create_object = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_object")
    bindings.create_object = UnsafePointer(to=_create_object).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 3. napi_set_named_property
    var _set_named_property = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[ImmutAnyOrigin], NapiValue) -> NapiStatus
    ]("napi_set_named_property")
    bindings.set_named_property = UnsafePointer(to=_set_named_property).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 4. napi_get_cb_info
    var _get_cb_info = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_cb_info")
    bindings.get_cb_info = UnsafePointer(to=_get_cb_info).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 5. napi_get_value_string_utf8
    var _get_value_string_utf8 = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin], UInt, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_value_string_utf8")
    bindings.get_value_string_utf8 = UnsafePointer(to=_get_value_string_utf8).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 6. napi_define_properties
    var _define_properties = h.get_function[
        fn (NapiEnv, NapiValue, UInt, OpaquePointer[ImmutAnyOrigin]) -> NapiStatus
    ]("napi_define_properties")
    bindings.define_properties = UnsafePointer(to=_define_properties).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 7. napi_get_value_double
    var _get_value_double = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_value_double")
    bindings.get_value_double = UnsafePointer(to=_get_value_double).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 8. napi_create_double
    var _create_double = h.get_function[
        fn (NapiEnv, Float64, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_double")
    bindings.create_double = UnsafePointer(to=_create_double).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 9. napi_throw_error
    var _throw_error = h.get_function[
        fn (NapiEnv, OpaquePointer[ImmutAnyOrigin], OpaquePointer[ImmutAnyOrigin]) -> NapiStatus
    ]("napi_throw_error")
    bindings.throw_error = UnsafePointer(to=_throw_error).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 10. napi_get_boolean
    var _get_boolean = h.get_function[
        fn (NapiEnv, Bool, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_boolean")
    bindings.get_boolean = UnsafePointer(to=_get_boolean).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 11. napi_get_value_bool
    var _get_value_bool = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_value_bool")
    bindings.get_value_bool = UnsafePointer(to=_get_value_bool).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 12. napi_typeof
    var _typeof = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_typeof")
    bindings.typeof_ = UnsafePointer(to=_typeof).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 13. napi_get_null
    var _get_null = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_null")
    bindings.get_null = UnsafePointer(to=_get_null).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 14. napi_get_undefined
    var _get_undefined = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_undefined")
    bindings.get_undefined = UnsafePointer(to=_get_undefined).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 15. napi_create_array_with_length
    var _create_array_with_length = h.get_function[
        fn (NapiEnv, UInt, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_array_with_length")
    bindings.create_array_with_length = UnsafePointer(to=_create_array_with_length).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 16. napi_set_element
    var _set_element = h.get_function[
        fn (NapiEnv, NapiValue, UInt32, NapiValue) -> NapiStatus
    ]("napi_set_element")
    bindings.set_element = UnsafePointer(to=_set_element).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 17. napi_get_element
    var _get_element = h.get_function[
        fn (NapiEnv, NapiValue, UInt32, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_element")
    bindings.get_element = UnsafePointer(to=_get_element).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 18. napi_get_array_length
    var _get_array_length = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_array_length")
    bindings.get_array_length = UnsafePointer(to=_get_array_length).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 19. napi_get_property
    var _get_property = h.get_function[
        fn (NapiEnv, NapiValue, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_property")
    bindings.get_property = UnsafePointer(to=_get_property).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 20. napi_is_array
    var _is_array = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_is_array")
    bindings.is_array = UnsafePointer(to=_is_array).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 21. napi_get_named_property
    var _get_named_property = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[ImmutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_named_property")
    bindings.get_named_property = UnsafePointer(to=_get_named_property).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 22. napi_has_named_property
    var _has_named_property = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[ImmutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_has_named_property")
    bindings.has_named_property = UnsafePointer(to=_has_named_property).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 23. napi_call_function
    var _call_function = h.get_function[
        fn (NapiEnv, NapiValue, NapiValue, UInt, OpaquePointer[ImmutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_call_function")
    bindings.call_function = UnsafePointer(to=_call_function).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 24. napi_open_handle_scope
    var _open_handle_scope = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_open_handle_scope")
    bindings.open_handle_scope = UnsafePointer(to=_open_handle_scope).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 25. napi_close_handle_scope
    var _close_handle_scope = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_close_handle_scope")
    bindings.close_handle_scope = UnsafePointer(to=_close_handle_scope).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 26. napi_create_promise
    var _create_promise = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_promise")
    bindings.create_promise = UnsafePointer(to=_create_promise).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 27. napi_resolve_deferred
    var _resolve_deferred = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin], NapiValue) -> NapiStatus
    ]("napi_resolve_deferred")
    bindings.resolve_deferred = UnsafePointer(to=_resolve_deferred).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 28. napi_reject_deferred
    var _reject_deferred = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin], NapiValue) -> NapiStatus
    ]("napi_reject_deferred")
    bindings.reject_deferred = UnsafePointer(to=_reject_deferred).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 29. napi_create_error
    var _create_error = h.get_function[
        fn (NapiEnv, NapiValue, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_error")
    bindings.create_error = UnsafePointer(to=_create_error).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 30. napi_create_async_work
    var _create_async_work = h.get_function[
        fn (NapiEnv, NapiValue, NapiValue, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_async_work")
    bindings.create_async_work = UnsafePointer(to=_create_async_work).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 31. napi_queue_async_work
    var _queue_async_work = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_queue_async_work")
    bindings.queue_async_work = UnsafePointer(to=_queue_async_work).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 32. napi_delete_async_work
    var _delete_async_work = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_delete_async_work")
    bindings.delete_async_work = UnsafePointer(to=_delete_async_work).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 33. napi_create_int32
    var _create_int32 = h.get_function[
        fn (NapiEnv, Int32, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_int32")
    bindings.create_int32 = UnsafePointer(to=_create_int32).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 34. napi_get_value_int32
    var _get_value_int32 = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_value_int32")
    bindings.get_value_int32 = UnsafePointer(to=_get_value_int32).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 35. napi_create_uint32
    var _create_uint32 = h.get_function[
        fn (NapiEnv, UInt32, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_uint32")
    bindings.create_uint32 = UnsafePointer(to=_create_uint32).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 36. napi_get_value_uint32
    var _get_value_uint32 = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_value_uint32")
    bindings.get_value_uint32 = UnsafePointer(to=_get_value_uint32).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 37. napi_create_int64
    var _create_int64 = h.get_function[
        fn (NapiEnv, Int64, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_int64")
    bindings.create_int64 = UnsafePointer(to=_create_int64).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 38. napi_get_value_int64
    var _get_value_int64 = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_value_int64")
    bindings.get_value_int64 = UnsafePointer(to=_get_value_int64).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 39. napi_throw_type_error
    var _throw_type_error = h.get_function[
        fn (NapiEnv, OpaquePointer[ImmutAnyOrigin], OpaquePointer[ImmutAnyOrigin]) -> NapiStatus
    ]("napi_throw_type_error")
    bindings.throw_type_error = UnsafePointer(to=_throw_type_error).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 40. napi_throw_range_error
    var _throw_range_error = h.get_function[
        fn (NapiEnv, OpaquePointer[ImmutAnyOrigin], OpaquePointer[ImmutAnyOrigin]) -> NapiStatus
    ]("napi_throw_range_error")
    bindings.throw_range_error = UnsafePointer(to=_throw_range_error).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 41. napi_create_type_error
    var _create_type_error = h.get_function[
        fn (NapiEnv, NapiValue, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_type_error")
    bindings.create_type_error = UnsafePointer(to=_create_type_error).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 42. napi_create_range_error
    var _create_range_error = h.get_function[
        fn (NapiEnv, NapiValue, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_range_error")
    bindings.create_range_error = UnsafePointer(to=_create_range_error).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 43. napi_create_arraybuffer
    var _create_arraybuffer = h.get_function[
        fn (NapiEnv, UInt, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_arraybuffer")
    bindings.create_arraybuffer = UnsafePointer(to=_create_arraybuffer).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 44. napi_get_arraybuffer_info
    var _get_arraybuffer_info = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_arraybuffer_info")
    bindings.get_arraybuffer_info = UnsafePointer(to=_get_arraybuffer_info).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 45. napi_is_arraybuffer
    var _is_arraybuffer = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_is_arraybuffer")
    bindings.is_arraybuffer = UnsafePointer(to=_is_arraybuffer).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 46. napi_detach_arraybuffer
    var _detach_arraybuffer = h.get_function[
        fn (NapiEnv, NapiValue) -> NapiStatus
    ]("napi_detach_arraybuffer")
    bindings.detach_arraybuffer = UnsafePointer(to=_detach_arraybuffer).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 47. napi_create_buffer
    var _create_buffer = h.get_function[
        fn (NapiEnv, UInt, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_buffer")
    bindings.create_buffer = UnsafePointer(to=_create_buffer).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 48. napi_create_buffer_copy
    var _create_buffer_copy = h.get_function[
        fn (NapiEnv, UInt, OpaquePointer[ImmutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_buffer_copy")
    bindings.create_buffer_copy = UnsafePointer(to=_create_buffer_copy).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 49. napi_get_buffer_info
    var _get_buffer_info = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_buffer_info")
    bindings.get_buffer_info = UnsafePointer(to=_get_buffer_info).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 50. napi_is_buffer
    var _is_buffer = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_is_buffer")
    bindings.is_buffer = UnsafePointer(to=_is_buffer).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 51. napi_create_typedarray
    var _create_typedarray = h.get_function[
        fn (NapiEnv, Int32, UInt, NapiValue, UInt, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_typedarray")
    bindings.create_typedarray = UnsafePointer(to=_create_typedarray).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 52. napi_get_typedarray_info
    var _get_typedarray_info = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_typedarray_info")
    bindings.get_typedarray_info = UnsafePointer(to=_get_typedarray_info).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 53. napi_is_typedarray
    var _is_typedarray = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_is_typedarray")
    bindings.is_typedarray = UnsafePointer(to=_is_typedarray).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 54. napi_define_class
    var _define_class = h.get_function[
        fn (NapiEnv, OpaquePointer[ImmutAnyOrigin], UInt, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], UInt, OpaquePointer[ImmutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_define_class")
    bindings.define_class = UnsafePointer(to=_define_class).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 55. napi_wrap
    var _wrap = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_wrap")
    bindings.wrap = UnsafePointer(to=_wrap).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 56. napi_unwrap
    var _unwrap = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_unwrap")
    bindings.unwrap = UnsafePointer(to=_unwrap).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 57. napi_remove_wrap
    var _remove_wrap = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_remove_wrap")
    bindings.remove_wrap = UnsafePointer(to=_remove_wrap).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 58. napi_new_instance
    var _new_instance = h.get_function[
        fn (NapiEnv, NapiValue, UInt, OpaquePointer[ImmutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_new_instance")
    bindings.new_instance = UnsafePointer(to=_new_instance).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 59. napi_create_function
    var _create_function = h.get_function[
        fn (NapiEnv, OpaquePointer[ImmutAnyOrigin], UInt, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_function")
    bindings.create_function = UnsafePointer(to=_create_function).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 60. napi_get_new_target
    var _get_new_target = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_new_target")
    bindings.get_new_target = UnsafePointer(to=_get_new_target).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 61. napi_get_global
    var _get_global = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_global")
    bindings.get_global = UnsafePointer(to=_get_global).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 62. napi_create_reference
    var _create_reference = h.get_function[
        fn (NapiEnv, NapiValue, UInt32, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_reference")
    bindings.create_reference = UnsafePointer(to=_create_reference).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 63. napi_delete_reference
    var _delete_reference = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_delete_reference")
    bindings.delete_reference = UnsafePointer(to=_delete_reference).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 64. napi_reference_ref
    var _reference_ref = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_reference_ref")
    bindings.reference_ref = UnsafePointer(to=_reference_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 65. napi_reference_unref
    var _reference_unref = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_reference_unref")
    bindings.reference_unref = UnsafePointer(to=_reference_unref).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 66. napi_get_reference_value
    var _get_reference_value = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_reference_value")
    bindings.get_reference_value = UnsafePointer(to=_get_reference_value).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 67. napi_open_escapable_handle_scope
    var _open_escapable_handle_scope = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_open_escapable_handle_scope")
    bindings.open_escapable_handle_scope = UnsafePointer(to=_open_escapable_handle_scope).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 68. napi_close_escapable_handle_scope
    var _close_escapable_handle_scope = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_close_escapable_handle_scope")
    bindings.close_escapable_handle_scope = UnsafePointer(to=_close_escapable_handle_scope).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 69. napi_escape_handle
    var _escape_handle = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin], NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_escape_handle")
    bindings.escape_handle = UnsafePointer(to=_escape_handle).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 70. napi_create_bigint_int64
    var _create_bigint_int64 = h.get_function[
        fn (NapiEnv, Int64, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_bigint_int64")
    bindings.create_bigint_int64 = UnsafePointer(to=_create_bigint_int64).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 71. napi_create_bigint_uint64
    var _create_bigint_uint64 = h.get_function[
        fn (NapiEnv, UInt64, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_bigint_uint64")
    bindings.create_bigint_uint64 = UnsafePointer(to=_create_bigint_uint64).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 72. napi_get_value_bigint_int64
    var _get_value_bigint_int64 = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_value_bigint_int64")
    bindings.get_value_bigint_int64 = UnsafePointer(to=_get_value_bigint_int64).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 73. napi_get_value_bigint_uint64
    var _get_value_bigint_uint64 = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_value_bigint_uint64")
    bindings.get_value_bigint_uint64 = UnsafePointer(to=_get_value_bigint_uint64).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 74. napi_create_date
    var _create_date = h.get_function[
        fn (NapiEnv, Float64, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_date")
    bindings.create_date = UnsafePointer(to=_create_date).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 75. napi_get_date_value
    var _get_date_value = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_date_value")
    bindings.get_date_value = UnsafePointer(to=_get_date_value).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 76. napi_is_date
    var _is_date = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_is_date")
    bindings.is_date = UnsafePointer(to=_is_date).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 77. napi_create_symbol
    var _create_symbol = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_symbol")
    bindings.create_symbol = UnsafePointer(to=_create_symbol).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 78. node_api_symbol_for
    var _symbol_for = h.get_function[
        fn (NapiEnv, OpaquePointer[ImmutAnyOrigin], UInt, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("node_api_symbol_for")
    bindings.symbol_for = UnsafePointer(to=_symbol_for).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 79. napi_get_property_names
    var _get_property_names = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_property_names")
    bindings.get_property_names = UnsafePointer(to=_get_property_names).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 80. napi_get_all_property_names
    var _get_all_property_names = h.get_function[
        fn (NapiEnv, NapiValue, Int32, Int32, Int32, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_all_property_names")
    bindings.get_all_property_names = UnsafePointer(to=_get_all_property_names).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 81. napi_has_own_property
    var _has_own_property = h.get_function[
        fn (NapiEnv, NapiValue, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_has_own_property")
    bindings.has_own_property = UnsafePointer(to=_has_own_property).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 82. napi_delete_property
    var _delete_property = h.get_function[
        fn (NapiEnv, NapiValue, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_delete_property")
    bindings.delete_property = UnsafePointer(to=_delete_property).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 83. napi_strict_equals
    var _strict_equals = h.get_function[
        fn (NapiEnv, NapiValue, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_strict_equals")
    bindings.strict_equals = UnsafePointer(to=_strict_equals).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 84. napi_instanceof
    var _instanceof = h.get_function[
        fn (NapiEnv, NapiValue, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_instanceof")
    bindings.instanceof_ = UnsafePointer(to=_instanceof).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 85. napi_object_freeze
    var _object_freeze = h.get_function[
        fn (NapiEnv, NapiValue) -> NapiStatus
    ]("napi_object_freeze")
    bindings.object_freeze = UnsafePointer(to=_object_freeze).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 86. napi_object_seal
    var _object_seal = h.get_function[
        fn (NapiEnv, NapiValue) -> NapiStatus
    ]("napi_object_seal")
    bindings.object_seal = UnsafePointer(to=_object_seal).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 87. napi_has_element
    var _has_element = h.get_function[
        fn (NapiEnv, NapiValue, UInt32, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_has_element")
    bindings.has_element = UnsafePointer(to=_has_element).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 88. napi_delete_element
    var _delete_element = h.get_function[
        fn (NapiEnv, NapiValue, UInt32, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_delete_element")
    bindings.delete_element = UnsafePointer(to=_delete_element).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 89. napi_get_prototype
    var _get_prototype = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_prototype")
    bindings.get_prototype = UnsafePointer(to=_get_prototype).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 90. napi_create_threadsafe_function
    var _create_threadsafe_function = h.get_function[
        fn (NapiEnv, NapiValue, NapiValue, NapiValue, UInt, UInt, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_threadsafe_function")
    bindings.create_threadsafe_function = UnsafePointer(to=_create_threadsafe_function).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 91. napi_call_threadsafe_function (no env param)
    var _call_threadsafe_function = h.get_function[
        fn (OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], Int32) -> NapiStatus
    ]("napi_call_threadsafe_function")
    bindings.call_threadsafe_function = UnsafePointer(to=_call_threadsafe_function).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 92. napi_acquire_threadsafe_function (no env param)
    var _acquire_threadsafe_function = h.get_function[
        fn (OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_acquire_threadsafe_function")
    bindings.acquire_threadsafe_function = UnsafePointer(to=_acquire_threadsafe_function).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 93. napi_release_threadsafe_function (no env param)
    var _release_threadsafe_function = h.get_function[
        fn (OpaquePointer[MutAnyOrigin], Int32) -> NapiStatus
    ]("napi_release_threadsafe_function")
    bindings.release_threadsafe_function = UnsafePointer(to=_release_threadsafe_function).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 94. napi_create_external
    var _create_external = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_external")
    bindings.create_external = UnsafePointer(to=_create_external).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 95. napi_get_value_external
    var _get_value_external = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_value_external")
    bindings.get_value_external = UnsafePointer(to=_get_value_external).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 96. napi_get_version
    var _get_version = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_version")
    bindings.get_version = UnsafePointer(to=_get_version).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 97. napi_get_node_version
    var _get_node_version = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_node_version")
    bindings.get_node_version = UnsafePointer(to=_get_node_version).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 98. napi_set_property
    var _set_property = h.get_function[
        fn (NapiEnv, NapiValue, NapiValue, NapiValue) -> NapiStatus
    ]("napi_set_property")
    bindings.set_property = UnsafePointer(to=_set_property).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 99. napi_has_property
    var _has_property = h.get_function[
        fn (NapiEnv, NapiValue, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_has_property")
    bindings.has_property = UnsafePointer(to=_has_property).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 100. napi_throw
    var _throw = h.get_function[
        fn (NapiEnv, NapiValue) -> NapiStatus
    ]("napi_throw")
    bindings.throw_ = UnsafePointer(to=_throw).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 101. napi_is_exception_pending
    var _is_exception_pending = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_is_exception_pending")
    bindings.is_exception_pending = UnsafePointer(to=_is_exception_pending).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 102. napi_get_and_clear_last_exception
    var _get_and_clear_last_exception = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_and_clear_last_exception")
    bindings.get_and_clear_last_exception = UnsafePointer(to=_get_and_clear_last_exception).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 103. napi_coerce_to_bool
    var _coerce_to_bool = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_coerce_to_bool")
    bindings.coerce_to_bool = UnsafePointer(to=_coerce_to_bool).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 104. napi_coerce_to_number
    var _coerce_to_number = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_coerce_to_number")
    bindings.coerce_to_number = UnsafePointer(to=_coerce_to_number).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 105. napi_coerce_to_string
    var _coerce_to_string = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_coerce_to_string")
    bindings.coerce_to_string = UnsafePointer(to=_coerce_to_string).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 106. napi_coerce_to_object
    var _coerce_to_object = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_coerce_to_object")
    bindings.coerce_to_object = UnsafePointer(to=_coerce_to_object).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 107. napi_create_dataview
    var _create_dataview = h.get_function[
        fn (NapiEnv, UInt, NapiValue, UInt, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_dataview")
    bindings.create_dataview = UnsafePointer(to=_create_dataview).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 108. napi_get_dataview_info
    var _get_dataview_info = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_dataview_info")
    bindings.get_dataview_info = UnsafePointer(to=_get_dataview_info).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 109. napi_is_dataview
    var _is_dataview = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_is_dataview")
    bindings.is_dataview = UnsafePointer(to=_is_dataview).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 110. napi_create_bigint_words
    var _create_bigint_words = h.get_function[
        fn (NapiEnv, Int32, UInt, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_bigint_words")
    bindings.create_bigint_words = UnsafePointer(to=_create_bigint_words).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 111. napi_get_value_bigint_words
    var _get_value_bigint_words = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_value_bigint_words")
    bindings.get_value_bigint_words = UnsafePointer(to=_get_value_bigint_words).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 112. napi_add_finalizer
    var _add_finalizer = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_add_finalizer")
    bindings.add_finalizer = UnsafePointer(to=_add_finalizer).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 113. napi_create_external_arraybuffer
    var _create_external_arraybuffer = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin], UInt, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_create_external_arraybuffer")
    bindings.create_external_arraybuffer = UnsafePointer(to=_create_external_arraybuffer).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 114. napi_set_instance_data
    var _set_instance_data = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_set_instance_data")
    bindings.set_instance_data = UnsafePointer(to=_set_instance_data).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 115. napi_get_instance_data
    var _get_instance_data = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_instance_data")
    bindings.get_instance_data = UnsafePointer(to=_get_instance_data).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 116. napi_add_env_cleanup_hook
    var _add_env_cleanup_hook = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_add_env_cleanup_hook")
    bindings.add_env_cleanup_hook = UnsafePointer(to=_add_env_cleanup_hook).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 117. napi_remove_env_cleanup_hook
    var _remove_env_cleanup_hook = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_remove_env_cleanup_hook")
    bindings.remove_env_cleanup_hook = UnsafePointer(to=_remove_env_cleanup_hook).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 118. napi_cancel_async_work
    var _cancel_async_work = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_cancel_async_work")
    bindings.cancel_async_work = UnsafePointer(to=_cancel_async_work).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 119. napi_is_error
    var _is_error = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_is_error")
    bindings.is_error = UnsafePointer(to=_is_error).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 120. napi_adjust_external_memory
    var _adjust_external_memory = h.get_function[
        fn (NapiEnv, Int64, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_adjust_external_memory")
    bindings.adjust_external_memory = UnsafePointer(to=_adjust_external_memory).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 121. napi_run_script
    var _run_script = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_run_script")
    bindings.run_script = UnsafePointer(to=_run_script).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 122. node_api_throw_syntax_error (N-API v9)
    var _throw_syntax_error = h.get_function[
        fn (NapiEnv, OpaquePointer[ImmutAnyOrigin], OpaquePointer[ImmutAnyOrigin]) -> NapiStatus
    ]("node_api_throw_syntax_error")
    bindings.throw_syntax_error = UnsafePointer(to=_throw_syntax_error).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 123. node_api_create_syntax_error (N-API v9)
    var _create_syntax_error = h.get_function[
        fn (NapiEnv, NapiValue, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("node_api_create_syntax_error")
    bindings.create_syntax_error = UnsafePointer(to=_create_syntax_error).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 124. napi_is_detached_arraybuffer (N-API v7)
    var _is_detached_arraybuffer = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_is_detached_arraybuffer")
    bindings.is_detached_arraybuffer = UnsafePointer(to=_is_detached_arraybuffer).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 125. napi_fatal_exception
    var _fatal_exception = h.get_function[
        fn (NapiEnv, NapiValue) -> NapiStatus
    ]("napi_fatal_exception")
    bindings.fatal_exception = UnsafePointer(to=_fatal_exception).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 126. napi_type_tag_object (N-API v8)
    var _type_tag_object = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[ImmutAnyOrigin]) -> NapiStatus
    ]("napi_type_tag_object")
    bindings.type_tag_object = UnsafePointer(to=_type_tag_object).bitcast[OpaquePointer[MutAnyOrigin]]()[]

    # 127. napi_check_object_type_tag (N-API v8)
    var _check_object_type_tag = h.get_function[
        fn (NapiEnv, NapiValue, OpaquePointer[ImmutAnyOrigin], OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_check_object_type_tag")
    bindings.check_object_type_tag = UnsafePointer(to=_check_object_type_tag).bitcast[OpaquePointer[MutAnyOrigin]]()[]


fn get_bindings(env: NapiEnv) raises -> Bindings:
    """Retrieve the NapiBindings pointer stored as instance data."""
    var h = OwnedDLHandle()
    var f = h.get_function[
        fn (NapiEnv, OpaquePointer[MutAnyOrigin]) -> NapiStatus
    ]("napi_get_instance_data")
    var data_ptr = OpaquePointer[MutAnyOrigin]()
    var out_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=data_ptr).bitcast[NoneType]()
    _ = f(env, out_ptr)
    return data_ptr.bitcast[NapiBindings]()
