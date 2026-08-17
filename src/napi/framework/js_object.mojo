## src/napi/framework/js_object.mojo — ergonomic wrapper for JavaScript object values
##
## JsObject hides the raw pointer operations needed to create and mutate a JS
## object, giving addon authors a clean API:
##
##   var obj = JsObject.create(b, env)
##   var msg = JsString.create_literal(b, env, "Hello!")
##   obj.set_property(b, env, "message", msg.value)  # StringLiteral key (preferred)
##   return obj.value
##
##   # Heap String key (use when key is computed at runtime):
##   var key = String("message")
##   obj.set_named_property(b, env, key, msg.value)
##
## Heap String keys are converted to a length-delimited JS string key
## internally (napi_create_string_utf8 + napi_set/get_property), never
## handed to the C-string napi_*_named_property API: a heap Mojo String has
## no guaranteed NUL terminator, so strlen-based APIs would read out of
## bounds. set_property takes a StringLiteral (static, NUL-terminated
## .rodata), which the C-string API handles safely.

from std.collections import Optional
from napi.types import (
    NapiEnv,
    NapiValue,
    NAPI_KEY_OWN_ONLY,
    NAPI_KEY_ENUMERABLE,
    NAPI_KEY_SKIP_SYMBOLS,
    NAPI_KEY_NUMBERS_TO_STRINGS,
)
from napi.bindings import Bindings
from napi.raw import (
    raw_create_object,
    raw_create_string_utf8,
    raw_set_named_property,
    raw_get_named_property,
    raw_has_named_property,
    raw_get_property,
    raw_set_property,
    raw_has_property,
    raw_get_property_names,
    raw_get_all_property_names,
    raw_has_own_property,
    raw_delete_property,
    raw_instanceof,
    raw_object_freeze,
    raw_object_seal,
    raw_get_prototype,
)
from napi.error import check_status


def _named_key(b: Bindings, env: NapiEnv, name: String) raises -> NapiValue:
    var result: NapiValue = NapiValue(unsafe_from_address=Int(0))
    var str_ptr: OpaquePointer[ImmutAnyOrigin] = name.unsafe_ptr().unsafe_bitcast[
        NoneType
    ]().as_unsafe_any_origin()
    var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
        to=result
    ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
    var status = raw_create_string_utf8(
        b, env, str_ptr, UInt(name.byte_length()), result_ptr
    )
    check_status(status)
    return result


