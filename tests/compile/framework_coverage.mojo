## tests/compile/framework_coverage.mojo — per-method elaboration coverage
##
## COMPILED BY CI, NEVER RUN. Compiling it IS the test.
##
## WHY THIS EXISTS
##
## Mojo elaborates `def` bodies in imported package modules LAZILY, per method.
## A body full of hard type errors compiles, packages and publishes as long as
## nothing in the compiled graph calls that specific method. napi-mojo 0.5.1
## shipped four broken framework modules exactly that way, with build.sh green
## and 609 tests passing. JsBigInt.to_int64 was called by src/addon/, so it
## elaborated and was fine; JsBigInt.to_uint64 was called nowhere, so its
## identical bug shipped. Same story in js_arraybuffer: create_and_fill was
## exercised, create was not, and create was broken — in both overloads.
##
## The pre-existing mitigation (the "Build examples" CI step) raised coverage
## from module level to some-methods level, because examples/ reaches framework
## code src/lib.mojo does not. But the unit of elaboration is the METHOD, and
## the addon plus examples together only call the subset they happen to expose.
## This file closes that gap by calling everything.
##
## HOW IT WORKS
##
## The lazy/eager split is by MODULE ROLE, not by decorator: bodies in the main
## module named on the `mojo build` command line are type-checked eagerly, and
## bodies reached through -I as an imported package are elaborated only when
## called. So this file is a main module that calls into src/napi/framework/,
## rooted at an @export'ed function that is never invoked — taking the address
## of a called function is enough to force its body through the type checker.
## spike/elaboration_probe.mojo demonstrates both halves of that claim, and is
## the thing to re-run if a nightly ever makes this file's guarantee suspect.
##
## Nothing here executes, so the values are all fabricated: parameters of the
## anchor, or null handles. Do not "improve" this file by making the calls
## realistic — a live napi_env is not available at build time and is not needed.
##
## MAINTENANCE RULES
##
##   1. One cover_<module>() per file in src/napi/framework/, in source order.
##   2. One call per public `def`, INCLUDING each env-only/Bindings overload
##      separately. Both JsArrayBuffer.create overloads were independently
##      broken; checking only one would have left the other latent. A target
##      that touched one function per module would have caught neither, because
##      js_arraybuffer and js_bigint were both already "covered" at that level.
##   3. Add new framework methods here in the same commit that adds them.
##      scripts/check-compile-coverage.mjs fails CI on a missing NAME, but it
##      cannot see a missing overload of a name already present. That part is
##      on the author and the reviewer.
##   4. Underscore-private helpers are deliberately absent: they elaborate
##      transitively through the public methods that call them.
##
## VERIFYING THE GUARD STILL BITES
##
##   git revert --no-commit 5161dfc
##   pixi run mojo build --emit shared-lib -I src \
##     tests/compile/framework_coverage.mojo -o /tmp/gate.so   # MUST FAIL
##   git reset --hard HEAD
##
## A coverage guard that does not fail on the known bug is worthless, so re-run
## that after any change to how this file roots elaboration.
##
## BUILD
##   pixi run mojo build --emit shared-lib -I src \
##     tests/compile/framework_coverage.mojo -o /tmp/framework_coverage.so

from std.memory import alloc

from napi.types import (
    NapiEnv,
    NapiValue,
    NapiDeferred,
    NapiAsyncWork,
    NapiAsyncContext,
    NapiRef,
    NapiThreadsafeFunction,
    NapiValueType,
    NAPI_TYPE_OBJECT,
)
from napi.bindings import NapiBindings, Bindings

