## src/addon/misc_ops.mojo — exceptions, version info, error utils,
##                           detach/type-tag, property enumeration

from std.memory import alloc
from napi.types import NapiEnv, NapiValue, NapiTypeTag
from napi.bindings import Bindings
from napi.error import throw_js_error, throw_js_syntax_error, check_status
from napi.raw import raw_type_tag_object, raw_check_object_type_tag
from napi.framework.js_boolean import JsBoolean
from napi.framework.js_number import JsNumber
from napi.framework.js_object import JsObject
from napi.framework.js_string import JsString, js_to_string
from napi.framework.js_null import JsNull
from napi.framework.js_arraybuffer import JsArrayBuffer
from napi.framework.args import CbArgs
from napi.framework.js_value import (
    js_is_error,
    js_adjust_external_memory,
    js_run_script,
)
from napi.framework.js_exception import (
    js_throw,
    js_get_and_clear_last_exception,
    js_get_error_message,
    js_get_error_stack,
)
from napi.framework.js_version import get_napi_version, get_node_version_ptr
from napi.framework.register import fn_ptr, ModuleBuilder


def throw_value_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        js_throw(b, env, arg0)
    except:
        pass
    return NapiValue()


def catch_and_return_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        js_throw(b, env, arg0)
        var caught = js_get_and_clear_last_exception(b, env)
        return caught
    except:
        return NapiValue()


def get_napi_version_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var ver = get_napi_version(b, env)
        return JsNumber.create_int(b, env, Int(ver)).value
    except:
        throw_js_error(env, "getNapiVersion failed")
        return NapiValue()


def get_node_version_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var ver = get_node_version_ptr(b, env)
        var obj = JsObject.create(b, env)
        obj.set_property(
            b, env, "major", JsNumber.create_int(b, env, Int(ver[0])).value
        )
        obj.set_property(
            b, env, "minor", JsNumber.create_int(b, env, Int(ver[1])).value
        )
        obj.set_property(
            b, env, "patch", JsNumber.create_int(b, env, Int(ver[2])).value
        )
        return obj.value
    except:
        throw_js_error(env, "getNodeVersion failed")
        return NapiValue()


def is_error_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        return JsBoolean.create(b, env, js_is_error(b, env, arg0)).value
    except:
        throw_js_error(env, "isError requires one argument")
        return NapiValue()


def adjust_external_memory_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var change = JsNumber.from_napi_value(b, env, arg0)
        var result = js_adjust_external_memory(b, env, Int64(Int(change)))
        return JsNumber.create(b, env, Float64(Int(result))).value
    except:
        throw_js_error(env, "adjustExternalMemory failed")
        return NapiValue()


def run_script_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        return js_run_script(b, env, arg0)
    except:
        throw_js_error(env, "runScript failed")
        return NapiValue()


def throw_syntax_error_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        throw_js_syntax_error(b, env, "test syntax error")
    except:
        throw_js_error(env, "throwSyntaxError failed")
    return NapiValue()


def is_detached_arraybuffer_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        return JsBoolean.create(
            b, env, JsArrayBuffer.is_detached(b, env, arg0)
        ).value
    except:
        throw_js_error(env, "isDetachedArrayBuffer failed")
        return NapiValue()


def detach_arraybuffer_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var ab = JsArrayBuffer(arg0)
        ab.detach(b, env)
        return JsBoolean.create(b, env, True).value
    except:
        throw_js_error(env, "detachArrayBuffer failed")
        return NapiValue()


def type_tag_object_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var argc = CbArgs.argc(b, env, info)
        var argv = alloc[NapiValue](Int(argc))
        CbArgs.get_argv(b, env, info, argc, argv)
        var obj = argv[0]
        var lower = UInt64(Int(JsNumber.from_napi_value(b, env, argv[1])))
        var upper = UInt64(Int(JsNumber.from_napi_value(b, env, argv[2])))
        argv.free()
        var tag = NapiTypeTag(lower, upper)
        var tag_ptr: OpaquePointer[ImmutAnyOrigin] = UnsafePointer(
            to=tag
        ).bitcast[NoneType]()
        check_status(raw_type_tag_object(b, env, obj, tag_ptr))
        return JsBoolean.create(b, env, True).value
    except:
        throw_js_error(env, "typeTagObject failed")
        return NapiValue()


def check_object_type_tag_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var argc = CbArgs.argc(b, env, info)
        var argv = alloc[NapiValue](Int(argc))
        CbArgs.get_argv(b, env, info, argc, argv)
        var obj = argv[0]
        var lower = UInt64(Int(JsNumber.from_napi_value(b, env, argv[1])))
        var upper = UInt64(Int(JsNumber.from_napi_value(b, env, argv[2])))
        argv.free()
        var tag = NapiTypeTag(lower, upper)
        var tag_ptr: OpaquePointer[ImmutAnyOrigin] = UnsafePointer(
            to=tag
        ).bitcast[NoneType]()
        var result: Bool = False
        check_status(
            raw_check_object_type_tag(
                b,
                env,
                obj,
                tag_ptr,
                UnsafePointer(to=result).bitcast[NoneType](),
            )
        )
        return JsBoolean.create(b, env, result).value
    except:
        throw_js_error(env, "checkObjectTypeTag failed")
        return NapiValue()


