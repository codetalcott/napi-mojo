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

from std.ffi import OwnedDLHandle
from std.sys.info import size_of
from napi.types import (
    NapiEnv,
    NapiValue,
    NapiStatus,
    NapiAsyncContext,
    NapiCallbackScope,
)


struct NapiBindings(Movable):
    # --- 143 fields: 142 resolved N-API symbols + the ClassRegistry pointer
    # (`registry`, below) which is not a symbol and is set after class setup ---
    @__allow_legacy_any_origin_fields
    var create_string_utf8: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var create_object: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var set_named_property: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var get_cb_info: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var get_value_string_utf8: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var define_properties: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var get_value_double: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var create_double: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var throw_error: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var get_boolean: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var get_value_bool: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var typeof_: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var get_null: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var get_undefined: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var create_array_with_length: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var set_element: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var get_element: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var get_array_length: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var get_property: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var is_array: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var get_named_property: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var has_named_property: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var call_function: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var open_handle_scope: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var close_handle_scope: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var create_promise: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var resolve_deferred: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var reject_deferred: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var create_error: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var create_async_work: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var queue_async_work: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var delete_async_work: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var create_int32: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var get_value_int32: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var create_uint32: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var get_value_uint32: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var create_int64: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var get_value_int64: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var throw_type_error: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var throw_range_error: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var create_type_error: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var create_range_error: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var create_arraybuffer: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var get_arraybuffer_info: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var is_arraybuffer: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var detach_arraybuffer: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var create_buffer: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var create_buffer_copy: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var get_buffer_info: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var is_buffer: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var create_typedarray: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var get_typedarray_info: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var is_typedarray: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var define_class: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var wrap: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var unwrap: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var remove_wrap: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var new_instance: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var create_function: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var get_new_target: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var get_global: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var create_reference: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var delete_reference: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var reference_ref: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var reference_unref: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var get_reference_value: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var open_escapable_handle_scope: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var close_escapable_handle_scope: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var escape_handle: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var create_bigint_int64: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var create_bigint_uint64: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var get_value_bigint_int64: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var get_value_bigint_uint64: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var create_date: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var get_date_value: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var is_date: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var create_symbol: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var symbol_for: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var get_property_names: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var get_all_property_names: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var has_own_property: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var delete_property: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var strict_equals: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var instanceof_: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var object_freeze: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var object_seal: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var has_element: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var delete_element: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var get_prototype: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var create_threadsafe_function: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var call_threadsafe_function: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var acquire_threadsafe_function: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var release_threadsafe_function: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var create_external: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var get_value_external: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var get_version: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var get_node_version: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var set_property: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var has_property: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var throw_: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var is_exception_pending: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var get_and_clear_last_exception: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var coerce_to_bool: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var coerce_to_number: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var coerce_to_string: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var coerce_to_object: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var create_dataview: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var get_dataview_info: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var is_dataview: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var create_bigint_words: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var get_value_bigint_words: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var add_finalizer: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var create_external_arraybuffer: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var set_instance_data: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var get_instance_data: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var add_env_cleanup_hook: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var remove_env_cleanup_hook: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var cancel_async_work: OpaquePointer[MutAnyOrigin]
    # Phase 21-22 additions (119-127)
    @__allow_legacy_any_origin_fields
    var is_error: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var adjust_external_memory: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var run_script: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var throw_syntax_error: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var create_syntax_error: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var is_detached_arraybuffer: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var fatal_exception: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var type_tag_object: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var check_object_type_tag: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var add_async_cleanup_hook: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var remove_async_cleanup_hook: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var get_uv_event_loop: OpaquePointer[MutAnyOrigin]
    # Phase C2 additions (131-133): async context + make_callback
    @__allow_legacy_any_origin_fields
    var async_init: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var async_destroy: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var make_callback: OpaquePointer[MutAnyOrigin]
    # Phase C3 additions (134-135): callback scope
    @__allow_legacy_any_origin_fields
    var open_callback_scope: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var close_callback_scope: OpaquePointer[MutAnyOrigin]
    # N-API v10 additions (136-141)
    @__allow_legacy_any_origin_fields
    var create_external_string_latin1: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var create_external_string_utf16: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var create_property_key_utf8: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var create_property_key_latin1: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var create_property_key_utf16: OpaquePointer[MutAnyOrigin]
    @__allow_legacy_any_origin_fields
    var create_buffer_from_arraybuffer: OpaquePointer[MutAnyOrigin]
    # Missing N-API v1 function (needed for external string Latin-1 path)
    @__allow_legacy_any_origin_fields
    var get_value_string_latin1: OpaquePointer[MutAnyOrigin]  # 142
    # Non-function-pointer slot: ClassRegistry pointer (set after module init)
    @__allow_legacy_any_origin_fields
    var registry: OpaquePointer[MutAnyOrigin]

    def __init__(out self):
        self.create_string_utf8 = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.create_object = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.set_named_property = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.get_cb_info = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.get_value_string_utf8 = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.define_properties = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.get_value_double = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.create_double = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.throw_error = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.get_boolean = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.get_value_bool = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.typeof_ = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.get_null = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.get_undefined = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.create_array_with_length = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.set_element = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.get_element = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.get_array_length = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.get_property = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.is_array = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.get_named_property = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.has_named_property = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.call_function = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.open_handle_scope = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.close_handle_scope = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.create_promise = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.resolve_deferred = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.reject_deferred = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.create_error = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.create_async_work = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.queue_async_work = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.delete_async_work = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.create_int32 = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.get_value_int32 = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.create_uint32 = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.get_value_uint32 = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.create_int64 = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.get_value_int64 = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.throw_type_error = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.throw_range_error = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.create_type_error = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.create_range_error = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.create_arraybuffer = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.get_arraybuffer_info = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.is_arraybuffer = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.detach_arraybuffer = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.create_buffer = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.create_buffer_copy = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.get_buffer_info = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.is_buffer = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.create_typedarray = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.get_typedarray_info = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.is_typedarray = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.define_class = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.wrap = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.unwrap = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.remove_wrap = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.new_instance = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.create_function = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.get_new_target = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.get_global = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.create_reference = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.delete_reference = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.reference_ref = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.reference_unref = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.get_reference_value = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.open_escapable_handle_scope = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.close_escapable_handle_scope = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.escape_handle = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.create_bigint_int64 = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.create_bigint_uint64 = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.get_value_bigint_int64 = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.get_value_bigint_uint64 = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.create_date = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.get_date_value = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.is_date = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.create_symbol = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.symbol_for = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.get_property_names = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.get_all_property_names = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.has_own_property = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.delete_property = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.strict_equals = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.instanceof_ = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.object_freeze = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.object_seal = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.has_element = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.delete_element = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.get_prototype = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.create_threadsafe_function = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.call_threadsafe_function = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.acquire_threadsafe_function = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.release_threadsafe_function = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.create_external = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.get_value_external = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.get_version = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.get_node_version = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.set_property = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.has_property = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.throw_ = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.is_exception_pending = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.get_and_clear_last_exception = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.coerce_to_bool = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.coerce_to_number = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.coerce_to_string = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.coerce_to_object = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.create_dataview = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.get_dataview_info = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.is_dataview = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.create_bigint_words = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.get_value_bigint_words = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.add_finalizer = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.create_external_arraybuffer = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.set_instance_data = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.get_instance_data = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.add_env_cleanup_hook = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.remove_env_cleanup_hook = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.cancel_async_work = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.is_error = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.adjust_external_memory = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.run_script = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.throw_syntax_error = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.create_syntax_error = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.is_detached_arraybuffer = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.fatal_exception = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.type_tag_object = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.check_object_type_tag = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.add_async_cleanup_hook = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.remove_async_cleanup_hook = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.get_uv_event_loop = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.async_init = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.async_destroy = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.make_callback = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.open_callback_scope = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.close_callback_scope = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.create_external_string_latin1 = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.create_external_string_utf16 = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.create_property_key_utf8 = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.create_property_key_latin1 = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.create_property_key_utf16 = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.create_buffer_from_arraybuffer = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.get_value_string_latin1 = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        self.registry = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))

    def __moveinit__(out self, deinit take: Self):
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
        self.add_async_cleanup_hook = take.add_async_cleanup_hook
        self.remove_async_cleanup_hook = take.remove_async_cleanup_hook
        self.get_uv_event_loop = take.get_uv_event_loop
        self.async_init = take.async_init
        self.async_destroy = take.async_destroy
        self.make_callback = take.make_callback
        self.open_callback_scope = take.open_callback_scope
        self.close_callback_scope = take.close_callback_scope
        self.create_external_string_latin1 = take.create_external_string_latin1
        self.create_external_string_utf16 = take.create_external_string_utf16
        self.create_property_key_utf8 = take.create_property_key_utf8
        self.create_property_key_latin1 = take.create_property_key_latin1
        self.create_property_key_utf16 = take.create_property_key_utf16
        self.create_buffer_from_arraybuffer = (
            take.create_buffer_from_arraybuffer
        )
        self.get_value_string_latin1 = take.get_value_string_latin1
        self.registry = take.registry


