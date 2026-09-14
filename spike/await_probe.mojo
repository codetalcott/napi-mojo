## await_probe.mojo — can Mojo, INSIDE a napi callback, see a JS Promise settle?
##
## PURPOSE: throwaway evidence, same role as runtime_probe.mojo. It backs the
## host-mode rule "do not add a blocking await helper" (CLAUDE.md, host mode,
## constraint 1; docs/plan-promise-bridge.md) with a measurement instead of an
## argument. Three attempts at a blocking wait, each against promises settled
## by a microtask, by libuv I/O (fs.promises) and by a timer:
##
##   holdAndPoll — sleep 25 ms x 20 and poll a flag the promise's .then() sets
##   scopeDrain  — open/close a napi callback scope (the microtask-drain point)
##   uvRun       — re-enter libuv with uv_run(loop, NOWAIT|ONCE)
##
## RECORDED RESULT (2026-09-13, Mojo 1.0.0, Node 24.15.0, darwin-arm64): no
## attempt ever observed a settlement; every promise settled ~20 ms after the
## callback returned. uv_run(ONCE) DID run a plain setTimeout callback on the
## nested stack, and ran a timer that called resolve() — and the resolved
## promise's .then() still did not run until the outer callback returned. So
## re-entering the loop is both unsafe (JS on a nested stack) and useless.
##
## RUN:
##   pixi run mojo build --emit shared-lib -I src spike/await_probe.mojo -o build/await_probe.so
##   mv build/await_probe.so build/await_probe.node
##   for c in state pollMicrotask pollFs pollTimer scopeTop scopeImmediate \
##            uvNowaitMicro uvNowaitFs uvOnceFs uvOnceTimer uvOnceTimerCb uvOnceTimerResolve; do
##     node spike/await_probe.cjs $c; done
##
## The language half needs no Node at all: Mojo 1.0.0 compiles and runs
##   from std.runtime.asyncrt import create_task
##   async def leaf(x: Int) -> Int:
##       return x * 2
##   async def middle(x: Int) -> Int:
##       var a = await leaf(x)
##       var b = await leaf(a)
##       return a + b
##   def main():
##       print(create_task(middle(5)).wait())   # prints 30
## `await` exists; it suspends Mojo coroutines, and nothing public makes a JS
## promise awaitable.

from std.memory.alloc import unsafe_alloc
from std.ffi import OwnedDLHandle
from std.time import sleep
from napi.types import NapiEnv, NapiValue
from napi.bindings import NapiBindings, Bindings, init_bindings
from napi.error import throw_js_error, throw_js_error_dynamic
from napi.raw import _sym
from napi.framework.register import ModuleBuilder, fn_ptr
from napi.framework.args import CbArgs
from napi.framework.js_function import JsFunction
from napi.framework.js_value import js_get_global
from napi.framework.js_boolean import JsBoolean
from napi.framework.js_number import JsNumber
from napi.framework.handle_scope import HandleScope
from napi.framework.callback_scope import CallbackScope
from napi.framework.js_async_context import JsAsyncContext
from napi.framework.js_string import JsString
from napi.framework.js_version import get_uv_event_loop


def _settled(b: Bindings, env: NapiEnv) raises -> Bool:
    var hs = HandleScope.open(b, env)
    var v = js_get_global(b, env).get_named_property(b, env, "__settled")
    var r = JsBoolean.from_napi_value(b, env, v)
    hs.close(b, env)
    return r


## holdAndPoll(fn, polls, sleepMs) -> number of polls that saw the settle
def hold_and_poll_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_three(b, env, info)
        _ = JsFunction(args[0]).call0(b, env)  # returns the Promise; we hold the thread
        var polls = Int(JsNumber.from_napi_value(b, env, args[1]))
        var ms = JsNumber.from_napi_value(b, env, args[2])
        var seen = 0
        for _ in range(polls):
            sleep(ms / 1000.0)
            if _settled(b, env):
                seen += 1
        return JsNumber.create_int(b, env, seen).value
    except e:
        throw_js_error_dynamic(env, String(e))
        return NapiValue(unsafe_from_address=Int(0))


## scopeDrain(fn, noop) -> did closing a callback scope drain microtasks?
def scope_drain_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        _ = JsFunction(args[0]).call0(b, env)
        var g = js_get_global(b, env)
        var name = JsString.create_literal(b, env, "awaitProbe")
        var ctx = JsAsyncContext.create(b, env, g.value, name.value)
        var scope = CallbackScope.open(b, env, g.value, ctx.value)
        _ = ctx.make_callback0(b, env, g.value, args[1])
        scope.close(b, env)
        ctx.destroy(b, env)
        return JsBoolean.create(b, env, _settled(b, env)).value
    except e:
        throw_js_error_dynamic(env, String(e))
        return NapiValue(unsafe_from_address=Int(0))


## uvRun(fn, mode, preSleepMs) -> did re-entering uv_run let the promise settle?
def uv_run_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_three(b, env, info)
        _ = JsFunction(args[0]).call0(b, env)
        var mode = Int32(Int(JsNumber.from_napi_value(b, env, args[1])))
        sleep(JsNumber.from_napi_value(b, env, args[2]) / 1000.0)
        var loop = get_uv_event_loop(b, env)
        var h = OwnedDLHandle()
        var uv_run = _sym[
            def(OpaquePointer[MutAnyOrigin], Int32) thin abi("C") -> Int32
        ](h, "uv_run")
        _ = uv_run(loop, mode)
        return JsBoolean.create(b, env, _settled(b, env)).value
    except e:
        throw_js_error_dynamic(env, String(e))
        return NapiValue(unsafe_from_address=Int(0))


@export("napi_register_module_v1")
def register_module(env: NapiEnv, exports: NapiValue) abi("C") -> NapiValue:
    var bindings_ptr = unsafe_alloc[NapiBindings](1)
    try:
        var bindings = NapiBindings()
        init_bindings(bindings)
        bindings_ptr.unsafe_write(bindings^)
    except:
        bindings_ptr.unsafe_free()
        throw_js_error(env, "await_probe: bindings init failed")
        return exports
    var cb_data = bindings_ptr.unsafe_bitcast[NoneType]().as_unsafe_any_origin()
    try:
        var m = ModuleBuilder(env, exports, cb_data)
        var a = hold_and_poll_fn
        var c = scope_drain_fn
        var d = uv_run_fn
        m.method("holdAndPoll", fn_ptr(a))
        m.method("scopeDrain", fn_ptr(c))
        m.method("uvRun", fn_ptr(d))
        m.flush()
        _ = a
        _ = c
        _ = d
    except:
        pass
    return exports