from napi.framework.args import CbArgs
from napi.framework.async_work import AsyncWork
from napi.framework.callback_scope import CallbackScope
from napi.framework.convert import (
    JsF64,
    JsI32,
    JsBool,
    JsStr,
    JsRaw,
    to_js_array,
    from_js_array,
    to_js_array_f64,
    from_js_array_f64,
    to_js_array_str,
    from_js_array_str,
)
from napi.framework.escapable_handle_scope import EscapableHandleScope
from napi.framework.handle_scope import HandleScope
from napi.framework.instance_data import set_instance_data, get_instance_data
from napi.framework.js_array import JsArray
from napi.framework.js_arraybuffer import JsArrayBuffer
from napi.framework.js_async_context import JsAsyncContext
from napi.framework.js_bigint import JsBigInt
from napi.framework.js_boolean import JsBoolean
from napi.framework.js_buffer import JsBuffer
from napi.framework.js_class import (
    define_class,
    register_instance_method,
    register_getter,
    register_getter_setter,
    register_static_method,
    register_static_getter,
    register_static_getter_setter,
    set_class_prototype,
    unwrap_native,
    unwrap_native_from_this,
)
from napi.framework.js_coerce import (
    js_coerce_to_bool,
    js_coerce_to_number,
    js_coerce_to_string,
    js_coerce_to_object,
)
from napi.framework.js_dataview import JsDataView
from napi.framework.js_date import JsDate
from napi.framework.js_exception import (
    js_throw,
    js_is_exception_pending,
    js_get_and_clear_last_exception,
    js_get_error_message,
    js_get_error_stack,
)
from napi.framework.js_external import JsExternal
from napi.framework.js_function import JsFunction
from napi.framework.js_int32 import JsInt32
from napi.framework.js_int64 import JsInt64
from napi.framework.js_mojo_array import MojoFloat64Array
from napi.framework.js_null import JsNull
from napi.framework.js_number import JsNumber
from napi.framework.js_object import JsObject
from napi.framework.js_promise import JsPromise
from napi.framework.js_ref import JsRef
from napi.framework.js_string import JsString, js_to_string
from napi.framework.js_symbol import JsSymbol
from napi.framework.js_typedarray import JsTypedArray
from napi.framework.js_uint32 import JsUInt32
from napi.framework.js_undefined import JsUndefined
from napi.framework.js_value import (
    js_typeof,
    js_type_name,
    js_is_array,
    js_strict_equals,
    js_get_global,
    js_is_error,
    js_adjust_external_memory,
    js_run_script,
)
from napi.framework.js_version import (
    get_napi_version,
    get_node_version_ptr,
    add_async_cleanup_hook,
    remove_async_cleanup_hook,
    get_uv_event_loop,
)
from napi.framework.register import (
    fn_ptr,
    ModuleBuilder,
    ClassBuilder,
    ClassRegistry,
)
from napi.framework.runtime import init_async_runtime, parallelize_safe
from napi.framework.threadsafe_function import ThreadsafeFunction


# --- Fabrication helpers ------------------------------------------------------
#
# Everything below is a stand-in. None of it is dereferenced, because none of
# these functions run.


## Payload type for the parametric methods. Explicit __moveinit__ is omitted
## deliberately: it fails to compile in a main-module file ("'None' has no
## attributes" on self) while the identical spelling works inside a package.
## Movable is auto-derived, which is all create_typed/set_instance_data need.
struct CoverPayload(Movable):
    var x: Int

    def __init__(out self, x: Int):
        self.x = x


## A napi_callback whose address stands in for every method/getter/setter
## function-pointer parameter.
def _cover_cb(env: NapiEnv, info: NapiValue) -> NapiValue:
    return info


def _null() -> OpaquePointer[MutAnyOrigin]:
    return OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))


def _null_imm() -> OpaquePointer[ImmutAnyOrigin]:
    return OpaquePointer[ImmutAnyOrigin](unsafe_from_address=Int(0))


# --- args.mojo ----------------------------------------------------------------


def cover_args(b: Bindings, env: NapiEnv, v: NapiValue) raises:
    _ = CbArgs.get_one(env, v)
    _ = CbArgs.get_one(b, env, v)
    _ = CbArgs.get_two(env, v)
    _ = CbArgs.get_two(b, env, v)
    _ = CbArgs.get_three(b, env, v)
    _ = CbArgs.get_four(b, env, v)
    _ = CbArgs.get_this(env, v)
    _ = CbArgs.get_this(b, env, v)
    _ = CbArgs.get_this_and_one(env, v)
    _ = CbArgs.get_this_and_one(b, env, v)
    _ = CbArgs.argc(env, v)
    _ = CbArgs.argc(b, env, v)

    var argv = alloc[NapiValue](2).as_unsafe_any_origin()
    CbArgs.get_argv(env, v, UInt(2), argv)
    CbArgs.get_argv(b, env, v, UInt(2), argv)
    argv.free()

    _ = CbArgs.get_data(env, v)
    _ = CbArgs.get_data(b, env, v)
    _ = CbArgs.get_bindings(env, v)
    _ = CbArgs.get_bindings_and_one(env, v)
    _ = CbArgs.get_bindings_and_two(env, v)
    _ = CbArgs.get_bindings_and_three(env, v)
    _ = CbArgs.get_bindings_and_this(env, v)
    _ = CbArgs.get_bindings_this_and_one(env, v)


# --- async_work.mojo ----------------------------------------------------------