comptime Bindings = UnsafePointer[NapiBindings, MutAnyOrigin]


## _slot — resolve a host-process symbol straight into a cache slot.
##
## Note there is deliberately NO `UnsafePointer(to=...)` + bitcast here.
## `get_symbol` hands back the symbol's address as a value, and a cache slot
## IS that address, so the assignment is direct. The address-of-local
## reinterpret is only needed when you want a *callable* — see `_sym` in
## napi/raw.mojo, which is where the fn types now live.
##
## This is what makes the migration off `get_function` a net safety win: the
## old code took the address of a local holding the resolved pointer and
## reinterpreted that word as an opaque pointer. Had a nightly ever made a
## function reference fat, that erasure would have stored the wrong word and
## still compiled — a jump to garbage inside Node with no build failure. That
## failure mode no longer exists here. (`_sym` still needs the reinterpret, so
## `assert_fn_ptr_is_one_word` below keeps guarding it.)
##
## `.as_unsafe_any_origin()` is the explicit spelling of the
## MutUntrackedOrigin -> MutAnyOrigin widening the slot type requires. It is
## sound here for a reason specific to symbols: a symbol address is a static
## code address with no lifetime. This is NOT precedent for using
## UntrackedOrigin at the transient slot-cast sites elsewhere — see the
## AnyOrigin rule in CLAUDE.md.
@always_inline
def _slot(ref h: OwnedDLHandle, name: StaticString) raises -> OpaquePointer[
    MutAnyOrigin
]:
    var opt = h.get_symbol[NoneType](name)
    if opt is None:
        raise Error("napi-mojo: symbol not found: ", name)
    return opt.value().as_unsafe_any_origin()