def get_all_property_names_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var argc: UInt = 4
        var argv = alloc[NapiValue](4)
        CbArgs.get_argv(b, env, info, argc, argv)
        var obj = argv[0]
        var mode = Int32(Int(JsNumber.from_napi_value(b, env, argv[1])))
        var filter = Int32(Int(JsNumber.from_napi_value(b, env, argv[2])))
        var conversion = Int32(Int(JsNumber.from_napi_value(b, env, argv[3])))
        argv.free()
        var result = JsObject(obj).keys_filtered(
            b, env, mode, filter, conversion
        )
        return result
    except:
        throw_js_error(env, "getAllPropertyNames failed")
        return NapiValue()


def get_error_message_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var msg = js_get_error_message(b, env, arg0)
        return JsString.create(b, env, msg).value
    except:
        throw_js_error(env, "getErrorMessage failed")
        return NapiValue()


def get_error_stack_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var stack = js_get_error_stack(b, env, arg0)
        return JsString.create(b, env, stack).value
    except:
        throw_js_error(env, "getErrorStack failed")
        return NapiValue()


def get_opt_value_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var maybe = JsObject(arg0).get_opt(b, env, "x")
        if not maybe:
            return JsNull.create(b, env).value
        return maybe.value()
    except:
        throw_js_error(env, "getOptValue failed")
        return NapiValue()


def to_js_string_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var s = js_to_string(b, env, arg0)
        return JsString.create(b, env, s).value
    except:
        throw_js_error(env, "toJsString failed")
        return NapiValue()


## createPropertyKey — create an engine-internalized property key string (N-API v10)
##
## Accepts a JS string, creates an internalized key, and returns it as a JS string.
## The returned value is typeof 'string' and compares equal to the input. Its
## advantage is V8 interning: repeated napi_get/set_property calls using this key
## skip the string hash lookup, giving faster property access in hot paths.
def create_property_key_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var s = JsString.from_napi_value(b, env, arg0)
        return JsString.create_property_key(b, env, s).value
    except:
        throw_js_error(env, "createPropertyKey requires a string argument")
        return NapiValue()


def register_misc(mut m: ModuleBuilder) raises:
    var throw_value_ref = throw_value_fn
    var catch_and_return_ref = catch_and_return_fn
    var get_napi_version_ref = get_napi_version_fn
    var get_node_version_ref = get_node_version_fn
    var is_error_ref = is_error_fn
    var adjust_external_memory_ref = adjust_external_memory_fn
    var run_script_ref = run_script_fn
    var throw_syntax_error_ref = throw_syntax_error_fn
    var is_detached_arraybuffer_ref = is_detached_arraybuffer_fn
    var detach_arraybuffer_ref = detach_arraybuffer_fn
    var type_tag_object_ref = type_tag_object_fn
    var check_object_type_tag_ref = check_object_type_tag_fn
    var get_all_property_names_ref = get_all_property_names_fn
    var get_error_message_ref = get_error_message_fn
    var get_error_stack_ref = get_error_stack_fn
    var get_opt_value_ref = get_opt_value_fn
    var to_js_string_ref = to_js_string_fn
    var create_property_key_ref = create_property_key_fn
    m.method("throwValue", fn_ptr(throw_value_ref))
    m.method("catchAndReturn", fn_ptr(catch_and_return_ref))
    m.method("getNapiVersion", fn_ptr(get_napi_version_ref))
    m.method("getNodeVersion", fn_ptr(get_node_version_ref))
    m.method("isError", fn_ptr(is_error_ref))
    m.method("adjustExternalMemory", fn_ptr(adjust_external_memory_ref))
    m.method("runScript", fn_ptr(run_script_ref))
    m.method("throwSyntaxError", fn_ptr(throw_syntax_error_ref))
    m.method("isDetachedArrayBuffer", fn_ptr(is_detached_arraybuffer_ref))
    m.method("detachArrayBuffer", fn_ptr(detach_arraybuffer_ref))
    m.method("typeTagObject", fn_ptr(type_tag_object_ref))
    m.method("checkObjectTypeTag", fn_ptr(check_object_type_tag_ref))
    m.method("getAllPropertyNames", fn_ptr(get_all_property_names_ref))
    m.method("getErrorMessage", fn_ptr(get_error_message_ref))
    m.method("getErrorStack", fn_ptr(get_error_stack_ref))
    m.method("getOptValue", fn_ptr(get_opt_value_ref))
    m.method("toJsString", fn_ptr(to_js_string_ref))
    m.method("createPropertyKey", fn_ptr(create_property_key_ref))
