## src/napi/framework/js_object.mojo — ergonomic wrapper for JavaScript object values
##
## JsObject hides the raw pointer operations needed to create and mutate a JS
## object, giving addon authors a clean API:
##
##   var obj = JsObject.create(env)
##   var msg = JsString.create_literal(env, "Hello!")
##   obj.set_property(env, "message", msg.value)     # StringLiteral key (preferred)
##   return obj.value
##
##   # Heap String key (use when key is computed at runtime):
##   var key = String("message")
##   obj.set_named_property(env, key, msg.value)
##
## String lifetime: property name strings passed to set_named_property must
## remain alive for the duration of the call. Use named `var` bindings.
## set_property takes a StringLiteral (static lifetime), so no lifetime
## management is needed on the caller side.

from std.collections import Optional
from napi.types import NapiEnv, NapiValue, NAPI_KEY_OWN_ONLY, NAPI_KEY_ENUMERABLE, NAPI_KEY_SKIP_SYMBOLS, NAPI_KEY_NUMBERS_TO_STRINGS
from napi.bindings import Bindings
from napi.raw import raw_create_object, raw_set_named_property, raw_get_named_property, raw_has_named_property, raw_get_property, raw_set_property, raw_has_property, raw_get_property_names, raw_get_all_property_names, raw_has_own_property, raw_delete_property, raw_instanceof, raw_object_freeze, raw_object_seal, raw_get_prototype
from napi.error import check_status

