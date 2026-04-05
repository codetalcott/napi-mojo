## src/addon/ref_ops.mojo — JsRef and EscapableHandleScope demos

from napi.types import NapiEnv, NapiValue
from napi.bindings import Bindings
from napi.error import throw_js_error
from napi.framework.js_object import JsObject
from napi.framework.js_number import JsNumber
from napi.framework.js_boolean import JsBoolean
from napi.framework.js_string import JsString
from napi.framework.js_ref import JsRef
from napi.framework.escapable_handle_scope import EscapableHandleScope
from napi.framework.args import CbArgs
from napi.framework.register import fn_ptr, ModuleBuilder


def test_ref_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var obj = JsObject.create(b, env)
        obj.set_property(b, env, "value", JsNumber.create(b, env, 42.0).value)
        var js_ref = JsRef.create(b, env, obj.value, 1)
        var retrieved = JsObject(js_ref.get(b, env))
        js_ref.delete(b, env)
        return retrieved.get_named_property(b, env, "value")
    except:
        throw_js_error(env, "testRef failed")
        return NapiValue()


def test_ref_object_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var obj = JsObject.create(b, env)
        obj.set_property(b, env, "answer", JsNumber.create(b, env, 42.0).value)
        var js_ref = JsRef.create(b, env, obj.value, 1)
        var val = js_ref.get(b, env)
        js_ref.delete(b, env)
        return val
    except:
        throw_js_error(env, "testRefObject failed")
        return NapiValue()


def test_ref_string_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var obj = JsObject.create(b, env)
        obj.set_property(b, env, "value", arg0)
        var js_ref = JsRef.create(b, env, obj.value, 1)
        var retrieved = JsObject(js_ref.get(b, env))
        js_ref.delete(b, env)
        return retrieved.get_named_property(b, env, "value")
    except:
        throw_js_error(env, "testRefString requires one string argument")
        return NapiValue()


def build_in_scope_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var esc = EscapableHandleScope.open(b, env)
        var obj = JsObject.create(b, env)
        obj.set_property(
            b, env, "created", JsBoolean.create(b, env, True).value
        )
        obj.set_property(b, env, "answer", JsNumber.create(b, env, 42.0).value)
        var escaped = esc.escape(b, env, obj.value)
        esc.close(b, env)
        return escaped
    except:
        throw_js_error(env, "buildInScope failed")
        return NapiValue()


def test_weak_ref_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var weak = JsRef.create_weak(b, env, arg0)
        var retrieved = weak.get(b, env)
        weak.delete(b, env)
        return retrieved
    except:
        throw_js_error(env, "testWeakRef failed")
        return NapiValue()


def register_refs(mut m: ModuleBuilder) raises:
    var test_ref_ref = test_ref_fn
    var test_ref_object_ref = test_ref_object_fn
    var test_ref_string_ref = test_ref_string_fn
    var build_in_scope_ref = build_in_scope_fn
    var test_weak_ref_ref = test_weak_ref_fn
    m.method("testRef", fn_ptr(test_ref_ref))
    m.method("testRefObject", fn_ptr(test_ref_object_ref))
    m.method("testRefString", fn_ptr(test_ref_string_ref))
    m.method("buildInScope", fn_ptr(build_in_scope_ref))
    m.method("testWeakRef", fn_ptr(test_weak_ref_ref))