## Compile-time guard for the whole cache design: 142 function pointers are
## type-erased into single-word OpaquePointer slots and reinterpreted back on
## every call. If a future nightly makes a `thin abi("C")` function reference
## fat, this fails the build instead of miscompiling into a runtime crash.
@always_inline
def assert_fn_ptr_is_one_word():
    comptime assert size_of[
        def(NapiEnv, OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ]() == size_of[OpaquePointer[MutAnyOrigin]](), (
        "a thin abi(C) fn ptr is no longer one machine word — the NapiBindings"
        " cache (fn ptr erased to OpaquePointer) is no longer sound"
    )


def init_bindings(mut bindings: NapiBindings) raises:
    """Resolve all 142 N-API symbols from the host process once."""
    assert_fn_ptr_is_one_word()
    var h = OwnedDLHandle()

    # 1. napi_create_string_utf8
    bindings.create_string_utf8 = _slot(h, "napi_create_string_utf8")

    # 2. napi_create_object
    bindings.create_object = _slot(h, "napi_create_object")

    # 3. napi_set_named_property
    bindings.set_named_property = _slot(h, "napi_set_named_property")

    # 4. napi_get_cb_info
    bindings.get_cb_info = _slot(h, "napi_get_cb_info")

    # 5. napi_get_value_string_utf8
    bindings.get_value_string_utf8 = _slot(h, "napi_get_value_string_utf8")

    # 6. napi_define_properties
    bindings.define_properties = _slot(h, "napi_define_properties")

    # 7. napi_get_value_double
    bindings.get_value_double = _slot(h, "napi_get_value_double")

    # 8. napi_create_double
    bindings.create_double = _slot(h, "napi_create_double")

    # 9. napi_throw_error
    bindings.throw_error = _slot(h, "napi_throw_error")

    # 10. napi_get_boolean
    bindings.get_boolean = _slot(h, "napi_get_boolean")

    # 11. napi_get_value_bool
    bindings.get_value_bool = _slot(h, "napi_get_value_bool")

    # 12. napi_typeof
    bindings.typeof_ = _slot(h, "napi_typeof")

    # 13. napi_get_null
    bindings.get_null = _slot(h, "napi_get_null")

    # 14. napi_get_undefined
    bindings.get_undefined = _slot(h, "napi_get_undefined")

    # 15. napi_create_array_with_length
    bindings.create_array_with_length = _slot(h, "napi_create_array_with_length")

    # 16. napi_set_element
    bindings.set_element = _slot(h, "napi_set_element")

    # 17. napi_get_element
    bindings.get_element = _slot(h, "napi_get_element")

    # 18. napi_get_array_length
    bindings.get_array_length = _slot(h, "napi_get_array_length")

    # 19. napi_get_property
    bindings.get_property = _slot(h, "napi_get_property")

    # 20. napi_is_array
    bindings.is_array = _slot(h, "napi_is_array")

    # 21. napi_get_named_property
    bindings.get_named_property = _slot(h, "napi_get_named_property")

    # 22. napi_has_named_property
    bindings.has_named_property = _slot(h, "napi_has_named_property")

    # 23. napi_call_function
    bindings.call_function = _slot(h, "napi_call_function")

    # 24. napi_open_handle_scope
    bindings.open_handle_scope = _slot(h, "napi_open_handle_scope")

    # 25. napi_close_handle_scope
    bindings.close_handle_scope = _slot(h, "napi_close_handle_scope")

    # 26. napi_create_promise
    bindings.create_promise = _slot(h, "napi_create_promise")

    # 27. napi_resolve_deferred
    bindings.resolve_deferred = _slot(h, "napi_resolve_deferred")

    # 28. napi_reject_deferred
    bindings.reject_deferred = _slot(h, "napi_reject_deferred")

    # 29. napi_create_error
    bindings.create_error = _slot(h, "napi_create_error")

    # 30. napi_create_async_work
    bindings.create_async_work = _slot(h, "napi_create_async_work")

    # 31. napi_queue_async_work
    bindings.queue_async_work = _slot(h, "napi_queue_async_work")

    # 32. napi_delete_async_work
    bindings.delete_async_work = _slot(h, "napi_delete_async_work")

    # 33. napi_create_int32
    bindings.create_int32 = _slot(h, "napi_create_int32")

    # 34. napi_get_value_int32
    bindings.get_value_int32 = _slot(h, "napi_get_value_int32")

    # 35. napi_create_uint32
    bindings.create_uint32 = _slot(h, "napi_create_uint32")

    # 36. napi_get_value_uint32
    bindings.get_value_uint32 = _slot(h, "napi_get_value_uint32")

    # 37. napi_create_int64
    bindings.create_int64 = _slot(h, "napi_create_int64")

    # 38. napi_get_value_int64
    bindings.get_value_int64 = _slot(h, "napi_get_value_int64")

    # 39. napi_throw_type_error
    bindings.throw_type_error = _slot(h, "napi_throw_type_error")

    # 40. napi_throw_range_error
    bindings.throw_range_error = _slot(h, "napi_throw_range_error")

    # 41. napi_create_type_error
    bindings.create_type_error = _slot(h, "napi_create_type_error")

    # 42. napi_create_range_error
    bindings.create_range_error = _slot(h, "napi_create_range_error")

    # 43. napi_create_arraybuffer
    bindings.create_arraybuffer = _slot(h, "napi_create_arraybuffer")

    # 44. napi_get_arraybuffer_info
    bindings.get_arraybuffer_info = _slot(h, "napi_get_arraybuffer_info")

    # 45. napi_is_arraybuffer
    bindings.is_arraybuffer = _slot(h, "napi_is_arraybuffer")

    # 46. napi_detach_arraybuffer
    bindings.detach_arraybuffer = _slot(h, "napi_detach_arraybuffer")

    # 47. napi_create_buffer
    bindings.create_buffer = _slot(h, "napi_create_buffer")

    # 48. napi_create_buffer_copy
    bindings.create_buffer_copy = _slot(h, "napi_create_buffer_copy")

    # 49. napi_get_buffer_info
    bindings.get_buffer_info = _slot(h, "napi_get_buffer_info")

    # 50. napi_is_buffer
    bindings.is_buffer = _slot(h, "napi_is_buffer")

    # 51. napi_create_typedarray
    bindings.create_typedarray = _slot(h, "napi_create_typedarray")

    # 52. napi_get_typedarray_info
    bindings.get_typedarray_info = _slot(h, "napi_get_typedarray_info")

    # 53. napi_is_typedarray
    bindings.is_typedarray = _slot(h, "napi_is_typedarray")

    # 54. napi_define_class
    bindings.define_class = _slot(h, "napi_define_class")

    # 55. napi_wrap
    bindings.wrap = _slot(h, "napi_wrap")

    # 56. napi_unwrap
    bindings.unwrap = _slot(h, "napi_unwrap")

    # 57. napi_remove_wrap
    bindings.remove_wrap = _slot(h, "napi_remove_wrap")

    # 58. napi_new_instance
    bindings.new_instance = _slot(h, "napi_new_instance")

    # 59. napi_create_function
    bindings.create_function = _slot(h, "napi_create_function")

    # 60. napi_get_new_target
    bindings.get_new_target = _slot(h, "napi_get_new_target")

    # 61. napi_get_global
    bindings.get_global = _slot(h, "napi_get_global")

    # 62. napi_create_reference
    bindings.create_reference = _slot(h, "napi_create_reference")

    # 63. napi_delete_reference
    bindings.delete_reference = _slot(h, "napi_delete_reference")

    # 64. napi_reference_ref
    bindings.reference_ref = _slot(h, "napi_reference_ref")

    # 65. napi_reference_unref
    bindings.reference_unref = _slot(h, "napi_reference_unref")

    # 66. napi_get_reference_value
    bindings.get_reference_value = _slot(h, "napi_get_reference_value")

    # 67. napi_open_escapable_handle_scope
    bindings.open_escapable_handle_scope = _slot(h, "napi_open_escapable_handle_scope")

    # 68. napi_close_escapable_handle_scope
    bindings.close_escapable_handle_scope = _slot(h, "napi_close_escapable_handle_scope")

    # 69. napi_escape_handle
    bindings.escape_handle = _slot(h, "napi_escape_handle")

    # 70. napi_create_bigint_int64
    bindings.create_bigint_int64 = _slot(h, "napi_create_bigint_int64")

    # 71. napi_create_bigint_uint64
    bindings.create_bigint_uint64 = _slot(h, "napi_create_bigint_uint64")

    # 72. napi_get_value_bigint_int64
    bindings.get_value_bigint_int64 = _slot(h, "napi_get_value_bigint_int64")

    # 73. napi_get_value_bigint_uint64
    bindings.get_value_bigint_uint64 = _slot(h, "napi_get_value_bigint_uint64")

    # 74. napi_create_date
    bindings.create_date = _slot(h, "napi_create_date")

    # 75. napi_get_date_value
    bindings.get_date_value = _slot(h, "napi_get_date_value")

    # 76. napi_is_date
    bindings.is_date = _slot(h, "napi_is_date")

    # 77. napi_create_symbol
    bindings.create_symbol = _slot(h, "napi_create_symbol")

    # 78. node_api_symbol_for
    bindings.symbol_for = _slot(h, "node_api_symbol_for")

    # 79. napi_get_property_names
    bindings.get_property_names = _slot(h, "napi_get_property_names")

    # 80. napi_get_all_property_names
    bindings.get_all_property_names = _slot(h, "napi_get_all_property_names")

    # 81. napi_has_own_property
    bindings.has_own_property = _slot(h, "napi_has_own_property")

    # 82. napi_delete_property
    bindings.delete_property = _slot(h, "napi_delete_property")

    # 83. napi_strict_equals
    bindings.strict_equals = _slot(h, "napi_strict_equals")

    # 84. napi_instanceof
    bindings.instanceof_ = _slot(h, "napi_instanceof")

    # 85. napi_object_freeze
    bindings.object_freeze = _slot(h, "napi_object_freeze")

    # 86. napi_object_seal
    bindings.object_seal = _slot(h, "napi_object_seal")

    # 87. napi_has_element
    bindings.has_element = _slot(h, "napi_has_element")

    # 88. napi_delete_element
    bindings.delete_element = _slot(h, "napi_delete_element")

    # 89. napi_get_prototype
    bindings.get_prototype = _slot(h, "napi_get_prototype")

    # 90. napi_create_threadsafe_function
    bindings.create_threadsafe_function = _slot(h, "napi_create_threadsafe_function")

    # 91. napi_call_threadsafe_function (no env param)
    bindings.call_threadsafe_function = _slot(h, "napi_call_threadsafe_function")

    # 92. napi_acquire_threadsafe_function (no env param)
    bindings.acquire_threadsafe_function = _slot(h, "napi_acquire_threadsafe_function")

    # 93. napi_release_threadsafe_function (no env param)
    bindings.release_threadsafe_function = _slot(h, "napi_release_threadsafe_function")

    # 94. napi_create_external
    bindings.create_external = _slot(h, "napi_create_external")

    # 95. napi_get_value_external
    bindings.get_value_external = _slot(h, "napi_get_value_external")

    # 96. napi_get_version
    bindings.get_version = _slot(h, "napi_get_version")

    # 97. napi_get_node_version
    bindings.get_node_version = _slot(h, "napi_get_node_version")

    # 98. napi_set_property
    bindings.set_property = _slot(h, "napi_set_property")

    # 99. napi_has_property
    bindings.has_property = _slot(h, "napi_has_property")

    # 100. napi_throw
    bindings.throw_ = _slot(h, "napi_throw")

    # 101. napi_is_exception_pending
    bindings.is_exception_pending = _slot(h, "napi_is_exception_pending")

    # 102. napi_get_and_clear_last_exception
    bindings.get_and_clear_last_exception = _slot(h, "napi_get_and_clear_last_exception")

    # 103. napi_coerce_to_bool
    bindings.coerce_to_bool = _slot(h, "napi_coerce_to_bool")

    # 104. napi_coerce_to_number
    bindings.coerce_to_number = _slot(h, "napi_coerce_to_number")

    # 105. napi_coerce_to_string
    bindings.coerce_to_string = _slot(h, "napi_coerce_to_string")

    # 106. napi_coerce_to_object
    bindings.coerce_to_object = _slot(h, "napi_coerce_to_object")

    # 107. napi_create_dataview
    bindings.create_dataview = _slot(h, "napi_create_dataview")

    # 108. napi_get_dataview_info
    bindings.get_dataview_info = _slot(h, "napi_get_dataview_info")

    # 109. napi_is_dataview
    bindings.is_dataview = _slot(h, "napi_is_dataview")

    # 110. napi_create_bigint_words
    bindings.create_bigint_words = _slot(h, "napi_create_bigint_words")

    # 111. napi_get_value_bigint_words
    bindings.get_value_bigint_words = _slot(h, "napi_get_value_bigint_words")

    # 112. napi_add_finalizer
    bindings.add_finalizer = _slot(h, "napi_add_finalizer")

    # 113. napi_create_external_arraybuffer
    bindings.create_external_arraybuffer = _slot(h, "napi_create_external_arraybuffer")

    # 114. napi_set_instance_data
    bindings.set_instance_data = _slot(h, "napi_set_instance_data")

    # 115. napi_get_instance_data
    bindings.get_instance_data = _slot(h, "napi_get_instance_data")

    # 116. napi_add_env_cleanup_hook
    bindings.add_env_cleanup_hook = _slot(h, "napi_add_env_cleanup_hook")

    # 117. napi_remove_env_cleanup_hook
    bindings.remove_env_cleanup_hook = _slot(h, "napi_remove_env_cleanup_hook")

    # 118. napi_cancel_async_work
    bindings.cancel_async_work = _slot(h, "napi_cancel_async_work")

    # 119. napi_is_error
    bindings.is_error = _slot(h, "napi_is_error")

    # 120. napi_adjust_external_memory
    bindings.adjust_external_memory = _slot(h, "napi_adjust_external_memory")

    # 121. napi_run_script
    bindings.run_script = _slot(h, "napi_run_script")

    # 122. node_api_throw_syntax_error (N-API v9)
    bindings.throw_syntax_error = _slot(h, "node_api_throw_syntax_error")

    # 123. node_api_create_syntax_error (N-API v9)
    bindings.create_syntax_error = _slot(h, "node_api_create_syntax_error")

    # 124. napi_is_detached_arraybuffer (N-API v7)
    bindings.is_detached_arraybuffer = _slot(h, "napi_is_detached_arraybuffer")

    # 125. napi_fatal_exception
    bindings.fatal_exception = _slot(h, "napi_fatal_exception")

    # 126. napi_type_tag_object (N-API v8)
    bindings.type_tag_object = _slot(h, "napi_type_tag_object")

    # 127. napi_check_object_type_tag (N-API v8)
    bindings.check_object_type_tag = _slot(h, "napi_check_object_type_tag")

    # 128. napi_add_async_cleanup_hook (N-API v8)
    # hook: fn(handle, arg), arg: void*, remove_handle: out *
    bindings.add_async_cleanup_hook = _slot(h, "napi_add_async_cleanup_hook")

    # 129. napi_remove_async_cleanup_hook (N-API v8)
    # Takes only the handle (no env) — can be called from any thread
    bindings.remove_async_cleanup_hook = _slot(h, "napi_remove_async_cleanup_hook")

    # 130. napi_get_uv_event_loop (N-API v2)
    # Returns the uv_loop_t* for the current environment
    bindings.get_uv_event_loop = _slot(h, "napi_get_uv_event_loop")

    # 131. napi_async_init (N-API v1)
    # Creates an async context for async_hooks tracking.
    # async_resource: JS object representing the resource (or undefined)
    # async_resource_name: string identifying the resource type
    bindings.async_init = _slot(h, "napi_async_init")

    # 132. napi_async_destroy (N-API v1)
    # Destroys an async context previously created with napi_async_init.
    bindings.async_destroy = _slot(h, "napi_async_destroy")

    # 133. napi_make_callback (N-API v1)
    # Calls a JS function in the given async context, correctly propagating
    # AsyncLocalStorage and async_hooks tracking.
    bindings.make_callback = _slot(h, "napi_make_callback")

    # 134. napi_open_callback_scope (N-API v3)
    # Opens a callback scope, setting up the async context for synchronous
    # N-API calls (needed for correct async_hooks integration).
    bindings.open_callback_scope = _slot(h, "napi_open_callback_scope")

    # 135. napi_close_callback_scope (N-API v3)
    # Closes a callback scope previously opened with napi_open_callback_scope.
    bindings.close_callback_scope = _slot(h, "napi_close_callback_scope")

    # N-API v10 additions (136-141)

    # 136. node_api_create_external_string_latin1 (N-API v10)
    # Creates a JS string backed by a native Latin-1 buffer without copying.
    # finalize_cb fires when the string is GC'd; copied_out indicates if a copy was forced.
    bindings.create_external_string_latin1 = _slot(h, "node_api_create_external_string_latin1")

    # 137. node_api_create_external_string_utf16 (N-API v10)
    # Creates a JS string backed by a native UTF-16LE buffer without copying.
    bindings.create_external_string_utf16 = _slot(h, "node_api_create_external_string_utf16")

    # 138. node_api_create_property_key_utf8 (N-API v10)
    # Creates an engine-internalized string from UTF-8 for use as a property key.
    # More efficient than napi_create_string_utf8 for repeated property access.
    bindings.create_property_key_utf8 = _slot(h, "node_api_create_property_key_utf8")

    # 139. node_api_create_property_key_latin1 (N-API v10)
    # Creates an engine-internalized string from Latin-1 for use as a property key.
    bindings.create_property_key_latin1 = _slot(h, "node_api_create_property_key_latin1")

    # 140. node_api_create_property_key_utf16 (N-API v10)
    # Creates an engine-internalized string from UTF-16LE for use as a property key.
    bindings.create_property_key_utf16 = _slot(h, "node_api_create_property_key_utf16")

    # 141. node_api_create_buffer_from_arraybuffer (N-API v10)
    # Creates a zero-copy Node.js Buffer view into a slice of an existing ArrayBuffer.
    # Raises RangeError if offset+length exceeds the ArrayBuffer bounds.
    bindings.create_buffer_from_arraybuffer = _slot(h, "node_api_create_buffer_from_arraybuffer")

    # 142. napi_get_value_string_latin1 (N-API v1)
    # Reads a JS string as Latin-1 (ISO-8859-1) bytes.
    # Same signature as napi_get_value_string_utf8 but output is single-byte Latin-1.
    bindings.get_value_string_latin1 = _slot(h, "napi_get_value_string_latin1")


def get_bindings(env: NapiEnv) raises -> Bindings:
    """Retrieve the NapiBindings pointer stored as instance data."""
    var h = OwnedDLHandle()
    var f = _sym[
        def(NapiEnv, OpaquePointer[MutAnyOrigin]) thin abi("C") -> NapiStatus
    ](h, "napi_get_instance_data")
    var data_ptr = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
    var out_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
        to=data_ptr
    ).bitcast[NoneType]()
    _ = f(env, out_ptr)
    return data_ptr.bitcast[NapiBindings]()