def cover_async_work(b: Bindings, env: NapiEnv, v: NapiValue) raises:
    var deferred = NapiDeferred(unsafe_from_address=Int(0))
    var work = NapiAsyncWork(unsafe_from_address=Int(0))
    _ = AsyncWork.queue(env, "cover", _null(), _null(), _null())
    _ = AsyncWork.queue(b, env, "cover", _null(), _null(), _null())
    AsyncWork.resolve(env, deferred, work, v)
    AsyncWork.resolve(b, env, deferred, work, v)
    AsyncWork.reject_with_error(env, deferred, work, "cover")
    AsyncWork.reject_with_error(b, env, deferred, work, "cover")
    AsyncWork.reject_with_error_dynamic(env, deferred, work, String("cover"))
    AsyncWork.reject_with_error_dynamic(b, env, deferred, work, String("cover"))


# --- callback_scope.mojo ------------------------------------------------------


def cover_callback_scope(b: Bindings, env: NapiEnv, v: NapiValue) raises:
    var ctx = NapiAsyncContext(unsafe_from_address=Int(0))
    var scope = CallbackScope.open(b, env, v, ctx)
    scope.close(b, env)


# --- convert.mojo -------------------------------------------------------------


def cover_convert(b: Bindings, env: NapiEnv, v: NapiValue) raises:
    _ = JsF64(1.0).to_js(env)
    _ = JsF64(1.0).to_js(b, env)
    _ = JsF64.from_js(env, v)
    _ = JsF64.from_js(b, env, v)

    _ = JsI32(1).to_js(env)
    _ = JsI32(1).to_js(b, env)
    _ = JsI32.from_js(env, v)
    _ = JsI32.from_js(b, env, v)

    _ = JsBool(True).to_js(env)
    _ = JsBool(True).to_js(b, env)
    _ = JsBool.from_js(env, v)
    _ = JsBool.from_js(b, env, v)

    _ = JsStr(String("cover")).to_js(env)
    _ = JsStr(String("cover")).to_js(b, env)
    _ = JsStr.from_js(env, v)
    _ = JsStr.from_js(b, env, v)

    _ = JsRaw(v).to_js(env)
    _ = JsRaw(v).to_js(b, env)
    _ = JsRaw.from_js(env, v)
    _ = JsRaw.from_js(b, env, v)

    var floats = List[Float64]()
    _ = to_js_array_f64(b, env, floats)
    _ = from_js_array_f64(b, env, v)
    var strs = List[String]()
    _ = to_js_array_str(b, env, strs)
    _ = from_js_array_str(b, env, v)

    # Parametric forms need a concrete instantiation to elaborate at all.
    var wrapped = List[JsF64]()
    _ = to_js_array(b, env, wrapped)
    _ = from_js_array[JsF64](b, env, v)


# --- escapable_handle_scope.mojo ----------------------------------------------


def cover_escapable_handle_scope(
    b: Bindings, env: NapiEnv, v: NapiValue
) raises:
    var s1 = EscapableHandleScope.open(env)
    _ = s1.escape(env, v)
    _ = s1.escape(b, env, v)
    s1.close(env)
    var s2 = EscapableHandleScope.open(b, env)
    s2.close(b, env)


# --- handle_scope.mojo --------------------------------------------------------


def cover_handle_scope(b: Bindings, env: NapiEnv) raises:
    var s1 = HandleScope.open(env)
    s1.close(env)
    var s2 = HandleScope.open(b, env)
    s2.close(b, env)


# --- instance_data.mojo -------------------------------------------------------


def cover_instance_data(b: Bindings, env: NapiEnv) raises:
    set_instance_data(b, env, CoverPayload(0))
    _ = get_instance_data[CoverPayload](b, env)


# --- js_array.mojo ------------------------------------------------------------


def cover_js_array(b: Bindings, env: NapiEnv, v: NapiValue) raises:
    var a = JsArray.create_with_length(env, UInt(1))
    a.set(env, UInt32(0), v)
    _ = a.get(env, UInt32(0))
    _ = a.length(env)
    _ = a.has(env, UInt32(0))
    _ = a.delete_element(env, UInt32(0))

    var a2 = JsArray.create_with_length(b, env, UInt(1))
    a2.set(b, env, UInt32(0), v)
    _ = a2.get(b, env, UInt32(0))
    _ = a2.length(b, env)
    _ = a2.has(b, env, UInt32(0))
    _ = a2.delete_element(b, env, UInt32(0))


# --- js_arraybuffer.mojo ------------------------------------------------------


def cover_js_arraybuffer(b: Bindings, env: NapiEnv, v: NapiValue) raises:
    _ = JsArrayBuffer.create(env, UInt(8))
    _ = JsArrayBuffer.create(b, env, UInt(8))
    _ = JsArrayBuffer.create_and_fill(env, UInt(8))
    _ = JsArrayBuffer.create_and_fill(b, env, UInt(8))
    _ = JsArrayBuffer.is_arraybuffer(env, v)
    _ = JsArrayBuffer.is_arraybuffer(b, env, v)
    _ = JsArrayBuffer.is_detached(env, v)
    _ = JsArrayBuffer.is_detached(b, env, v)

    var ab = JsArrayBuffer(v)
    _ = ab.byte_length(env)
    _ = ab.byte_length(b, env)
    _ = ab.data_ptr(env)
    _ = ab.data_ptr(b, env)
    ab.detach(env)
    ab.detach(b, env)