## JsObject — typed wrapper for a JavaScript object napi_value
struct JsObject:
    ## The underlying napi_value handle. Valid within the current handle scope.
    var value: NapiValue

    fn __init__(out self, value: NapiValue):
        self.value = value

    ## create — construct a new empty JavaScript object {}
    ##
    ## Calls napi_create_object and checks the status.
    @staticmethod
    fn create(env: NapiEnv) raises -> JsObject:
        var result: NapiValue = NapiValue()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
        var status = raw_create_object(env, result_ptr)
        check_status(status)
        return JsObject(result)

    ## set_property — set a named property using a StringLiteral key
    ##
    ## Preferred overload for compile-time-known property names. Uses the
    ## literal's static (.rodata) pointer directly — no heap allocation,
    ## no ASAP lifetime concern.
    fn set_property(self, env: NapiEnv, key: StringLiteral, val: NapiValue) raises:
        var key_ptr: OpaquePointer[ImmutAnyOrigin] = key.unsafe_ptr().bitcast[NoneType]()
        var status = raw_set_named_property(env, self.value, key_ptr, val)
        check_status(status)

    ## set_named_property — set a named property using a heap String key
    ##
    ## Use when the property name is computed at runtime. `name` is borrowed —
    ## the caller's String must remain alive for the duration of this call
    ## (use a named `var`).
    fn set_named_property(self, env: NapiEnv, name: String, val: NapiValue) raises:
        var name_ptr: OpaquePointer[ImmutAnyOrigin] = name.unsafe_ptr().bitcast[NoneType]()
        var status = raw_set_named_property(env, self.value, name_ptr, val)
        check_status(status)

    ## set — set a property using a napi_value key (string, symbol, etc.)
    ##
    ## Most general form for setting properties — works with any key type.
    ## Use set_property() for StringLiteral keys or set_named_property() for
    ## heap String keys.
    fn set(self, env: NapiEnv, key: NapiValue, val: NapiValue) raises:
        var status = raw_set_property(env, self.value, key, val)
        check_status(status)

    ## has — check if a property exists using a napi_value key
    ##
    ## Walks the prototype chain (like `key in obj`). Use has_own() to check
    ## own properties only.
    fn has(self, env: NapiEnv, key: NapiValue) raises -> Bool:
        var exists: Bool = False
        var exists_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=exists).bitcast[NoneType]()
        var status = raw_has_property(env, self.value, key, exists_ptr)
        check_status(status)
        return exists

    ## get — read a property using a napi_value key
    ##
    ## Most general form — works with any key type (string, symbol, etc.).
    ## Pass the JS key napi_value directly; avoids any string conversion.
    fn get(self, env: NapiEnv, key: NapiValue) raises -> NapiValue:
        var result: NapiValue = NapiValue()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
        var status = raw_get_property(env, self.value, key, result_ptr)
        check_status(status)
        return result

    ## get_property — read a named property using a StringLiteral key
    ##
    ## Preferred overload for compile-time-known property names. Returns the
    ## property's napi_value (undefined if the property does not exist).
    fn get_property(self, env: NapiEnv, key: StringLiteral) raises -> NapiValue:
        var result: NapiValue = NapiValue()
        var key_ptr: OpaquePointer[ImmutAnyOrigin] = key.unsafe_ptr().bitcast[NoneType]()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
        var status = raw_get_named_property(env, self.value, key_ptr, result_ptr)
        check_status(status)
        return result

    ## get_named_property — read a named property using a heap String key
    ##
    ## Use when the property name is computed at runtime. `name` is borrowed —
    ## the caller's String must remain alive for the duration of this call.
    fn get_named_property(self, env: NapiEnv, name: String) raises -> NapiValue:
        var name_ptr: OpaquePointer[ImmutAnyOrigin] = name.unsafe_ptr().bitcast[NoneType]()
        var result: NapiValue = NapiValue()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
        var status = raw_get_named_property(env, self.value, name_ptr, result_ptr)
        check_status(status)
        return result

    ## has_property — check if a named property exists (StringLiteral key)
    ##
    ## Returns true if the property exists on the object, false otherwise.
    fn has_property(self, env: NapiEnv, key: StringLiteral) raises -> Bool:
        var exists: Bool = False
        var key_ptr: OpaquePointer[ImmutAnyOrigin] = key.unsafe_ptr().bitcast[NoneType]()
        var exists_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=exists).bitcast[NoneType]()
        var status = raw_has_named_property(env, self.value, key_ptr, exists_ptr)
        check_status(status)
        return exists

    ## get_opt — read a property only if the key exists
    ##
    ## Checks existence via napi_has_named_property first. Returns
    ## Optional[NapiValue](value) if present, or None if absent.
    ## Useful when you must distinguish "key missing" from "key=undefined".
    fn get_opt(self, env: NapiEnv, key: StringLiteral) raises -> Optional[NapiValue]:
        if not self.has_property(env, key):
            return None
        return self.get_property(env, key)

    ## keys — return the object's own enumerable property names as a JS array
    ##
    ## Uses napi_get_all_property_names with own-only + enumerable filter.
    ## Equivalent to Object.keys(obj).
    fn keys(self, env: NapiEnv) raises -> NapiValue:
        var result: NapiValue = NapiValue()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
        var status = raw_get_all_property_names(
            env, self.value,
            NAPI_KEY_OWN_ONLY,
            NAPI_KEY_ENUMERABLE | NAPI_KEY_SKIP_SYMBOLS,
            NAPI_KEY_NUMBERS_TO_STRINGS,
            result_ptr,
        )
        check_status(status)
        return result

    ## has_own — check if the object has the key as an own (non-inherited) property
    ##
    ## Calls napi_has_own_property. Key must be a napi_value (string or symbol).
    fn has_own(self, env: NapiEnv, key: NapiValue) raises -> Bool:
        var exists: Bool = False
        var exists_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=exists).bitcast[NoneType]()
        var status = raw_has_own_property(env, self.value, key, exists_ptr)
        check_status(status)
        return exists

    ## delete_prop — delete a property by napi_value key
    ##
    ## Calls napi_delete_property. Returns true if the property was deleted.
    fn delete_prop(self, env: NapiEnv, key: NapiValue) raises -> Bool:
        var deleted: Bool = False
        var deleted_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=deleted).bitcast[NoneType]()
        var status = raw_delete_property(env, self.value, key, deleted_ptr)
        check_status(status)
        return deleted

    ## instance_of — check if this value is an instance of a constructor
    ##
    ## Calls napi_instanceof.
    fn instance_of(self, env: NapiEnv, constructor: NapiValue) raises -> Bool:
        var result: Bool = False
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
        var status = raw_instanceof(env, self.value, constructor, result_ptr)
        check_status(status)
        return result

    ## freeze — freeze the object (prevent all modifications)
    ##
    ## Calls napi_object_freeze (N-API v8+).
    fn freeze(self, env: NapiEnv) raises:
        var status = raw_object_freeze(env, self.value)
        check_status(status)

    ## seal — seal the object (prevent adding/deleting properties)
    ##
    ## Calls napi_object_seal (N-API v8+).
    fn seal(self, env: NapiEnv) raises:
        var status = raw_object_seal(env, self.value)
        check_status(status)

    ## prototype — return the prototype of this object
    ##
    ## Calls napi_get_prototype. Returns null for Object.create(null).
    fn prototype(self, env: NapiEnv) raises -> NapiValue:
        var result: NapiValue = NapiValue()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
        var status = raw_get_prototype(env, self.value, result_ptr)
        check_status(status)
        return result

    # --- Bindings-aware overloads ---

    @staticmethod
    fn create(b: Bindings, env: NapiEnv) raises -> JsObject:
        var result: NapiValue = NapiValue()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
        var status = raw_create_object(b, env, result_ptr)
        check_status(status)
        return JsObject(result)

    fn set_property(self, b: Bindings, env: NapiEnv, key: StringLiteral, val: NapiValue) raises:
        var key_ptr: OpaquePointer[ImmutAnyOrigin] = key.unsafe_ptr().bitcast[NoneType]()
        var status = raw_set_named_property(b, env, self.value, key_ptr, val)
        check_status(status)

    fn set_named_property(self, b: Bindings, env: NapiEnv, name: String, val: NapiValue) raises:
        var name_ptr: OpaquePointer[ImmutAnyOrigin] = name.unsafe_ptr().bitcast[NoneType]()
        var status = raw_set_named_property(b, env, self.value, name_ptr, val)
        check_status(status)

    fn set(self, b: Bindings, env: NapiEnv, key: NapiValue, val: NapiValue) raises:
        var status = raw_set_property(b, env, self.value, key, val)
        check_status(status)

    fn has(self, b: Bindings, env: NapiEnv, key: NapiValue) raises -> Bool:
        var exists: Bool = False
        var exists_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=exists).bitcast[NoneType]()
        var status = raw_has_property(b, env, self.value, key, exists_ptr)
        check_status(status)
        return exists

    fn get(self, b: Bindings, env: NapiEnv, key: NapiValue) raises -> NapiValue:
        var result: NapiValue = NapiValue()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
        var status = raw_get_property(b, env, self.value, key, result_ptr)
        check_status(status)
        return result

    fn get_property(self, b: Bindings, env: NapiEnv, key: StringLiteral) raises -> NapiValue:
        var result: NapiValue = NapiValue()
        var key_ptr: OpaquePointer[ImmutAnyOrigin] = key.unsafe_ptr().bitcast[NoneType]()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
        var status = raw_get_named_property(b, env, self.value, key_ptr, result_ptr)
        check_status(status)
        return result

    fn get_named_property(self, b: Bindings, env: NapiEnv, name: String) raises -> NapiValue:
        var name_ptr: OpaquePointer[ImmutAnyOrigin] = name.unsafe_ptr().bitcast[NoneType]()
        var result: NapiValue = NapiValue()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
        var status = raw_get_named_property(b, env, self.value, name_ptr, result_ptr)
        check_status(status)
        return result

    fn has_property(self, b: Bindings, env: NapiEnv, key: StringLiteral) raises -> Bool:
        var exists: Bool = False
        var key_ptr: OpaquePointer[ImmutAnyOrigin] = key.unsafe_ptr().bitcast[NoneType]()
        var exists_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=exists).bitcast[NoneType]()
        var status = raw_has_named_property(b, env, self.value, key_ptr, exists_ptr)
        check_status(status)
        return exists

    fn get_opt(self, b: Bindings, env: NapiEnv, key: StringLiteral) raises -> Optional[NapiValue]:
        if not self.has_property(b, env, key):
            return None
        return self.get_property(b, env, key)

    fn keys(self, b: Bindings, env: NapiEnv) raises -> NapiValue:
        var result: NapiValue = NapiValue()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
        var status = raw_get_all_property_names(
            b, env, self.value,
            NAPI_KEY_OWN_ONLY,
            NAPI_KEY_ENUMERABLE | NAPI_KEY_SKIP_SYMBOLS,
            NAPI_KEY_NUMBERS_TO_STRINGS,
            result_ptr,
        )
        check_status(status)
        return result

    ## keys_filtered — full-parameter napi_get_all_property_names exposure
    fn keys_filtered(self, b: Bindings, env: NapiEnv, mode: Int32, filter: Int32, conversion: Int32) raises -> NapiValue:
        var result: NapiValue = NapiValue()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
        check_status(raw_get_all_property_names(b, env, self.value, mode, filter, conversion, result_ptr))
        return result

    fn has_own(self, b: Bindings, env: NapiEnv, key: NapiValue) raises -> Bool:
        var exists: Bool = False
        var exists_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=exists).bitcast[NoneType]()
        var status = raw_has_own_property(b, env, self.value, key, exists_ptr)
        check_status(status)
        return exists

    fn delete_prop(self, b: Bindings, env: NapiEnv, key: NapiValue) raises -> Bool:
        var deleted: Bool = False
        var deleted_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=deleted).bitcast[NoneType]()
        var status = raw_delete_property(b, env, self.value, key, deleted_ptr)
        check_status(status)
        return deleted

    fn instance_of(self, b: Bindings, env: NapiEnv, constructor: NapiValue) raises -> Bool:
        var result: Bool = False
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
        var status = raw_instanceof(b, env, self.value, constructor, result_ptr)
        check_status(status)
        return result

    fn freeze(self, b: Bindings, env: NapiEnv) raises:
        var status = raw_object_freeze(b, env, self.value)
        check_status(status)

    fn seal(self, b: Bindings, env: NapiEnv) raises:
        var status = raw_object_seal(b, env, self.value)
        check_status(status)

    fn prototype(self, b: Bindings, env: NapiEnv) raises -> NapiValue:
        var result: NapiValue = NapiValue()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
        var status = raw_get_prototype(b, env, self.value, result_ptr)
        check_status(status)
        return result