## JsObject — typed wrapper for a JavaScript object napi_value
struct JsObject:
    ## The underlying napi_value handle. Valid within the current handle scope.
    @__allow_legacy_any_origin_fields
    var value: NapiValue

    def __init__(out self, value: NapiValue):
        self.value = value

    # --- Bindings-aware overloads ---

    @staticmethod
    def create(b: Bindings, env: NapiEnv) raises -> JsObject:
        var result: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=result
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var status = raw_create_object(b, env, result_ptr)
        check_status(status)
        return JsObject(result)

    def set_property(
        self, b: Bindings, env: NapiEnv, key: StringLiteral, val: NapiValue
    ) raises:
        var key_ptr: OpaquePointer[ImmutAnyOrigin] = key.unsafe_ptr().unsafe_bitcast[
            NoneType
        ]().as_unsafe_any_origin()
        var status = raw_set_named_property(b, env, self.value, key_ptr, val)
        check_status(status)

    def set_named_property(
        self, b: Bindings, env: NapiEnv, name: String, val: NapiValue
    ) raises:
        var key = _named_key(b, env, name)
        var status = raw_set_property(b, env, self.value, key, val)
        check_status(status)

    def set(
        self, b: Bindings, env: NapiEnv, key: NapiValue, val: NapiValue
    ) raises:
        var status = raw_set_property(b, env, self.value, key, val)
        check_status(status)

    def has(self, b: Bindings, env: NapiEnv, key: NapiValue) raises -> Bool:
        var exists: Bool = False
        var exists_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=exists
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var status = raw_has_property(b, env, self.value, key, exists_ptr)
        check_status(status)
        return exists

    def get(
        self, b: Bindings, env: NapiEnv, key: NapiValue
    ) raises -> NapiValue:
        var result: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=result
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var status = raw_get_property(b, env, self.value, key, result_ptr)
        check_status(status)
        return result

    def get_property(
        self, b: Bindings, env: NapiEnv, key: StringLiteral
    ) raises -> NapiValue:
        var result: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var key_ptr: OpaquePointer[ImmutAnyOrigin] = key.unsafe_ptr().unsafe_bitcast[
            NoneType
        ]().as_unsafe_any_origin()
        var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=result
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var status = raw_get_named_property(
            b, env, self.value, key_ptr, result_ptr
        )
        check_status(status)
        return result

    def get_named_property(
        self, b: Bindings, env: NapiEnv, name: String
    ) raises -> NapiValue:
        var key = _named_key(b, env, name)
        var result: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=result
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var status = raw_get_property(b, env, self.value, key, result_ptr)
        check_status(status)
        return result

    def has_property(
        self, b: Bindings, env: NapiEnv, key: StringLiteral
    ) raises -> Bool:
        var exists: Bool = False
        var key_ptr: OpaquePointer[ImmutAnyOrigin] = key.unsafe_ptr().unsafe_bitcast[
            NoneType
        ]().as_unsafe_any_origin()
        var exists_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=exists
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var status = raw_has_named_property(
            b, env, self.value, key_ptr, exists_ptr
        )
        check_status(status)
        return exists

    def get_opt(
        self, b: Bindings, env: NapiEnv, key: StringLiteral
    ) raises -> Optional[NapiValue]:
        if not self.has_property(b, env, key):
            return None
        return self.get_property(b, env, key)

    def keys(self, b: Bindings, env: NapiEnv) raises -> NapiValue:
        var result: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=result
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var status = raw_get_all_property_names(
            b,
            env,
            self.value,
            NAPI_KEY_OWN_ONLY,
            NAPI_KEY_ENUMERABLE | NAPI_KEY_SKIP_SYMBOLS,
            NAPI_KEY_NUMBERS_TO_STRINGS,
            result_ptr,
        )
        check_status(status)
        return result

    ## keys_filtered — full-parameter napi_get_all_property_names exposure
    def keys_filtered(
        self,
        b: Bindings,
        env: NapiEnv,
        mode: Int32,
        filter: Int32,
        conversion: Int32,
    ) raises -> NapiValue:
        var result: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=result
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        check_status(
            raw_get_all_property_names(
                b, env, self.value, mode, filter, conversion, result_ptr
            )
        )
        return result

    def has_own(self, b: Bindings, env: NapiEnv, key: NapiValue) raises -> Bool:
        var exists: Bool = False
        var exists_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=exists
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var status = raw_has_own_property(b, env, self.value, key, exists_ptr)
        check_status(status)
        return exists

    def delete_prop(
        self, b: Bindings, env: NapiEnv, key: NapiValue
    ) raises -> Bool:
        var deleted: Bool = False
        var deleted_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=deleted
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var status = raw_delete_property(b, env, self.value, key, deleted_ptr)
        check_status(status)
        return deleted

    def instance_of(
        self, b: Bindings, env: NapiEnv, constructor: NapiValue
    ) raises -> Bool:
        var result: Bool = False
        var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=result
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var status = raw_instanceof(b, env, self.value, constructor, result_ptr)
        check_status(status)
        return result

    def freeze(self, b: Bindings, env: NapiEnv) raises:
        var status = raw_object_freeze(b, env, self.value)
        check_status(status)

    def seal(self, b: Bindings, env: NapiEnv) raises:
        var status = raw_object_seal(b, env, self.value)
        check_status(status)

    def prototype(self, b: Bindings, env: NapiEnv) raises -> NapiValue:
        var result: NapiValue = NapiValue(unsafe_from_address=Int(0))
        var result_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=result
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var status = raw_get_prototype(b, env, self.value, result_ptr)
        check_status(status)
        return result