# --- js_async_context.mojo ----------------------------------------------------


def cover_js_async_context(b: Bindings, env: NapiEnv, v: NapiValue) raises:
    var ctx = JsAsyncContext.create(b, env, v, v)
    _ = ctx.make_callback0(b, env, v, v)
    _ = ctx.make_callback1(b, env, v, v, v)
    _ = ctx.make_callback2(b, env, v, v, v, v)
    ctx.destroy(b, env)


# --- js_bigint.mojo -----------------------------------------------------------


def cover_js_bigint(b: Bindings, env: NapiEnv, v: NapiValue) raises:
    _ = JsBigInt.from_int64(env, Int64(0))
    _ = JsBigInt.from_int64(b, env, Int64(0))
    _ = JsBigInt.from_uint64(env, UInt64(0))
    _ = JsBigInt.from_uint64(b, env, UInt64(0))
    _ = JsBigInt.to_int64(env, v)
    _ = JsBigInt.to_int64(b, env, v)
    _ = JsBigInt.to_uint64(env, v)
    _ = JsBigInt.to_uint64(b, env, v)
    _ = JsBigInt.from_words(env, Int32(0), _null(), UInt(0))
    _ = JsBigInt.from_words(b, env, Int32(0), _null(), UInt(0))
    _ = JsBigInt.word_count(env, v)
    _ = JsBigInt.word_count(b, env, v)
    JsBigInt.to_words(env, v, _null(), _null(), _null())
    JsBigInt.to_words(b, env, v, _null(), _null(), _null())


# --- js_boolean.mojo ----------------------------------------------------------


def cover_js_boolean(b: Bindings, env: NapiEnv, v: NapiValue) raises:
    _ = JsBoolean.create(env, True)
    _ = JsBoolean.create(b, env, True)
    _ = JsBoolean.from_napi_value(env, v)
    _ = JsBoolean.from_napi_value(b, env, v)


# --- js_buffer.mojo -----------------------------------------------------------


def cover_js_buffer(b: Bindings, env: NapiEnv, v: NapiValue) raises:
    _ = JsBuffer.create(env, UInt(8))
    _ = JsBuffer.create(b, env, UInt(8))
    _ = JsBuffer.create_and_fill(env, UInt(8))
    _ = JsBuffer.create_and_fill(b, env, UInt(8))
    _ = JsBuffer.is_buffer(env, v)
    _ = JsBuffer.is_buffer(b, env, v)
    _ = JsBuffer.create_copy(b, env, JsBuffer(v))
    _ = JsBuffer.from_arraybuffer(b, env, JsArrayBuffer(v), UInt(0), UInt(8))

    var buf = JsBuffer(v)
    _ = buf.data_ptr(env)
    _ = buf.data_ptr(b, env)
    _ = buf.length(env)
    _ = buf.length(b, env)


# --- js_class.mojo ------------------------------------------------------------


def cover_js_class(b: Bindings, env: NapiEnv, v: NapiValue) raises:
    var cb_ref = _cover_cb
    var p = fn_ptr(cb_ref)

    _ = define_class(env, "Cover", p)
    _ = define_class(env, "Cover", p, _null())
    _ = define_class(b, env, "Cover", p)
    _ = define_class(b, env, "Cover", p, _null())

    register_instance_method(env, v, "m", p)
    register_instance_method(b, env, v, "m", p)
    register_getter(env, v, "g", p)
    register_getter(b, env, v, "g", p)
    register_getter_setter(env, v, "gs", p, p)
    register_getter_setter(b, env, v, "gs", p, p)
    register_static_method(env, v, "sm", p)
    register_static_method(b, env, v, "sm", p)
    register_static_getter(env, v, "sg", p)
    register_static_getter(b, env, v, "sg", p)
    register_static_getter_setter(env, v, "sgs", p, p)
    register_static_getter_setter(b, env, v, "sgs", p, p)
    set_class_prototype(env, v, v)
    set_class_prototype(b, env, v, v)

    _ = unwrap_native[CoverPayload](env, v)
    _ = unwrap_native[CoverPayload](b, env, v)
    _ = unwrap_native_from_this[CoverPayload](b, env, v)

    _ = cb_ref


# --- js_coerce.mojo -----------------------------------------------------------


