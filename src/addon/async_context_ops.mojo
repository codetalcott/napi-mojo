## src/addon/async_context_ops.mojo — napi_make_callback + callback scope callbacks

from napi.types import NapiEnv, NapiValue
from napi.bindings import Bindings
from napi.error import throw_js_error, throw_js_type_error
from napi.framework.args import CbArgs
from napi.framework.js_number import JsNumber
from napi.framework.js_undefined import JsUndefined
from napi.framework.js_string import JsString
from napi.framework.js_value import js_get_global
from napi.framework.js_async_context import JsAsyncContext
from napi.framework.callback_scope import CallbackScope
from napi.framework.register import fn_ptr, ModuleBuilder

## makeCallback(fn, arg) — call fn(arg) via napi_make_callback
##
## Creates a temporary async context, calls fn(arg) inside it, destroys the
## context, returns the result. Demonstrates that napi_make_callback correctly
## propagates AsyncLocalStorage context.
fn make_callback_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var func = args[0]
        var arg0 = args[1]
        var global_obj = js_get_global(b, env)
        var name = JsString.create_literal(b, env, "makeCallback")
        var ctx = JsAsyncContext.create(b, env, global_obj.value, name.value)
        var result = ctx.make_callback1(b, env, global_obj.value, func, arg0)
        ctx.destroy(b, env)
        return result
    except:
        throw_js_error(env, "makeCallback failed")
        return NapiValue()

## makeCallback0(fn) — call fn() via napi_make_callback (no arguments)
fn make_callback0_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var global_obj = js_get_global(b, env)
        var name = JsString.create_literal(b, env, "makeCallback0")
        var ctx = JsAsyncContext.create(b, env, global_obj.value, name.value)
        var result = ctx.make_callback0(b, env, global_obj.value, arg0)
        ctx.destroy(b, env)
        return result
    except:
        throw_js_error(env, "makeCallback0 failed")
        return NapiValue()

## makeCallback2(fn, a, b) — call fn(a, b) via napi_make_callback
fn make_callback2_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_three(b, env, info)
        var func = args[0]
        var arg0 = args[1]
        var arg1 = args[2]
        var global_obj = js_get_global(b, env)
        var name = JsString.create_literal(b, env, "makeCallback2")
        var ctx = JsAsyncContext.create(b, env, global_obj.value, name.value)
        var result = ctx.make_callback2(b, env, global_obj.value, func, arg0, arg1)
        ctx.destroy(b, env)
        return result
    except:
        throw_js_error(env, "makeCallback2 failed")
        return NapiValue()

## makeCallbackScope(fn, arg) — open a CallbackScope, call fn(arg), close scope
fn make_callback_scope_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var func = args[0]
        var arg0 = args[1]
        var global_obj = js_get_global(b, env)
        var name = JsString.create_literal(b, env, "makeCallbackScope")
        var ctx = JsAsyncContext.create(b, env, global_obj.value, name.value)
        var scope = CallbackScope.open(b, env, global_obj.value, ctx.value)
        var result = ctx.make_callback1(b, env, global_obj.value, func, arg0)
        scope.close(b, env)
        ctx.destroy(b, env)
        return result
    except:
        throw_js_error(env, "makeCallbackScope failed")
        return NapiValue()

fn register_async_context(mut m: ModuleBuilder) raises:
    var make_callback_ref = make_callback_fn
    var make_callback0_ref = make_callback0_fn
    var make_callback2_ref = make_callback2_fn
    var make_callback_scope_ref = make_callback_scope_fn
    m.method("makeCallback", fn_ptr(make_callback_ref))
    m.method("makeCallback0", fn_ptr(make_callback0_ref))
    m.method("makeCallback2", fn_ptr(make_callback2_ref))
    m.method("makeCallbackScope", fn_ptr(make_callback_scope_ref))