def cover_js_coerce(b: Bindings, env: NapiEnv, v: NapiValue) raises:
    _ = js_coerce_to_bool(env, v)
    _ = js_coerce_to_bool(b, env, v)
    _ = js_coerce_to_number(env, v)
    _ = js_coerce_to_number(b, env, v)
    _ = js_coerce_to_string(env, v)
    _ = js_coerce_to_string(b, env, v)
    _ = js_coerce_to_object(env, v)
    _ = js_coerce_to_object(b, env, v)


# --- js_dataview.mojo ---------------------------------------------------------


def cover_js_dataview(b: Bindings, env: NapiEnv, v: NapiValue) raises:
    _ = JsDataView.create(env, UInt(8), v, UInt(0))
    _ = JsDataView.create(b, env, UInt(8), v, UInt(0))
    _ = JsDataView.is_dataview(env, v)
    _ = JsDataView.is_dataview(b, env, v)

    var dv = JsDataView(v)
    _ = dv.byte_length(env)
    _ = dv.byte_length(b, env)
    _ = dv.byte_offset(env)
    _ = dv.byte_offset(b, env)
    _ = dv.data_ptr(env)
    _ = dv.data_ptr(b, env)
    _ = dv.arraybuffer(env)
    _ = dv.arraybuffer(b, env)


# --- js_date.mojo -------------------------------------------------------------


def cover_js_date(b: Bindings, env: NapiEnv, v: NapiValue) raises:
    _ = JsDate.create(env, 0.0)
    _ = JsDate.create(b, env, 0.0)
    _ = JsDate.is_date(env, v)
    _ = JsDate.is_date(b, env, v)

    var d = JsDate(v)
    _ = d.timestamp_ms(env)
    _ = d.timestamp_ms(b, env)


# --- js_exception.mojo --------------------------------------------------------


def cover_js_exception(b: Bindings, env: NapiEnv, v: NapiValue) raises:
    js_throw(env, v)
    js_throw(b, env, v)
    _ = js_is_exception_pending(env)
    _ = js_is_exception_pending(b, env)
    _ = js_get_and_clear_last_exception(env)
    _ = js_get_and_clear_last_exception(b, env)
    _ = js_get_error_message(env, v)
    _ = js_get_error_message(b, env, v)
    _ = js_get_error_stack(env, v)
    _ = js_get_error_stack(b, env, v)


# --- js_external.mojo ---------------------------------------------------------


def cover_js_external(b: Bindings, env: NapiEnv, v: NapiValue) raises:
    _ = JsExternal.create(env, _null(), _null())
    _ = JsExternal.create(b, env, _null(), _null())
    _ = JsExternal.create_no_release(env, _null())
    _ = JsExternal.create_no_release(b, env, _null())
    _ = JsExternal.get_data(env, v)
    _ = JsExternal.get_data(b, env, v)
    _ = JsExternal.create_typed[CoverPayload](b, env, CoverPayload(0))
    _ = JsExternal.get_typed[CoverPayload](b, env, v, String("cover"))


# --- js_function.mojo ---------------------------------------------------------


def cover_js_function(b: Bindings, env: NapiEnv, v: NapiValue) raises:
    var cb_ref = _cover_cb
    var p = fn_ptr(cb_ref)

    _ = JsFunction.create(env, "cover", p)
    _ = JsFunction.create(b, env, "cover", p)
    _ = JsFunction.create_with_data(env, "cover", p, _null())
    _ = JsFunction.create_with_data(b, env, "cover", p, _null())
    _ = JsFunction.create_named(env, String("cover"), 0, p)
    _ = JsFunction.create_named(b, env, String("cover"), 0, p)
    _ = JsFunction.create_named(b, env, String("cover"), 0, p, _null())

    var f = JsFunction(v)
    _ = f.call0(env)
    _ = f.call0(b, env)
    _ = f.call1(env, v)
    _ = f.call1(b, env, v)
    _ = f.call2(env, v, v)
    _ = f.call2(b, env, v, v)

    _ = cb_ref


# --- js_int32.mojo / js_int64.mojo / js_uint32.mojo ---------------------------


def cover_js_int32(b: Bindings, env: NapiEnv, v: NapiValue) raises:
    _ = JsInt32.create(env, Int32(0))
    _ = JsInt32.create(b, env, Int32(0))
    _ = JsInt32.from_napi_value(env, v)
    _ = JsInt32.from_napi_value(b, env, v)


def cover_js_int64(b: Bindings, env: NapiEnv, v: NapiValue) raises:
    _ = JsInt64.create(b, env, Int64(0))
    _ = JsInt64.from_napi_value(b, env, v)


def cover_js_uint32(b: Bindings, env: NapiEnv, v: NapiValue) raises:
    _ = JsUInt32.create(b, env, UInt32(0))
    _ = JsUInt32.from_napi_value(b, env, v)


# --- js_mojo_array.mojo -------------------------------------------------------


def cover_js_mojo_array(b: Bindings, env: NapiEnv) raises:
    var arr = MojoFloat64Array(1)
    _ = arr.to_js(b, env)
    var arr2 = MojoFloat64Array(1)
    _ = arr2.to_js(env)


# --- js_null.mojo / js_undefined.mojo -----------------------------------------


def cover_js_null(b: Bindings, env: NapiEnv) raises:
    _ = JsNull.create(b, env)


def cover_js_undefined(b: Bindings, env: NapiEnv) raises:
    _ = JsUndefined.create(env)
    _ = JsUndefined.create(b, env)


# --- js_number.mojo -----------------------------------------------------------


def cover_js_number(b: Bindings, env: NapiEnv, v: NapiValue) raises:
    _ = JsNumber.create(env, 0.0)
    _ = JsNumber.create(b, env, 0.0)
    _ = JsNumber.from_napi_value(env, v)
    _ = JsNumber.from_napi_value(b, env, v)
    _ = JsNumber.create_int(env, 0)
    _ = JsNumber.create_int(b, env, 0)
    _ = JsNumber.to_int(env, v)
    _ = JsNumber.to_int(b, env, v)


# --- js_object.mojo -----------------------------------------------------------


def cover_js_object(b: Bindings, env: NapiEnv, v: NapiValue) raises:
    _ = JsObject.create(env)
    _ = JsObject.create(b, env)

    var o = JsObject(v)
    o.set_property(env, "k", v)
    o.set_property(b, env, "k", v)
    o.set_named_property(env, String("k"), v)
    o.set_named_property(b, env, String("k"), v)
    o.set(env, v, v)
    o.set(b, env, v, v)
    _ = o.has(env, v)
    _ = o.has(b, env, v)
    _ = o.get(env, v)
    _ = o.get(b, env, v)
    _ = o.get_property(env, "k")
    _ = o.get_property(b, env, "k")
    _ = o.get_named_property(env, String("k"))
    _ = o.get_named_property(b, env, String("k"))
    _ = o.has_property(env, "k")
    _ = o.has_property(b, env, "k")
    _ = o.get_opt(env, "k")
    _ = o.get_opt(b, env, "k")
    _ = o.keys(env)
    _ = o.keys(b, env)
    _ = o.keys_filtered(b, env, Int32(0), Int32(0), Int32(0))
    _ = o.has_own(env, v)
    _ = o.has_own(b, env, v)
    _ = o.delete_prop(env, v)
    _ = o.delete_prop(b, env, v)
    _ = o.instance_of(env, v)
    _ = o.instance_of(b, env, v)
    o.freeze(env)
    o.freeze(b, env)
    o.seal(env)
    o.seal(b, env)
    _ = o.prototype(env)
    _ = o.prototype(b, env)


# --- js_promise.mojo ----------------------------------------------------------


def cover_js_promise(b: Bindings, env: NapiEnv, v: NapiValue) raises:
    var p1 = JsPromise.create(env)
    p1.resolve(env, v)
    p1.reject(env, v)
    var p2 = JsPromise.create(b, env)
    p2.resolve(b, env, v)
    p2.reject(b, env, v)


# --- js_ref.mojo --------------------------------------------------------------


def cover_js_ref(b: Bindings, env: NapiEnv, v: NapiValue) raises:
    _ = JsRef.create(env, v, UInt32(1))
    _ = JsRef.create(b, env, v, UInt32(1))
    _ = JsRef.create_weak(env, v)
    _ = JsRef.create_weak(b, env, v)

    var handle = JsRef(NapiRef(unsafe_from_address=Int(0)))
    _ = handle.inc(env)
    _ = handle.inc(b, env)
    _ = handle.dec(env)
    _ = handle.dec(b, env)
    _ = handle.get(env)
    _ = handle.get(b, env)
    handle.delete(env)
    handle.delete(b, env)


# --- js_string.mojo -----------------------------------------------------------


def cover_js_string(b: Bindings, env: NapiEnv, v: NapiValue) raises:
    _ = JsString.create(env, String("cover"))
    _ = JsString.create(b, env, String("cover"))
    _ = JsString.create_literal(env, "cover")
    _ = JsString.create_literal(b, env, "cover")
    _ = JsString.from_napi_value(env, v)
    _ = JsString.from_napi_value(b, env, v)
    _ = JsString.read_arg_0(env, v)
    _ = JsString.read_arg_0(b, env, v)
    _ = JsString.read_latin1(b, env, v)
    _ = JsString.create_property_key(b, env, String("cover"))
    _ = JsString.create_property_key_literal(b, env, "cover")
    _ = JsString.create_external_latin1(
        b, env, _null_imm(), UInt(0), _null(), _null()
    )
    _ = js_to_string(env, v)
    _ = js_to_string(b, env, v)


# --- js_symbol.mojo -----------------------------------------------------------


def cover_js_symbol(b: Bindings, env: NapiEnv, v: NapiValue) raises:
    _ = JsSymbol.create(env, v)
    _ = JsSymbol.create(b, env, v)
    _ = JsSymbol.create_for(env, "cover")
    _ = JsSymbol.create_for(b, env, "cover")


# --- js_typedarray.mojo -------------------------------------------------------


def cover_js_typedarray(b: Bindings, env: NapiEnv, v: NapiValue) raises:
    _ = JsTypedArray.create_float64(env, v, UInt(0), UInt(1))
    _ = JsTypedArray.create_float64(b, env, v, UInt(0), UInt(1))
    _ = JsTypedArray.create_uint8(env, v, UInt(0), UInt(1))
    _ = JsTypedArray.create_uint8(b, env, v, UInt(0), UInt(1))
    _ = JsTypedArray.create_int32(env, v, UInt(0), UInt(1))
    _ = JsTypedArray.create_int32(b, env, v, UInt(0), UInt(1))
    _ = JsTypedArray.create_int8(env, v, UInt(0), UInt(1))
    _ = JsTypedArray.create_int8(b, env, v, UInt(0), UInt(1))
    _ = JsTypedArray.create_uint8_clamped(env, v, UInt(0), UInt(1))
    _ = JsTypedArray.create_uint8_clamped(b, env, v, UInt(0), UInt(1))
    _ = JsTypedArray.create_int16(env, v, UInt(0), UInt(1))
    _ = JsTypedArray.create_int16(b, env, v, UInt(0), UInt(1))
    _ = JsTypedArray.create_uint16(env, v, UInt(0), UInt(1))
    _ = JsTypedArray.create_uint16(b, env, v, UInt(0), UInt(1))
    _ = JsTypedArray.create_uint32(env, v, UInt(0), UInt(1))
    _ = JsTypedArray.create_uint32(b, env, v, UInt(0), UInt(1))
    _ = JsTypedArray.create_float32(env, v, UInt(0), UInt(1))
    _ = JsTypedArray.create_float32(b, env, v, UInt(0), UInt(1))
    _ = JsTypedArray.create_bigint64(env, v, UInt(0), UInt(1))
    _ = JsTypedArray.create_bigint64(b, env, v, UInt(0), UInt(1))
    _ = JsTypedArray.create_biguint64(env, v, UInt(0), UInt(1))
    _ = JsTypedArray.create_biguint64(b, env, v, UInt(0), UInt(1))
    _ = JsTypedArray.is_typedarray(env, v)
    _ = JsTypedArray.is_typedarray(b, env, v)

    var ta = JsTypedArray(v)
    _ = ta.array_type(env)
    _ = ta.array_type(b, env)
    _ = ta.length(env)
    _ = ta.length(b, env)
    _ = ta.data_ptr(env)
    _ = ta.data_ptr(b, env)
    _ = ta.arraybuffer(env)
    _ = ta.arraybuffer(b, env)
    _ = ta.data_ptr_float64(env)
    _ = ta.data_ptr_float64(b, env)
    _ = ta.data_ptr_float32(env)
    _ = ta.data_ptr_float32(b, env)
    _ = ta.data_ptr_int32(env)
    _ = ta.data_ptr_int32(b, env)
    _ = ta.data_ptr_uint8(env)
    _ = ta.data_ptr_uint8(b, env)


# --- js_value.mojo ------------------------------------------------------------


def cover_js_value(b: Bindings, env: NapiEnv, v: NapiValue) raises:
    _ = js_typeof(env, v)
    _ = js_typeof(b, env, v)
    _ = js_type_name(NAPI_TYPE_OBJECT)
    _ = js_is_array(env, v)
    _ = js_is_array(b, env, v)
    _ = js_strict_equals(env, v, v)
    _ = js_strict_equals(b, env, v, v)
    _ = js_get_global(env)
    _ = js_get_global(b, env)
    _ = js_is_error(env, v)
    _ = js_is_error(b, env, v)
    _ = js_adjust_external_memory(env, Int64(0))
    _ = js_adjust_external_memory(b, env, Int64(0))
    _ = js_run_script(env, v)
    _ = js_run_script(b, env, v)


# --- js_version.mojo ----------------------------------------------------------


def cover_js_version(b: Bindings, env: NapiEnv) raises:
    _ = get_napi_version(env)
    _ = get_napi_version(b, env)
    _ = get_node_version_ptr(env)
    _ = get_node_version_ptr(b, env)
    _ = add_async_cleanup_hook(b, env, _null(), _null())
    remove_async_cleanup_hook(b, _null())
    _ = get_uv_event_loop(b, env)


# --- register.mojo ------------------------------------------------------------


def cover_register(b: Bindings, env: NapiEnv, v: NapiValue) raises:
    var cb_ref = _cover_cb
    var p = fn_ptr(cb_ref)

    var m1 = ModuleBuilder(env, v)
    m1.method("cover", p)
    m1.flush()

    var m2 = ModuleBuilder(env, v, _null())
    var c1 = m2.class_def("Cover", p)
    var c2 = m2.class_def(b, "Cover", p)
    m2.flush()

    c1.instance_method("m", p)
    c1.instance_method(b, "m", p)
    c1.getter("g", p)
    c1.getter(b, "g", p)
    c1.getter_setter("gs", p, p)
    c1.getter_setter(b, "gs", p, p)
    c1.static_method("sm", p)
    c1.static_method(b, "sm", p)
    c1.static_getter("sg", p)
    c1.static_getter(b, "sg", p)
    c1.static_getter_setter("sgs", p, p)
    c1.static_getter_setter(b, "sgs", p, p)
    c1.inherits(c2)
    c1.inherits(b, c2)

    var reg = ClassRegistry()
    reg.register(b, env, "Cover", v)
    _ = reg.new_instance(b, env, "Cover", UInt(0), _null_imm())

    _ = cb_ref


# --- runtime.mojo -------------------------------------------------------------


def cover_runtime() raises:
    init_async_runtime()

    def worker(i: Int) capturing:
        _ = i

    parallelize_safe[worker](0)


# --- threadsafe_function.mojo -------------------------------------------------


def cover_threadsafe_function(b: Bindings, env: NapiEnv, v: NapiValue) raises:
    _ = ThreadsafeFunction.create(
        env, v, v, UInt(0), _null(), _null(), _null()
    )
    _ = ThreadsafeFunction.create(
        b, env, v, v, UInt(0), _null(), _null(), _null()
    )

    var tsfn = ThreadsafeFunction(
        NapiThreadsafeFunction(unsafe_from_address=Int(0))
    )
    tsfn.call_blocking(_null())
    tsfn.call_blocking(b, _null())
    tsfn.call_nonblocking(_null())
    tsfn.call_nonblocking(b, _null())
    tsfn.acquire()
    tsfn.acquire(b)
    tsfn.release()
    tsfn.release(b)
    tsfn.abort()
    tsfn.abort(b)


# --- anchor -------------------------------------------------------------------


## The export name is deliberately NOT napi_register_module_v1: this artifact
## must never be loadable as a Node addon. Every call below runs against null
## handles, so `require()`-ing it would drive N-API on garbage. The name is the
## interlock — do not "fix" it for consistency with examples/.
@export("napi_mojo_framework_coverage")
def coverage_anchor(env: NapiEnv, exports: NapiValue) abi("C") -> NapiValue:
    var b = Bindings(unsafe_from_address=Int(0))
    try:
        cover_args(b, env, exports)
        cover_async_work(b, env, exports)
        cover_callback_scope(b, env, exports)
        cover_convert(b, env, exports)
        cover_escapable_handle_scope(b, env, exports)
        cover_handle_scope(b, env)
        cover_instance_data(b, env)
        cover_js_array(b, env, exports)
        cover_js_arraybuffer(b, env, exports)
        cover_js_async_context(b, env, exports)
        cover_js_bigint(b, env, exports)
        cover_js_boolean(b, env, exports)
        cover_js_buffer(b, env, exports)
        cover_js_class(b, env, exports)
        cover_js_coerce(b, env, exports)
        cover_js_dataview(b, env, exports)
        cover_js_date(b, env, exports)
        cover_js_exception(b, env, exports)
        cover_js_external(b, env, exports)
        cover_js_function(b, env, exports)
        cover_js_int32(b, env, exports)
        cover_js_int64(b, env, exports)
        cover_js_uint32(b, env, exports)
        cover_js_mojo_array(b, env)
        cover_js_null(b, env)
        cover_js_undefined(b, env)
        cover_js_number(b, env, exports)
        cover_js_object(b, env, exports)
        cover_js_promise(b, env, exports)
        cover_js_ref(b, env, exports)
        cover_js_string(b, env, exports)
        cover_js_symbol(b, env, exports)
        cover_js_typedarray(b, env, exports)
        cover_js_value(b, env, exports)
        cover_js_version(b, env)
        cover_register(b, env, exports)
        cover_runtime()
        cover_threadsafe_function(b, env, exports)
    except:
        pass
    return exports
