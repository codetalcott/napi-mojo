## src/lib.mojo — napi-mojo module entry point
##
## Exports: hello, createObject, makeGreeting, greet, add, isPositive,
##          getNull, getUndefined, sumArray, getProperty, callFunction, mapArray,
##          resolveWith, rejectWith, asyncDouble,
##          addInts, bitwiseOr,
##          throwTypeError, throwRangeError, addIntsStrict,
##          createArrayBuffer, arrayBufferLength,
##          sumBuffer, createBuffer,
##          doubleFloat64Array,
##          Counter (class: constructor, increment, reset, value getter/setter,
##                   static: isCounter, fromValue),
##          sumArgs, createCallback, createAdder, getGlobal,
##          testRef, testRefObject, testRefString, buildInScope,
##          addBigInts, createDate, getDateValue, createSymbol, symbolFor,
##          getKeys, hasOwn, deleteProperty, strictEquals, isInstanceOf,
##          freezeObject, sealObject, arrayHasElement, arrayDeleteElement,
##          getPrototype,
##          asyncProgress,
##          createExternal, getExternalData, isExternal,
##          coerceToBool, coerceToNumber, coerceToString, coerceToObject,
##          setPropertyByKey, hasPropertyByKey,
##          throwValue, catchAndReturn,
##          getNapiVersion, getNodeVersion
##
## Module structure:
##   src/napi/types.mojo                             — NapiEnv, NapiValue, NapiStatus, etc.
##   src/napi/raw.mojo                               — sole OwnedDLHandle user; raw_* bindings
##   src/napi/error.mojo                             — check_status(), throw_js_error()
##   src/napi/module.mojo                            — define_property(), register_method()
##   src/napi/framework/js_string.mojo               — JsString
##   src/napi/framework/js_object.mojo               — JsObject
##   src/napi/framework/js_number.mojo               — JsNumber
##   src/napi/framework/js_boolean.mojo              — JsBoolean
##   src/napi/framework/js_null.mojo                 — JsNull
##   src/napi/framework/js_undefined.mojo            — JsUndefined
##   src/napi/framework/js_array.mojo                — JsArray
##   src/napi/framework/js_function.mojo             — JsFunction
##   src/napi/framework/js_promise.mojo              — JsPromise
##   src/napi/framework/js_int32.mojo                — JsInt32
##   src/napi/framework/js_uint32.mojo               — JsUInt32
##   src/napi/framework/js_int64.mojo                — JsInt64
##   src/napi/framework/js_arraybuffer.mojo          — JsArrayBuffer
##   src/napi/framework/js_buffer.mojo               — JsBuffer
##   src/napi/framework/js_typedarray.mojo           — JsTypedArray
##   src/napi/framework/js_class.mojo                — define_class, register_instance_method
##   src/napi/framework/js_ref.mojo                  — JsRef
##   src/napi/framework/escapable_handle_scope.mojo  — EscapableHandleScope
##   src/napi/framework/js_bigint.mojo               — JsBigInt
##   src/napi/framework/js_date.mojo                 — JsDate
##   src/napi/framework/js_symbol.mojo               — JsSymbol
##   src/napi/framework/args.mojo                    — CbArgs
##   src/napi/framework/js_value.mojo                — js_typeof, js_is_array, js_get_global
##   src/napi/framework/handle_scope.mojo            — HandleScope
##   src/napi/framework/js_external.mojo              — JsExternal
##   src/napi/framework/js_coerce.mojo               — js_coerce_to_*
##   src/napi/framework/js_exception.mojo            — js_throw, js_is_exception_pending
##   src/napi/framework/js_version.mojo             — get_napi_version, get_node_version
##   src/napi/framework/threadsafe_function.mojo     — ThreadsafeFunction
##
## This file contains only:
##   1. Imports from the napi/ package
##   2. The napi_callback implementations
##   3. The @export entry point (register_module)

from memory import alloc
from napi.types import NapiEnv, NapiValue, NapiStatus, NapiDeferred, NapiAsyncWork, NapiThreadsafeFunction, NapiTypeTag, NAPI_TYPE_STRING, NAPI_TYPE_NUMBER, NAPI_TYPE_OBJECT, NAPI_TYPE_FUNCTION, NAPI_TYPE_BIGINT, NAPI_TYPE_EXTERNAL, NAPI_OK, NAPI_TSFN_BLOCKING, NAPI_TSFN_RELEASE, NAPI_INT8_ARRAY, NAPI_UINT8_ARRAY, NAPI_UINT8_CLAMPED_ARRAY, NAPI_INT16_ARRAY, NAPI_UINT16_ARRAY, NAPI_INT32_ARRAY, NAPI_UINT32_ARRAY, NAPI_FLOAT32_ARRAY, NAPI_FLOAT64_ARRAY, NAPI_KEY_OWN_ONLY, NAPI_KEY_INCLUDE_PROTOTYPES, NAPI_KEY_ALL_PROPERTIES, NAPI_KEY_ENUMERABLE, NAPI_KEY_CONFIGURABLE, NAPI_KEY_WRITABLE, NAPI_KEY_SKIP_STRINGS, NAPI_KEY_SKIP_SYMBOLS, NAPI_KEY_KEEP_NUMBERS, NAPI_KEY_NUMBERS_TO_STRINGS
from napi.raw import raw_create_error, raw_resolve_deferred, raw_reject_deferred, raw_create_async_work, raw_queue_async_work, raw_delete_async_work, raw_call_threadsafe_function, raw_release_threadsafe_function, raw_new_instance, raw_get_value_bigint_words, raw_add_finalizer, raw_create_external_arraybuffer, raw_set_instance_data, raw_get_instance_data, raw_add_env_cleanup_hook, raw_remove_env_cleanup_hook, raw_cancel_async_work, raw_fatal_exception, raw_type_tag_object, raw_check_object_type_tag
from napi.framework.threadsafe_function import ThreadsafeFunction
from napi.framework.js_string import JsString, js_to_string
from napi.framework.js_object import JsObject
from napi.framework.js_number import JsNumber
from napi.framework.js_boolean import JsBoolean
from napi.framework.js_null import JsNull
from napi.framework.js_undefined import JsUndefined
from napi.framework.js_array import JsArray
from napi.framework.js_function import JsFunction
from napi.framework.js_promise import JsPromise
from napi.framework.args import CbArgs
from napi.framework.js_value import js_typeof, js_type_name, js_is_array, js_get_global, js_strict_equals, js_is_error, js_adjust_external_memory, js_run_script
from napi.framework.handle_scope import HandleScope
from napi.framework.js_int32 import JsInt32
from napi.framework.js_uint32 import JsUInt32
from napi.framework.js_arraybuffer import JsArrayBuffer
from napi.framework.js_buffer import JsBuffer
from napi.framework.js_typedarray import JsTypedArray
from napi.framework.js_class import unwrap_native
from napi.framework.register import fn_ptr, ModuleBuilder, ClassRegistry
from generated.callbacks import register_generated
from napi.framework.js_ref import JsRef
from napi.framework.escapable_handle_scope import EscapableHandleScope
from napi.framework.js_bigint import JsBigInt
from napi.framework.js_date import JsDate
from napi.framework.js_symbol import JsSymbol
from napi.framework.js_external import JsExternal
from napi.framework.js_coerce import js_coerce_to_bool, js_coerce_to_number, js_coerce_to_string, js_coerce_to_object
from napi.framework.js_exception import js_throw, js_is_exception_pending, js_get_and_clear_last_exception, js_get_error_message, js_get_error_stack
from napi.framework.js_dataview import JsDataView
from napi.framework.js_version import get_napi_version, get_node_version_ptr, add_async_cleanup_hook, remove_async_cleanup_hook, get_uv_event_loop
from napi.framework.async_work import AsyncWork
from napi.bindings import NapiBindings, Bindings, init_bindings, get_bindings
from napi.raw import raw_wrap
from napi.error import throw_js_error, throw_js_error_dynamic, throw_js_type_error, throw_js_type_error_dynamic, throw_js_range_error, throw_js_syntax_error, check_status

# ---------------------------------------------------------------------------
# hello() — exposed as addon.hello()
#
# Returns the JavaScript string "Hello from Mojo!".
# Signature matches napi_callback: fn(NapiEnv, NapiValue) -> NapiValue.
# Cannot be `raises` — Node.js calls this directly via C function pointer.
# ---------------------------------------------------------------------------
fn hello_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        return JsString.create_literal(b, env, "Hello from Mojo!").value
    except:
        return NapiValue()

# ---------------------------------------------------------------------------
# createObject() — exposed as addon.createObject()
#
# Returns a new empty JavaScript object {}.
# ---------------------------------------------------------------------------
fn create_object_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        return JsObject.create(b, env).value
    except:
        return NapiValue()

# ---------------------------------------------------------------------------
# makeGreeting() — exposed as addon.makeGreeting()
#
# Returns the JavaScript object {message: "Hello!"}.
# Demonstrates JsObject.set_property (StringLiteral key) with a JsString value.
# ---------------------------------------------------------------------------
fn make_greeting_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var obj = JsObject.create(b, env)
        var msg = JsString.create_literal(b, env, "Hello!")
        obj.set_property(b, env, "message", msg.value)
        return obj.value
    except:
        return NapiValue()

# ---------------------------------------------------------------------------
# greet(name) — exposed as addon.greet(name)
#
# Takes a JavaScript string argument and returns "Hello, <name>!".
# Uses js_typeof to validate the argument type before reading, enabling
# a descriptive error message that names the actual received type.
# ---------------------------------------------------------------------------
fn greet_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var t = js_typeof(b, env, arg0)
        if t != NAPI_TYPE_STRING:
            throw_js_error_dynamic(b, env, "greet: expected string, got " + js_type_name(t))
            return NapiValue()
        var name = JsString.from_napi_value(b, env, arg0)
        return JsString.create(b, env, "Hello, " + name + "!").value
    except:
        throw_js_error(env, "greet requires one string argument")
        return NapiValue()

# ---------------------------------------------------------------------------
# add(a, b) — exposed as addon.add(a, b)
#
# Takes two JavaScript number arguments and returns their sum as a JS number.
# Uses CbArgs.get_two for argument extraction and JsNumber for numeric I/O.
# ---------------------------------------------------------------------------
fn add_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var a = JsNumber.from_napi_value(b, env, args[0])
        var b2 = JsNumber.from_napi_value(b, env, args[1])
        return JsNumber.create(b, env, a + b2).value
    except:
        throw_js_error(env, "add requires two number arguments")
        return NapiValue()

# ---------------------------------------------------------------------------
# isPositive(n) — exposed as addon.isPositive(n)
#
# Takes a JavaScript number argument and returns true if it is > 0, false
# otherwise. Uses CbArgs.get_one for argument extraction.
# ---------------------------------------------------------------------------
fn is_positive_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var n = JsNumber.from_napi_value(b, env, arg0)
        return JsBoolean.create(b, env, n > 0).value
    except:
        throw_js_error(env, "isPositive requires one number argument")
        return NapiValue()

# ---------------------------------------------------------------------------
# getNull() — exposed as addon.getNull()
#
# Returns the JavaScript null singleton. Demonstrates JsNull.create().
# ---------------------------------------------------------------------------
fn get_null_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        return JsNull.create(b, env).value
    except:
        return NapiValue()

# ---------------------------------------------------------------------------
# getUndefined() — exposed as addon.getUndefined()
#
# Returns the JavaScript undefined singleton. Demonstrates JsUndefined.create().
# ---------------------------------------------------------------------------
fn get_undefined_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        return JsUndefined.create(b, env).value
    except:
        return NapiValue()

# ---------------------------------------------------------------------------
# sumArray(arr) — exposed as addon.sumArray(arr)
#
# Takes a JavaScript array of numbers and returns their sum as a JS number.
# Demonstrates JsArray.length(), JsArray.get(), and JsNumber.from_napi_value().
# ---------------------------------------------------------------------------
fn sum_array_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        if not js_is_array(b, env, arg0):
            var t = js_typeof(b, env, arg0)
            throw_js_error_dynamic(b, env, "sumArray: expected array, got " + js_type_name(t))
            return NapiValue()
        var arr = JsArray(arg0)
        var len = arr.length(b, env)
        var total: Float64 = 0.0
        for i in range(Int(len)):
            var elem = arr.get(b, env, UInt32(i))
            total += JsNumber.from_napi_value(b, env, elem)
        return JsNumber.create(b, env, total).value
    except:
        throw_js_error(env, "sumArray requires one array argument")
        return NapiValue()

# ---------------------------------------------------------------------------
# getProperty(obj, key) — exposed as addon.getProperty(obj, key)
#
# Takes a JavaScript object and a string key, returns the property value.
# Returns undefined if the property does not exist.
# ---------------------------------------------------------------------------
fn get_property_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var t0 = js_typeof(b, env, args[0])
        if t0 != NAPI_TYPE_OBJECT:
            throw_js_error_dynamic(b, env, "getProperty: expected object, got " + js_type_name(t0))
            return NapiValue()
        var t1 = js_typeof(b, env, args[1])
        if t1 != NAPI_TYPE_STRING:
            throw_js_error_dynamic(b, env, "getProperty: expected string key, got " + js_type_name(t1))
            return NapiValue()
        var obj = JsObject(args[0])
        return obj.get(b, env, args[1])
    except:
        throw_js_error(env, "getProperty requires (object, string)")
        return NapiValue()

# ---------------------------------------------------------------------------
# callFunction(fn, arg) — exposed as addon.callFunction(fn, arg)
#
# Takes a JavaScript function and one argument, calls the function with
# that argument, and returns the result.
# ---------------------------------------------------------------------------
fn call_function_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var t = js_typeof(b, env, args[0])
        if t != NAPI_TYPE_FUNCTION:
            throw_js_error_dynamic(b, env, "callFunction: expected function, got " + js_type_name(t))
            return NapiValue()
        var func = JsFunction(args[0])
        return func.call1(b, env, args[1])
    except:
        throw_js_error(env, "callFunction requires (function, arg)")
        return NapiValue()

# ---------------------------------------------------------------------------
# mapArray(arr, fn) — exposed as addon.mapArray(arr, fn)
#
# Takes a JavaScript array and a mapping function, returns a new array
# with the function applied to each element.
# ---------------------------------------------------------------------------
fn map_array_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        if not js_is_array(b, env, args[0]):
            var t = js_typeof(b, env, args[0])
            throw_js_error_dynamic(b, env, "mapArray: expected array, got " + js_type_name(t))
            return NapiValue()
        var t1 = js_typeof(b, env, args[1])
        if t1 != NAPI_TYPE_FUNCTION:
            throw_js_error_dynamic(b, env, "mapArray: expected function, got " + js_type_name(t1))
            return NapiValue()
        var arr = JsArray(args[0])
        var func = JsFunction(args[1])
        var len = arr.length(b, env)
        var result = JsArray.create_with_length(b, env, UInt(len))
        for i in range(Int(len)):
            var hs = HandleScope.open(b, env)
            var ok = True
            try:
                var elem = arr.get(b, env, UInt32(i))
                var mapped = func.call1(b, env, elem)
                result.set(b, env, UInt32(i), mapped)
            except:
                ok = False
            hs.close(b, env)
            if not ok:
                raise Error("mapArray: callback failed at index " + String(i))
        return result.value
    except:
        throw_js_error(env, "mapArray requires (array, function)")
        return NapiValue()

# ---------------------------------------------------------------------------
# resolveWith(value) — exposed as addon.resolveWith(value)
#
# Creates a new JavaScript Promise, immediately resolves it with the given
# argument, and returns the promise.
# ---------------------------------------------------------------------------
fn resolve_with_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var p = JsPromise.create(b, env)
        p.resolve(b, env, arg0)
        return p.value
    except:
        throw_js_error(env, "resolveWith requires one argument")
        return NapiValue()

# ---------------------------------------------------------------------------
# rejectWith(msg) — exposed as addon.rejectWith(msg)
#
# Creates a new JavaScript Promise, immediately rejects it with a JS Error
# containing the given message string, and returns the promise.
# ---------------------------------------------------------------------------
fn reject_with_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var t = js_typeof(b, env, arg0)
        if t != NAPI_TYPE_STRING:
            throw_js_error_dynamic(b, env, "rejectWith: expected string, got " + js_type_name(t))
            return NapiValue()
        # Create an Error object from the message string (without throwing)
        var null_code = NapiValue()
        var error_val = NapiValue()
        var error_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=error_val).bitcast[NoneType]()
        check_status(raw_create_error(env, null_code, arg0, error_ptr))
        var p = JsPromise.create(b, env)
        p.reject(b, env, error_val)
        return p.value
    except:
        throw_js_error(env, "rejectWith requires one string argument")
        return NapiValue()

# ---------------------------------------------------------------------------
# AsyncDoubleData — shared state between execute and complete callbacks
#
# Heap-allocated with UnsafePointer.alloc(). Contains only simple types
# (no Mojo String or objects with destructors) because the execute callback
# runs on a worker thread where Mojo's runtime may not be available.
# ---------------------------------------------------------------------------
struct AsyncDoubleData(Movable):
    var deferred: NapiDeferred
    var work: NapiAsyncWork
    var input: Float64
    var result: Float64

    fn __init__(out self, input: Float64):
        self.deferred = NapiDeferred()
        self.work = NapiAsyncWork()
        self.input = input
        self.result = 0.0

    fn __moveinit__(out self, deinit take: Self):
        self.deferred = take.deferred
        self.work = take.work
        self.input = take.input
        self.result = take.result

fn async_double_execute(env: NapiEnv, data: OpaquePointer[MutAnyOrigin]):
    var ptr = data.bitcast[AsyncDoubleData]()
    ptr[].result = ptr[].input * 2.0

fn async_double_complete(env: NapiEnv, status: NapiStatus, data: OpaquePointer[MutAnyOrigin]):
    var ptr = data.bitcast[AsyncDoubleData]()
    try:
        if status == NAPI_OK:
            var result_val = JsNumber.create(env, ptr[].result)
            AsyncWork.resolve(env, ptr[].deferred, ptr[].work, result_val.value)
        else:
            AsyncWork.reject_with_error(env, ptr[].deferred, ptr[].work, "async work failed")
    except:
        pass
    ptr.destroy_pointee()
    ptr.free()

fn async_double_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var n = JsNumber.from_napi_value(b, env, arg0)
        var data_ptr = alloc[AsyncDoubleData](1)
        data_ptr.init_pointee_move(AsyncDoubleData(n))
        var exec_ref = async_double_execute
        var comp_ref = async_double_complete
        var aw = AsyncWork.queue(
            b, env, "asyncDouble", data_ptr.bitcast[NoneType](),
            fn_ptr(exec_ref), fn_ptr(comp_ref),
        )
        data_ptr[].deferred = aw.deferred
        data_ptr[].work = aw.work
        return aw.value
    except:
        throw_js_error(env, "asyncDouble requires one number argument")
        return NapiValue()

# ---------------------------------------------------------------------------
# asyncTriple(n) — exposed as addon.asyncTriple(n)
#
# Demonstrates the AsyncWork framework helper. Same pattern as asyncDouble
# but uses AsyncWork.queue/resolve/cleanup to eliminate boilerplate.
# ---------------------------------------------------------------------------
struct AsyncTripleData(Movable):
    var deferred: NapiDeferred
    var work: NapiAsyncWork
    var input: Float64
    var result: Float64

    fn __init__(out self, input: Float64):
        self.deferred = NapiDeferred()
        self.work = NapiAsyncWork()
        self.input = input
        self.result = 0.0

    fn __moveinit__(out self, deinit take: Self):
        self.deferred = take.deferred
        self.work = take.work
        self.input = take.input
        self.result = take.result

fn async_triple_execute(env: NapiEnv, data: OpaquePointer[MutAnyOrigin]):
    var ptr = data.bitcast[AsyncTripleData]()
    ptr[].result = ptr[].input * 3.0

fn async_triple_complete(env: NapiEnv, status: NapiStatus, data: OpaquePointer[MutAnyOrigin]):
    var ptr = data.bitcast[AsyncTripleData]()
    try:
        if status == NAPI_OK:
            var result_val = JsNumber.create(env, ptr[].result)
            AsyncWork.resolve(env, ptr[].deferred, ptr[].work, result_val.value)
        else:
            AsyncWork.reject_with_error(env, ptr[].deferred, ptr[].work, "asyncTriple failed")
    except:
        pass
    ptr.destroy_pointee()
    ptr.free()

fn async_triple_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var n = JsNumber.from_napi_value(b, env, arg0)
        var data_ptr = alloc[AsyncTripleData](1)
        data_ptr.init_pointee_move(AsyncTripleData(n))
        var exec_ref = async_triple_execute
        var comp_ref = async_triple_complete
        var aw = AsyncWork.queue(
            b, env, "asyncTriple", data_ptr.bitcast[NoneType](),
            fn_ptr(exec_ref), fn_ptr(comp_ref),
        )
        data_ptr[].deferred = aw.deferred
        data_ptr[].work = aw.work
        return aw.value
    except:
        throw_js_error(env, "asyncTriple requires one number argument")
        return NapiValue()

# ---------------------------------------------------------------------------
# addInts(a, b) — exposed as addon.addInts(a, b)
#
# Takes two JavaScript number arguments, reads them as Int32, returns their sum.
# ---------------------------------------------------------------------------
fn add_ints_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var ta = js_typeof(b, env, args[0])
        var tb = js_typeof(b, env, args[1])
        if ta != NAPI_TYPE_NUMBER or tb != NAPI_TYPE_NUMBER:
            throw_js_error(b, env, "addInts requires two number arguments")
            return NapiValue()
        var a = JsInt32.from_napi_value(b, env, args[0])
        var b2 = JsInt32.from_napi_value(b, env, args[1])
        return JsInt32.create(b, env, a + b2).value
    except:
        throw_js_error(env, "addInts requires two number arguments")
        return NapiValue()

# ---------------------------------------------------------------------------
# bitwiseOr(a, b) — exposed as addon.bitwiseOr(a, b)
#
# Takes two JavaScript number arguments, reads them as UInt32, returns a | b.
# ---------------------------------------------------------------------------
fn bitwise_or_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var ta = js_typeof(b, env, args[0])
        var tb = js_typeof(b, env, args[1])
        if ta != NAPI_TYPE_NUMBER or tb != NAPI_TYPE_NUMBER:
            throw_js_error(b, env, "bitwiseOr requires two number arguments")
            return NapiValue()
        var a = JsUInt32.from_napi_value(b, env, args[0])
        var b2 = JsUInt32.from_napi_value(b, env, args[1])
        return JsUInt32.create(b, env, a | b2).value
    except:
        throw_js_error(env, "bitwiseOr requires two number arguments")
        return NapiValue()

# ---------------------------------------------------------------------------
# throwTypeError() — exposed as addon.throwTypeError()
#
# Throws a JavaScript TypeError with a fixed message.
# ---------------------------------------------------------------------------
fn throw_type_error_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        throw_js_type_error(b, env, "wrong type")
    except:
        throw_js_type_error(env, "wrong type")
    return NapiValue()

# ---------------------------------------------------------------------------
# throwRangeError() — exposed as addon.throwRangeError()
#
# Throws a JavaScript RangeError with a fixed message.
# ---------------------------------------------------------------------------
fn throw_range_error_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        throw_js_range_error(b, env, "out of range")
    except:
        throw_js_range_error(env, "out of range")
    return NapiValue()

# ---------------------------------------------------------------------------
# addIntsStrict(a, b) — exposed as addon.addIntsStrict(a, b)
#
# Like addInts but throws TypeError (not Error) on type mismatch.
# ---------------------------------------------------------------------------
fn add_ints_strict_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var ta = js_typeof(b, env, args[0])
        var tb = js_typeof(b, env, args[1])
        if ta != NAPI_TYPE_NUMBER or tb != NAPI_TYPE_NUMBER:
            throw_js_type_error_dynamic(b, env,
                "addIntsStrict: expected two numbers, got " + js_type_name(ta) + " and " + js_type_name(tb))
            return NapiValue()
        var a = JsInt32.from_napi_value(b, env, args[0])
        var b2 = JsInt32.from_napi_value(b, env, args[1])
        return JsInt32.create(b, env, a + b2).value
    except:
        throw_js_type_error(env, "addIntsStrict requires two number arguments")
        return NapiValue()

# ---------------------------------------------------------------------------
# createArrayBuffer(size) — exposed as addon.createArrayBuffer(size)
#
# Creates an ArrayBuffer of the given size, filled with incrementing bytes.
# ---------------------------------------------------------------------------
fn create_arraybuffer_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var ta = js_typeof(b, env, arg0)
        if ta != NAPI_TYPE_NUMBER:
            throw_js_error(b, env, "createArrayBuffer requires a number argument")
            return NapiValue()
        var size = JsNumber.from_napi_value(b, env, arg0)
        return JsArrayBuffer.create_and_fill(b, env, UInt(Int(size))).value
    except:
        throw_js_error(env, "createArrayBuffer requires a number argument")
        return NapiValue()

# ---------------------------------------------------------------------------
# arrayBufferLength(buf) — exposed as addon.arrayBufferLength(buf)
#
# Returns the byte length of an ArrayBuffer.
# ---------------------------------------------------------------------------
fn arraybuffer_length_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        if not JsArrayBuffer.is_arraybuffer(b, env, arg0):
            throw_js_error(b, env, "arrayBufferLength requires an ArrayBuffer argument")
            return NapiValue()
        var ab = JsArrayBuffer(arg0)
        var length = ab.byte_length(b, env)
        return JsNumber.create(b, env, Float64(length)).value
    except:
        throw_js_error(env, "arrayBufferLength requires an ArrayBuffer argument")
        return NapiValue()

# ---------------------------------------------------------------------------
# sumBuffer(buf) — exposed as addon.sumBuffer(buf)
#
# Sums the bytes of a Node.js Buffer and returns the total.
# ---------------------------------------------------------------------------
fn sum_buffer_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        if not JsBuffer.is_buffer(b, env, arg0):
            throw_js_error(b, env, "sumBuffer requires a Buffer argument")
            return NapiValue()
        var buf = JsBuffer(arg0)
        var ptr = buf.data_ptr(b, env)
        var len = buf.length(b, env)
        var total: Float64 = 0.0
        for i in range(Int(len)):
            total += Float64(Int(ptr[i]))
        return JsNumber.create(b, env, total).value
    except:
        throw_js_error(env, "sumBuffer requires a Buffer argument")
        return NapiValue()

# ---------------------------------------------------------------------------
# createBuffer(size) — exposed as addon.createBuffer(size)
#
# Creates a Buffer of the given size filled with incrementing byte values.
# ---------------------------------------------------------------------------
fn create_buffer_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var ta = js_typeof(b, env, arg0)
        if ta != NAPI_TYPE_NUMBER:
            throw_js_error(b, env, "createBuffer requires a number argument")
            return NapiValue()
        var size = JsNumber.from_napi_value(b, env, arg0)
        return JsBuffer.create_and_fill(b, env, UInt(Int(size))).value
    except:
        throw_js_error(env, "createBuffer requires a number argument")
        return NapiValue()

# ---------------------------------------------------------------------------
# doubleFloat64Array(arr) — exposed as addon.doubleFloat64Array(arr)
#
# Doubles each element of a Float64Array in-place and returns it.
# ---------------------------------------------------------------------------
fn double_float64_array_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        if not JsTypedArray.is_typedarray(b, env, arg0):
            throw_js_error(b, env, "doubleFloat64Array requires a TypedArray argument")
            return NapiValue()
        var ta = JsTypedArray(arg0)
        var len = ta.length(b, env)
        var byte_ptr = ta.data_ptr(b, env)
        var float_ptr = byte_ptr.bitcast[Float64]()
        for i in range(Int(len)):
            float_ptr[i] = float_ptr[i] * 2.0
        return arg0
    except:
        throw_js_error(env, "doubleFloat64Array requires a TypedArray argument")
        return NapiValue()

# ---------------------------------------------------------------------------
# createTypedArrayView(typeStr, ab, offset, length) — exposed as addon.createTypedArrayView
#
# Creates a TypedArray view of the given type over an ArrayBuffer.
# typeStr: "int8"|"uint8"|"uint8clamped"|"int16"|"uint16"|"int32"|"uint32"|"float32"|"float64"
# ---------------------------------------------------------------------------
fn create_typed_array_view_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var argc = CbArgs.argc(b, env, info)
        var argv = alloc[NapiValue](Int(argc))
        CbArgs.get_argv(b, env, info, argc, argv)
        if argc < 4:
            throw_js_error(b, env, "createTypedArrayView requires 4 arguments")
            argv.free()
            return NapiValue()
        var type_str = JsString.from_napi_value(b, env, argv[0])
        var ab = argv[1]
        var offset = Int(JsNumber.from_napi_value(b, env, argv[2]))
        var length = Int(JsNumber.from_napi_value(b, env, argv[3]))
        argv.free()
        var ta: JsTypedArray
        if type_str == "int8":
            ta = JsTypedArray.create_int8(b, env, ab, UInt(offset), UInt(length))
        elif type_str == "uint8":
            ta = JsTypedArray.create_uint8(b, env, ab, UInt(offset), UInt(length))
        elif type_str == "uint8clamped":
            ta = JsTypedArray.create_uint8_clamped(b, env, ab, UInt(offset), UInt(length))
        elif type_str == "int16":
            ta = JsTypedArray.create_int16(b, env, ab, UInt(offset), UInt(length))
        elif type_str == "uint16":
            ta = JsTypedArray.create_uint16(b, env, ab, UInt(offset), UInt(length))
        elif type_str == "int32":
            ta = JsTypedArray.create_int32(b, env, ab, UInt(offset), UInt(length))
        elif type_str == "uint32":
            ta = JsTypedArray.create_uint32(b, env, ab, UInt(offset), UInt(length))
        elif type_str == "float32":
            ta = JsTypedArray.create_float32(b, env, ab, UInt(offset), UInt(length))
        elif type_str == "float64":
            ta = JsTypedArray.create_float64(b, env, ab, UInt(offset), UInt(length))
        else:
            throw_js_error_dynamic(b, env, "createTypedArrayView: unknown type '" + type_str + "'")
            return NapiValue()
        return ta.value
    except:
        throw_js_error(env, "createTypedArrayView failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# getTypedArrayType(ta) — exposed as addon.getTypedArrayType
#
# Returns the integer type constant (NAPI_*_ARRAY) for a TypedArray.
# ---------------------------------------------------------------------------
fn get_typed_array_type_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        if not JsTypedArray.is_typedarray(b, env, arg0):
            throw_js_type_error(b, env, "getTypedArrayType: expected TypedArray")
            return NapiValue()
        var ta = JsTypedArray(arg0)
        var t = ta.array_type(b, env)
        return JsNumber.create_int(b, env, Int(t)).value
    except:
        throw_js_error(env, "getTypedArrayType failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# getTypedArrayLength(ta) — exposed as addon.getTypedArrayLength
#
# Returns the element count (not byte length) of a TypedArray.
# ---------------------------------------------------------------------------
fn get_typed_array_length_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        if not JsTypedArray.is_typedarray(b, env, arg0):
            throw_js_type_error(b, env, "getTypedArrayLength: expected TypedArray")
            return NapiValue()
        var ta = JsTypedArray(arg0)
        var len = ta.length(b, env)
        return JsNumber.create_int(b, env, Int(len)).value
    except:
        throw_js_error(env, "getTypedArrayLength failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# CounterData — native backing store for Counter class instances
# ---------------------------------------------------------------------------
struct CounterData(Movable):
    var count: Float64
    var initial: Float64

    fn __init__(out self, initial: Float64):
        self.count = initial
        self.initial = initial

    fn __moveinit__(out self, deinit take: Self):
        self.count = take.count
        self.initial = take.initial

# ---------------------------------------------------------------------------
# counter_finalize — GC invokes this when a Counter instance is collected
#
# Cleans up the heap-allocated CounterData wrapped onto the JS object.
# Signature: fn(NapiEnv, void* data, void* hint)
# ---------------------------------------------------------------------------
fn counter_finalize(env: NapiEnv, data: OpaquePointer[MutAnyOrigin], hint: OpaquePointer[MutAnyOrigin]):
    var ptr = data.bitcast[CounterData]()
    ptr.destroy_pointee()
    ptr.free()

# ---------------------------------------------------------------------------
# counter_constructor_fn — Counter(initial) constructor callback
#
# Called when JS does `new Counter(n)`. Validates argument, heap-allocates
# CounterData, and wraps it onto `this`.
# ---------------------------------------------------------------------------
fn counter_constructor_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var this_val = CbArgs.get_this(b, env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var t = js_typeof(b, env, arg0)
        if t != NAPI_TYPE_NUMBER:
            throw_js_type_error(b, env, "Counter constructor requires a number argument")
            return NapiValue()
        var initial = JsNumber.from_napi_value(b, env, arg0)

        # Heap-allocate native data
        var data_ptr = alloc[CounterData](1)
        data_ptr.init_pointee_move(CounterData(initial))

        # Get finalize function pointer
        var fin_ref = counter_finalize
        var fin_ptr = UnsafePointer(to=fin_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]

        # Wrap native data onto this
        check_status(raw_wrap(b,
            env,
            this_val,
            data_ptr.bitcast[NoneType](),              # native_object
            fin_ptr,                                     # finalize_cb
            OpaquePointer[MutAnyOrigin](),              # finalize_hint = NULL
            OpaquePointer[MutAnyOrigin](),              # result = NULL (no ref needed)
        ))

        return this_val
    except:
        throw_js_error(env, "Counter constructor failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# counter_get_value_fn — Counter.prototype.value getter
# ---------------------------------------------------------------------------
fn counter_get_value_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var ptr = unwrap_native[CounterData](b, env, info)
        return JsNumber.create(b, env, ptr[].count).value
    except:
        throw_js_error(env, "Counter.value getter failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# counter_set_value_fn — Counter.prototype.value setter
# ---------------------------------------------------------------------------
fn counter_set_value_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var t = js_typeof(b, env, arg0)
        if t != NAPI_TYPE_NUMBER:
            throw_js_type_error(b, env, "Counter.value setter requires a number")
            return NapiValue()
        var new_val = JsNumber.from_napi_value(b, env, arg0)
        var ptr = unwrap_native[CounterData](b, env, info)
        ptr[].count = new_val
        return JsUndefined.create(b, env).value
    except:
        throw_js_error(env, "Counter.value setter failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# counter_increment_fn — Counter.prototype.increment()
# ---------------------------------------------------------------------------
fn counter_increment_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var ptr = unwrap_native[CounterData](b, env, info)
        ptr[].count += 1.0
        return JsUndefined.create(b, env).value
    except:
        throw_js_error(env, "Counter.increment failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# counter_reset_fn — Counter.prototype.reset()
# ---------------------------------------------------------------------------
fn counter_reset_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var ptr = unwrap_native[CounterData](b, env, info)
        ptr[].count = ptr[].initial
        return JsUndefined.create(b, env).value
    except:
        throw_js_error(env, "Counter.reset failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# counter_is_counter_fn — Counter.isCounter(val) static method
#
# Returns true if val is an instance of Counter, false otherwise.
# Guards primitives (which cause napi_instanceof to fail) via js_typeof.
# Uses CbArgs.get_this() to get the constructor (this = Counter when called
# as Counter.isCounter(x)).
# ---------------------------------------------------------------------------
fn counter_is_counter_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var this_val = CbArgs.get_this(b, env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        # napi_instanceof requires object LHS — primitives are never instanceof
        var t = js_typeof(b, env, arg0)
        if t != NAPI_TYPE_OBJECT and t != NAPI_TYPE_FUNCTION:
            return JsBoolean.create(b, env, False).value
        var result = JsObject(arg0).instance_of(b, env, this_val)
        return JsBoolean.create(b, env, result).value
    except:
        throw_js_error(env, "Counter.isCounter failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# counter_from_value_fn — Counter.fromValue(n) static method
#
# Factory method that creates a new Counter instance with the given value.
# Uses raw_new_instance to call new Counter(n).
# ---------------------------------------------------------------------------
fn counter_from_value_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var this_val = CbArgs.get_this(b, env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var t = js_typeof(b, env, arg0)
        if t != NAPI_TYPE_NUMBER:
            throw_js_type_error(b, env, "Counter.fromValue requires a number argument")
            return NapiValue()
        var result = NapiValue()
        var argv_ptr: OpaquePointer[ImmutAnyOrigin] = UnsafePointer(to=arg0).bitcast[NoneType]()
        check_status(raw_new_instance(b,
            env,
            this_val,
            1,
            argv_ptr,
            UnsafePointer(to=result).bitcast[NoneType](),
        ))
        return result
    except:
        throw_js_error(env, "Counter.fromValue failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# AnimalData — native backing store for Animal class instances
# ---------------------------------------------------------------------------
struct AnimalData(Movable):
    var name_ptr: OpaquePointer[MutAnyOrigin]  # heap-allocated Byte buffer
    var name_len: UInt

    fn __init__(out self, name_ptr: OpaquePointer[MutAnyOrigin], name_len: UInt):
        self.name_ptr = name_ptr
        self.name_len = name_len

    fn __moveinit__(out self, deinit take: Self):
        self.name_ptr = take.name_ptr
        self.name_len = take.name_len

# ---------------------------------------------------------------------------
# DogData — native backing store for Dog class instances
# Embeds AnimalData-compatible fields at offset 0 so inherited Animal methods
# can read name via AnimalData* cast.
# ---------------------------------------------------------------------------
struct DogData(Movable):
    var name_ptr: OpaquePointer[MutAnyOrigin]  # heap-allocated Byte buffer
    var name_len: UInt
    var breed_ptr: OpaquePointer[MutAnyOrigin]  # heap-allocated Byte buffer
    var breed_len: UInt

    fn __init__(out self, name_ptr: OpaquePointer[MutAnyOrigin], name_len: UInt,
                breed_ptr: OpaquePointer[MutAnyOrigin], breed_len: UInt):
        self.name_ptr = name_ptr
        self.name_len = name_len
        self.breed_ptr = breed_ptr
        self.breed_len = breed_len

    fn __moveinit__(out self, deinit take: Self):
        self.name_ptr = take.name_ptr
        self.name_len = take.name_len
        self.breed_ptr = take.breed_ptr
        self.breed_len = take.breed_len

fn animal_finalize(env: NapiEnv, data: OpaquePointer[MutAnyOrigin], hint: OpaquePointer[MutAnyOrigin]):
    var ptr = data.bitcast[AnimalData]()
    ptr[].name_ptr.bitcast[Byte]().free()
    ptr.destroy_pointee()
    ptr.free()

fn dog_finalize(env: NapiEnv, data: OpaquePointer[MutAnyOrigin], hint: OpaquePointer[MutAnyOrigin]):
    var ptr = data.bitcast[DogData]()
    ptr[].name_ptr.bitcast[Byte]().free()
    ptr[].breed_ptr.bitcast[Byte]().free()
    ptr.destroy_pointee()
    ptr.free()

# ---------------------------------------------------------------------------
# animal_constructor_fn — Animal(name) constructor
# ---------------------------------------------------------------------------
fn animal_constructor_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var this_val = CbArgs.get_this(b, env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var t = js_typeof(b, env, arg0)
        if t != NAPI_TYPE_STRING:
            throw_js_type_error(b, env, "Animal constructor requires a string name")
            return NapiValue()
        var name_str = JsString.from_napi_value(b, env, arg0)
        var name_len = UInt(len(name_str))
        var name_buf = alloc[Byte](Int(name_len))
        for i in range(Int(name_len)):
            name_buf[i] = name_str.as_bytes()[i]

        var data_ptr = alloc[AnimalData](1)
        data_ptr.init_pointee_move(AnimalData(name_buf.bitcast[NoneType](), name_len))

        var fin_ref = animal_finalize
        var fin_ptr = UnsafePointer(to=fin_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]

        try:
            check_status(raw_wrap(b,
                env, this_val,
                data_ptr.bitcast[NoneType](),
                fin_ptr,
                OpaquePointer[MutAnyOrigin](),
                OpaquePointer[MutAnyOrigin](),
            ))
        except e:
            name_buf.free()
            data_ptr.destroy_pointee()
            data_ptr.free()
            raise e^
        return this_val
    except:
        throw_js_error(env, "Animal constructor failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# animal_get_name_fn — Animal.prototype.name getter
# ---------------------------------------------------------------------------
fn animal_get_name_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var ptr = unwrap_native[AnimalData](b, env, info)
        var name_bytes = ptr[].name_ptr.bitcast[Byte]()
        var span = Span[Byte](ptr=name_bytes, length=Int(ptr[].name_len))
        var name = String(from_utf8=span)
        return JsString.create(b, env, name).value
    except:
        throw_js_error(env, "Animal.name getter failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# animal_speak_fn — Animal.prototype.speak()
# ---------------------------------------------------------------------------
fn animal_speak_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var ptr = unwrap_native[AnimalData](b, env, info)
        var name_bytes = ptr[].name_ptr.bitcast[Byte]()
        var span = Span[Byte](ptr=name_bytes, length=Int(ptr[].name_len))
        var name = String(from_utf8=span)
        var msg = name + " says hello"
        return JsString.create(b, env, msg).value
    except:
        throw_js_error(env, "Animal.speak failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# animal_is_animal_fn — Animal.isAnimal(val) static method
# ---------------------------------------------------------------------------
fn animal_is_animal_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var this_val = CbArgs.get_this(b, env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var t = js_typeof(b, env, arg0)
        if t != NAPI_TYPE_OBJECT and t != NAPI_TYPE_FUNCTION:
            return JsBoolean.create(b, env, False).value
        var result = JsObject(arg0).instance_of(b, env, this_val)
        return JsBoolean.create(b, env, result).value
    except:
        throw_js_error(env, "Animal.isAnimal failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# dog_constructor_fn — Dog(name, breed) constructor
# ---------------------------------------------------------------------------
fn dog_constructor_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var this_val = CbArgs.get_this(b, env, info)
        var args = CbArgs.get_two(b, env, info)
        var t0 = js_typeof(b, env, args[0])
        var t1 = js_typeof(b, env, args[1])
        if t0 != NAPI_TYPE_STRING or t1 != NAPI_TYPE_STRING:
            throw_js_type_error(b, env, "Dog constructor requires (name: string, breed: string)")
            return NapiValue()

        var name_str = JsString.from_napi_value(b, env, args[0])
        var name_len = UInt(len(name_str))
        var name_buf = alloc[Byte](Int(name_len))
        for i in range(Int(name_len)):
            name_buf[i] = name_str.as_bytes()[i]

        try:
            var breed_str = JsString.from_napi_value(b, env, args[1])
            var breed_len = UInt(len(breed_str))
            var breed_buf = alloc[Byte](Int(breed_len))
            for i in range(Int(breed_len)):
                breed_buf[i] = breed_str.as_bytes()[i]

            var data_ptr = alloc[DogData](1)
            data_ptr.init_pointee_move(DogData(
                name_buf.bitcast[NoneType](), name_len,
                breed_buf.bitcast[NoneType](), breed_len,
            ))

            var fin_ref = dog_finalize
            var fin_ptr = UnsafePointer(to=fin_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]

            try:
                check_status(raw_wrap(b,
                    env, this_val,
                    data_ptr.bitcast[NoneType](),
                    fin_ptr,
                    OpaquePointer[MutAnyOrigin](),
                    OpaquePointer[MutAnyOrigin](),
                ))
            except e:
                name_buf.free()
                breed_buf.free()
                data_ptr.destroy_pointee()
                data_ptr.free()
                raise e^
        except e:
            name_buf.free()
            raise e^
        return this_val
    except:
        throw_js_error(env, "Dog constructor failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# dog_get_breed_fn — Dog.prototype.breed getter
# ---------------------------------------------------------------------------
fn dog_get_breed_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var ptr = unwrap_native[DogData](b, env, info)
        var breed_bytes = ptr[].breed_ptr.bitcast[Byte]()
        var span = Span[Byte](ptr=breed_bytes, length=Int(ptr[].breed_len))
        var breed = String(from_utf8=span)
        return JsString.create(b, env, breed).value
    except:
        throw_js_error(env, "Dog.breed getter failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# sumArgs(...) — exposed as addon.sumArgs(...)
#
# Takes a variable number of arguments, reads each as Float64, returns sum.
# Demonstrates CbArgs.argc() and CbArgs.get_argv().
# ---------------------------------------------------------------------------
fn sum_args_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var count = CbArgs.argc(b, env, info)
        if count == 0:
            return JsNumber.create(b, env, 0.0).value
        var argv = alloc[NapiValue](Int(count))
        CbArgs.get_argv(b, env, info, count, argv)
        var total: Float64 = 0.0
        for i in range(Int(count)):
            var t = js_typeof(b, env, argv[i])
            if t != NAPI_TYPE_NUMBER:
                argv.free()
                throw_js_error_dynamic(b, env, "sumArgs: expected number, got " + js_type_name(t))
                return NapiValue()
            total += JsNumber.from_napi_value(b, env, argv[i])
        argv.free()
        return JsNumber.create(b, env, total).value
    except:
        throw_js_error(env, "sumArgs failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# inner_callback_fn — the callback returned by createCallback()
#
# Returns the string "hello from callback".
# ---------------------------------------------------------------------------
fn inner_callback_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        return JsString.create_literal(env, "hello from callback").value
    except:
        return NapiValue()

# ---------------------------------------------------------------------------
# createCallback() — exposed as addon.createCallback()
#
# Creates and returns a new JavaScript function (inner_callback_fn).
# ---------------------------------------------------------------------------
fn create_callback_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var cb_ref = inner_callback_fn
        var cb_ptr = UnsafePointer(to=cb_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
        return JsFunction.create(b, env, "innerCallback", cb_ptr).value
    except:
        throw_js_error(env, "createCallback failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# inner_adder_fn — the closure returned by createAdder(n)
#
# Reads the captured Float64 from the data pointer, adds the first argument.
# ---------------------------------------------------------------------------
fn inner_adder_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var data = CbArgs.get_data(env, info)
        var n_ptr = data.bitcast[Float64]()
        var n = n_ptr[]
        var arg0 = CbArgs.get_one(env, info)
        var x = JsNumber.from_napi_value(env, arg0)
        return JsNumber.create(env, n + x).value
    except:
        throw_js_error(env, "adder callback failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# createAdder(n) — exposed as addon.createAdder(n)
#
# Takes a number n, heap-allocates it, creates a function that adds n to
# its argument. The data pointer captures n for the inner callback.
# ---------------------------------------------------------------------------
fn create_adder_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var n = JsNumber.from_napi_value(b, env, arg0)
        # Heap-allocate the captured value
        var n_ptr = alloc[Float64](1)
        n_ptr.init_pointee_move(n)
        var cb_ref = inner_adder_fn
        var cb_ptr = UnsafePointer(to=cb_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
        return JsFunction.create_with_data(b,
            env, "adder", cb_ptr, n_ptr.bitcast[NoneType]()
        ).value
    except:
        throw_js_error(env, "createAdder requires one number argument")
        return NapiValue()

# ---------------------------------------------------------------------------
# getGlobal() — exposed as addon.getGlobal()
#
# Returns the global object (globalThis).
# ---------------------------------------------------------------------------
fn get_global_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        return js_get_global(b, env).value
    except:
        throw_js_error(env, "getGlobal failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# testRef() — exposed as addon.testRef()
#
# Creates {value: 42}, stores in a reference, retrieves, returns .value.
# napi_create_reference only supports objects/functions/symbols.
# ---------------------------------------------------------------------------
fn test_ref_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
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

# ---------------------------------------------------------------------------
# testRefObject() — exposed as addon.testRefObject()
#
# Creates an object {answer: 42}, stores in reference, round-trips, returns.
# ---------------------------------------------------------------------------
fn test_ref_object_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
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

# ---------------------------------------------------------------------------
# testRefString(s) — exposed as addon.testRefString(s)
#
# Takes a string, wraps in {value: s}, stores in reference, round-trips,
# returns .value. napi_create_reference only supports objects.
# ---------------------------------------------------------------------------
fn test_ref_string_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
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

# ---------------------------------------------------------------------------
# buildInScope() — exposed as addon.buildInScope()
#
# Opens an escapable handle scope, creates {created: true, answer: 42},
# escapes it, closes the scope, returns the escaped value.
# ---------------------------------------------------------------------------
fn build_in_scope_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var esc = EscapableHandleScope.open(b, env)
        var obj = JsObject.create(b, env)
        obj.set_property(b, env, "created", JsBoolean.create(b, env, True).value)
        obj.set_property(b, env, "answer", JsNumber.create(b, env, 42.0).value)
        var escaped = esc.escape(b, env, obj.value)
        esc.close(b, env)
        return escaped
    except:
        throw_js_error(env, "buildInScope failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# addBigInts(a, b) — exposed as addon.addBigInts(a, b)
#
# Takes two BigInt arguments, returns their sum as a BigInt.
# ---------------------------------------------------------------------------
fn add_bigints_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var ta = js_typeof(b, env, args[0])
        var tb = js_typeof(b, env, args[1])
        if ta != NAPI_TYPE_BIGINT or tb != NAPI_TYPE_BIGINT:
            throw_js_error_dynamic(b, env,
                "addBigInts: expected bigint, got " + js_type_name(ta) + " and " + js_type_name(tb))
            return NapiValue()
        var a = JsBigInt.to_int64(b, env, args[0])
        var b2 = JsBigInt.to_int64(b, env, args[1])
        return JsBigInt.from_int64(b, env, a + b2).value
    except:
        throw_js_error(env, "addBigInts requires two bigint arguments")
        return NapiValue()

# ---------------------------------------------------------------------------
# createDate(timestamp_ms) — exposed as addon.createDate(timestamp_ms)
#
# Creates a JavaScript Date object from a millisecond timestamp.
# ---------------------------------------------------------------------------
fn create_date_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var ts = JsNumber.from_napi_value(b, env, arg0)
        return JsDate.create(b, env, ts).value
    except:
        throw_js_error(env, "createDate requires one number argument")
        return NapiValue()

# ---------------------------------------------------------------------------
# getDateValue(date) — exposed as addon.getDateValue(date)
#
# Returns the timestamp (ms since epoch) of a JavaScript Date object.
# ---------------------------------------------------------------------------
fn get_date_value_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var d = JsDate(arg0)
        var ts = d.timestamp_ms(b, env)
        return JsNumber.create(b, env, ts).value
    except:
        throw_js_error(env, "getDateValue requires one Date argument")
        return NapiValue()

# ---------------------------------------------------------------------------
# createSymbol(description) — exposed as addon.createSymbol(description)
#
# Creates a new unique Symbol with the given string description.
# ---------------------------------------------------------------------------
fn create_symbol_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        return JsSymbol.create(b, env, arg0).value
    except:
        throw_js_error(env, "createSymbol requires one string argument")
        return NapiValue()

# ---------------------------------------------------------------------------
# symbolFor(key) — exposed as addon.symbolFor(key)
#
# Returns the global Symbol for the given key (like Symbol.for(key)).
# Uses a StringLiteral-based approach: reads the JS string, then calls
# node_api_symbol_for with a C string.
# ---------------------------------------------------------------------------
fn symbol_for_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var key = JsString.from_napi_value(b, env, arg0)
        # node_api_symbol_for takes a C string + length, not a napi_value.
        # We use the Mojo String's unsafe_ptr for the C string.
        var key_ptr: OpaquePointer[ImmutAnyOrigin] = key.unsafe_ptr().bitcast[NoneType]()
        var key_len = UInt(len(key))
        var result = NapiValue()
        from napi.raw import raw_symbol_for
        check_status(raw_symbol_for(b, env, key_ptr, key_len,
            UnsafePointer(to=result).bitcast[NoneType]()))
        _ = key^  # prevent ASAP destruction before raw_symbol_for reads key_ptr
        return result
    except:
        throw_js_error(env, "symbolFor requires one string argument")
        return NapiValue()

# ---------------------------------------------------------------------------
# getKeys(obj) — exposed as addon.getKeys(obj)
#
# Returns an array of the object's own enumerable property names.
# ---------------------------------------------------------------------------
fn get_keys_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var t0 = js_typeof(b, env, arg0)
        if t0 != NAPI_TYPE_OBJECT:
            throw_js_error_dynamic(b, env, "getKeys: expected object, got " + js_type_name(t0))
            return NapiValue()
        var obj = JsObject(arg0)
        return obj.keys(b, env)
    except:
        throw_js_error(env, "getKeys requires one object argument")
        return NapiValue()

# ---------------------------------------------------------------------------
# hasOwn(obj, key) — exposed as addon.hasOwn(obj, key)
#
# Returns true if the object has the key as its own (non-inherited) property.
# ---------------------------------------------------------------------------
fn has_own_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var t0 = js_typeof(b, env, args[0])
        if t0 != NAPI_TYPE_OBJECT:
            throw_js_error_dynamic(b, env, "hasOwn: expected object, got " + js_type_name(t0))
            return NapiValue()
        var obj = JsObject(args[0])
        var result = obj.has_own(b, env, args[1])
        return JsBoolean.create(b, env, result).value
    except:
        throw_js_error(env, "hasOwn requires (object, key)")
        return NapiValue()

# ---------------------------------------------------------------------------
# deleteProperty(obj, key) — exposed as addon.deleteProperty(obj, key)
#
# Deletes a property from the object and returns the mutated object.
# ---------------------------------------------------------------------------
fn delete_property_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var t0 = js_typeof(b, env, args[0])
        if t0 != NAPI_TYPE_OBJECT:
            throw_js_error_dynamic(b, env, "deleteProperty: expected object, got " + js_type_name(t0))
            return NapiValue()
        var obj = JsObject(args[0])
        _ = obj.delete_prop(b, env, args[1])
        return obj.value
    except:
        throw_js_error(env, "deleteProperty requires (object, key)")
        return NapiValue()

# ---------------------------------------------------------------------------
# arrayHasElement(arr, index) — exposed as addon.arrayHasElement(arr, index)
#
# Returns true if the array has an element at the given index.
# ---------------------------------------------------------------------------
fn array_has_element_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        if not js_is_array(b, env, args[0]):
            throw_js_error(b, env, "arrayHasElement: first argument must be an array")
            return NapiValue()
        var arr = JsArray(args[0])
        var index = JsUInt32.from_napi_value(b, env, args[1])
        var result = arr.has(b, env, index)
        return JsBoolean.create(b, env, result).value
    except:
        throw_js_error(env, "arrayHasElement requires (array, index)")
        return NapiValue()

# ---------------------------------------------------------------------------
# arrayDeleteElement(arr, index) — exposed as addon.arrayDeleteElement(arr, index)
#
# Deletes element at index (makes array sparse), returns the mutated array.
# ---------------------------------------------------------------------------
fn array_delete_element_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        if not js_is_array(b, env, args[0]):
            throw_js_error(b, env, "arrayDeleteElement: first argument must be an array")
            return NapiValue()
        var arr = JsArray(args[0])
        var index = JsUInt32.from_napi_value(b, env, args[1])
        _ = arr.delete_element(b, env, index)
        return arr.value
    except:
        throw_js_error(env, "arrayDeleteElement requires (array, index)")
        return NapiValue()

# ---------------------------------------------------------------------------
# getPrototype(obj) — exposed as addon.getPrototype(obj)
#
# Returns Object.getPrototypeOf(obj).
# ---------------------------------------------------------------------------
fn get_prototype_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var t0 = js_typeof(b, env, arg0)
        if t0 != NAPI_TYPE_OBJECT:
            throw_js_error_dynamic(b, env, "getPrototype: expected object, got " + js_type_name(t0))
            return NapiValue()
        var obj = JsObject(arg0)
        return obj.prototype(b, env)
    except:
        throw_js_error(env, "getPrototype requires one object argument")
        return NapiValue()

# ---------------------------------------------------------------------------
# strictEquals(a, b) — exposed as addon.strictEquals(a, b)
#
# Returns true if a === b (strict equality).
# ---------------------------------------------------------------------------
fn strict_equals_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var eq = js_strict_equals(b, env, args[0], args[1])
        return JsBoolean.create(b, env, eq).value
    except:
        throw_js_error(env, "strictEquals requires two arguments")
        return NapiValue()

# ---------------------------------------------------------------------------
# isInstanceOf(obj, ctor) — exposed as addon.isInstanceOf(obj, ctor)
#
# Returns true if obj instanceof ctor.
# ---------------------------------------------------------------------------
fn is_instance_of_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var t1 = js_typeof(b, env, args[1])
        if t1 != NAPI_TYPE_FUNCTION:
            throw_js_error_dynamic(b, env, "isInstanceOf: second arg must be a constructor, got " + js_type_name(t1))
            return NapiValue()
        var obj = JsObject(args[0])
        var result = obj.instance_of(b, env, args[1])
        return JsBoolean.create(b, env, result).value
    except:
        throw_js_error(env, "isInstanceOf requires (value, constructor)")
        return NapiValue()

# ---------------------------------------------------------------------------
# freezeObject(obj) — exposed as addon.freezeObject(obj)
#
# Freezes the object and returns it.
# ---------------------------------------------------------------------------
fn freeze_object_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var t0 = js_typeof(b, env, arg0)
        if t0 != NAPI_TYPE_OBJECT:
            throw_js_error_dynamic(b, env, "freezeObject: expected object, got " + js_type_name(t0))
            return NapiValue()
        var obj = JsObject(arg0)
        obj.freeze(b, env)
        return obj.value
    except:
        throw_js_error(env, "freezeObject requires one object argument")
        return NapiValue()

# ---------------------------------------------------------------------------
# sealObject(obj) — exposed as addon.sealObject(obj)
#
# Seals the object and returns it.
# ---------------------------------------------------------------------------
fn seal_object_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var t0 = js_typeof(b, env, arg0)
        if t0 != NAPI_TYPE_OBJECT:
            throw_js_error_dynamic(b, env, "sealObject: expected object, got " + js_type_name(t0))
            return NapiValue()
        var obj = JsObject(arg0)
        obj.seal(b, env)
        return obj.value
    except:
        throw_js_error(env, "sealObject requires one object argument")
        return NapiValue()

# ---------------------------------------------------------------------------
# AsyncProgressData — shared state for asyncProgress
#
# Heap-allocated with alloc[]. Contains only simple types (no Mojo String)
# because the execute callback runs on a worker thread.
#
# Lifetime: allocated in async_progress_fn, freed in progress_finalize_cb.
# The finalize_cb fires AFTER all TSFN call_js_cb invocations have completed,
# guaranteeing all progress callbacks run before the promise resolves.
# ---------------------------------------------------------------------------
struct AsyncProgressData(Movable):
    var deferred: NapiDeferred
    var work: NapiAsyncWork
    var tsfn: NapiThreadsafeFunction
    var count: Int
    var status: NapiStatus   # set by complete callback

    fn __init__(out self, deferred: NapiDeferred, work: NapiAsyncWork,
                tsfn: NapiThreadsafeFunction, count: Int):
        self.deferred = deferred
        self.work = work
        self.tsfn = tsfn
        self.count = count
        self.status = NAPI_OK

    fn __moveinit__(out self, deinit take: Self):
        self.deferred = take.deferred
        self.work = take.work
        self.tsfn = take.tsfn
        self.count = take.count
        self.status = take.status

# ---------------------------------------------------------------------------
# progress_call_js_cb — TSFN main thread callback
#
# Invoked on the main thread for each napi_call_threadsafe_function call.
# `data` is a heap-allocated Float64 from the worker thread.
# During Node.js teardown, env may be NULL — just free data and return.
# ---------------------------------------------------------------------------
fn progress_call_js_cb(
    env: NapiEnv,
    js_callback: NapiValue,
    context: OpaquePointer[MutAnyOrigin],
    data: OpaquePointer[MutAnyOrigin],
):
    # Free the data even if env is NULL (teardown)
    var val_ptr = data.bitcast[Float64]()
    var value = val_ptr[]
    val_ptr.destroy_pointee()
    val_ptr.free()
    # If env is NULL (teardown), skip the JS call
    if not env:
        return
    try:
        var js_val = JsNumber.create(env, value)
        _ = JsFunction(js_callback).call1(env, js_val.value)
    except:
        pass  # swallow errors in callback

# ---------------------------------------------------------------------------
# progress_finalize_cb — TSFN thread finalize callback
#
# Called when the TSFN is being destroyed, AFTER all pending call_js_cb
# invocations have completed. This is where we resolve/reject the promise
# to guarantee all progress callbacks have fired first.
# ---------------------------------------------------------------------------
fn progress_finalize_cb(
    env: NapiEnv,
    finalize_data: OpaquePointer[MutAnyOrigin],
    finalize_hint: OpaquePointer[MutAnyOrigin],
):
    var ptr = finalize_data.bitcast[AsyncProgressData]()
    if env:
        try:
            if ptr[].status == NAPI_OK:
                var result_val = JsNumber.create(env, Float64(ptr[].count))
                _ = raw_resolve_deferred(env, ptr[].deferred, result_val.value)
            else:
                var msg = JsString.create_literal(env, "async progress work failed")
                var null_code = NapiValue()
                var error_val = NapiValue()
                var error_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=error_val).bitcast[NoneType]()
                _ = raw_create_error(env, null_code, msg.value, error_ptr)
                _ = raw_reject_deferred(env, ptr[].deferred, error_val)
            _ = raw_delete_async_work(env, ptr[].work)
        except:
            pass
    ptr.destroy_pointee()
    ptr.free()

# ---------------------------------------------------------------------------
# async_progress_execute — worker thread callback
#
# Runs on a worker thread. MUST NOT call any N-API functions except
# napi_call_threadsafe_function. For each iteration, heap-allocates
# a Float64 value and queues it via TSFN.
# ---------------------------------------------------------------------------
fn async_progress_execute(env: NapiEnv, data: OpaquePointer[MutAnyOrigin]):
    var ptr = data.bitcast[AsyncProgressData]()
    var count = ptr[].count
    var tsfn = ptr[].tsfn
    for i in range(count):
        var val_ptr = alloc[Float64](1)
        val_ptr.init_pointee_move(Float64(i))
        try:
            _ = raw_call_threadsafe_function(
                tsfn, val_ptr.bitcast[NoneType](), NAPI_TSFN_BLOCKING)
        except:
            val_ptr.destroy_pointee()
            val_ptr.free()

# ---------------------------------------------------------------------------
# async_progress_complete — main thread callback
#
# Runs on the main thread after async_progress_execute finishes.
# Stores the completion status and releases the TSFN. Does NOT resolve
# the promise — that happens in progress_finalize_cb after all pending
# TSFN callbacks have been processed.
# ---------------------------------------------------------------------------
fn async_progress_complete(env: NapiEnv, status: NapiStatus, data: OpaquePointer[MutAnyOrigin]):
    var ptr = data.bitcast[AsyncProgressData]()
    ptr[].status = status
    try:
        # Release the TSFN — triggers finalize_cb after all pending calls drain
        _ = raw_release_threadsafe_function(ptr[].tsfn, NAPI_TSFN_RELEASE)
    except:
        pass
    # NOTE: do NOT free ptr here — progress_finalize_cb handles cleanup

# ---------------------------------------------------------------------------
# asyncProgress(count, callback) — exposed as addon.asyncProgress(count, cb)
#
# Creates a promise, sets up a TSFN for the callback, queues async work
# that calls callback(i) for each i in 0..count-1 from a worker thread,
# then resolves the promise with count.
#
# Promise resolution is deferred to the TSFN's thread_finalize_cb, which
# fires only after all progress callbacks have been delivered.
# ---------------------------------------------------------------------------
fn async_progress_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var count_val = args[0]
        var callback_val = args[1]
        var count = JsNumber.from_napi_value(b, env, count_val)

        # Create promise
        var p = JsPromise.create(b, env)

        # Create resource name for diagnostics
        var resource_name = JsString.create_literal(b, env, "asyncProgress")

        # Get call_js_cb function pointer
        var call_js_ref = progress_call_js_cb
        var call_js_ptr = UnsafePointer(to=call_js_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]

        # Get finalize_cb function pointer
        var finalize_ref = progress_finalize_cb
        var finalize_ptr = UnsafePointer(to=finalize_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]

        # Heap-allocate shared data (before creating TSFN — needed as finalize_data)
        var data_ptr = alloc[AsyncProgressData](1)
        data_ptr.init_pointee_move(AsyncProgressData(
            p.deferred, NapiAsyncWork(), NapiThreadsafeFunction(), Int(count)
        ))
        var data_opaque: OpaquePointer[MutAnyOrigin] = data_ptr.bitcast[NoneType]()

        # Create the TSFN with finalize callback
        var tsfn = ThreadsafeFunction.create(
            b, env, callback_val, resource_name.value, UInt(0),
            call_js_ptr, data_opaque, finalize_ptr)

        # Store TSFN handle in data struct
        data_ptr[].tsfn = tsfn.tsfn

        # Get async work callback pointers
        var exec_ref = async_progress_execute
        var comp_ref = async_progress_complete
        var exec_ptr = UnsafePointer(to=exec_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
        var comp_ptr = UnsafePointer(to=comp_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]

        # Create async work
        var work = NapiAsyncWork()
        var work_out: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=work).bitcast[NoneType]()
        var null_resource = NapiValue()

        check_status(raw_create_async_work(b,
            env,
            null_resource,
            resource_name.value,
            exec_ptr,
            comp_ptr,
            data_opaque,
            work_out,
        ))

        # Store work handle back into data struct
        data_ptr[].work = work

        # Queue the work
        check_status(raw_queue_async_work(b, env, work))

        return p.value
    except:
        throw_js_error(env, "asyncProgress requires (count, callback)")
        return NapiValue()

# ---------------------------------------------------------------------------
# External data
#
# ExternalData is a simple struct for testing napi_create_external.
# The finalize callback frees the heap-allocated data on GC.
# ---------------------------------------------------------------------------
struct ExternalData(Movable):
    var x: Float64
    var y: Float64

    fn __init__(out self, x: Float64, y: Float64):
        self.x = x
        self.y = y

    fn __moveinit__(out self, deinit take: Self):
        self.x = take.x
        self.y = take.y

fn external_finalize(env: NapiEnv, data: OpaquePointer[MutAnyOrigin], hint: OpaquePointer[MutAnyOrigin]):
    var ptr = data.bitcast[ExternalData]()
    ptr.destroy_pointee()
    ptr.free()

# ---------------------------------------------------------------------------
# createExternal(x, y) — exposed as addon.createExternal()
#
# Creates an external value wrapping a heap-allocated ExternalData{x, y}.
# ---------------------------------------------------------------------------
fn create_external_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var x = JsNumber.from_napi_value(b, env, args[0])
        var y = JsNumber.from_napi_value(b, env, args[1])
        var data_ptr = alloc[ExternalData](1)
        data_ptr.init_pointee_move(ExternalData(x, y))
        var fin_ref = external_finalize
        var fin_ptr = UnsafePointer(to=fin_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
        return JsExternal.create(b, env, data_ptr.bitcast[NoneType](), fin_ptr).value
    except:
        throw_js_error(env, "createExternal requires two number arguments")
        return NapiValue()

# ---------------------------------------------------------------------------
# getExternalData(ext) — exposed as addon.getExternalData()
#
# Retrieves the ExternalData from an external and returns {x, y} object.
# ---------------------------------------------------------------------------
fn get_external_data_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var t = js_typeof(b, env, arg0)
        if t != NAPI_TYPE_EXTERNAL:
            throw_js_type_error_dynamic(b, env,
                "getExternalData: expected external, got " + js_type_name(t))
            return NapiValue()
        var data = JsExternal.get_data(b, env, arg0)
        var ptr = data.bitcast[ExternalData]()
        var obj = JsObject.create(b, env)
        obj.set_property(b, env, "x", JsNumber.create(b, env, ptr[].x).value)
        obj.set_property(b, env, "y", JsNumber.create(b, env, ptr[].y).value)
        return obj.value
    except:
        throw_js_error(env, "getExternalData failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# isExternal(val) — exposed as addon.isExternal()
#
# Returns true if the value is an external (napi_typeof == NAPI_TYPE_EXTERNAL).
# ---------------------------------------------------------------------------
fn is_external_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var t = js_typeof(b, env, arg0)
        return JsBoolean.create(b, env, t == NAPI_TYPE_EXTERNAL).value
    except:
        throw_js_error(env, "isExternal requires one argument")
        return NapiValue()

# ---------------------------------------------------------------------------
# coerceToBool(val) — exposed as addon.coerceToBool()
#
# Equivalent to Boolean(value) in JavaScript.
# ---------------------------------------------------------------------------
fn coerce_to_bool_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        return js_coerce_to_bool(b, env, arg0)
    except:
        throw_js_error(env, "coerceToBool requires one argument")
        return NapiValue()

# ---------------------------------------------------------------------------
# coerceToNumber(val) — exposed as addon.coerceToNumber()
#
# Equivalent to Number(value) in JavaScript.
# Symbol input throws TypeError (pending exception from N-API).
# ---------------------------------------------------------------------------
fn coerce_to_number_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        return js_coerce_to_number(b, env, arg0)
    except:
        # May have a pending exception (e.g., Symbol coercion TypeError)
        # Don't overwrite it — just return
        return NapiValue()

# ---------------------------------------------------------------------------
# coerceToString(val) — exposed as addon.coerceToString()
#
# Equivalent to String(value) in JavaScript.
# Symbol input throws TypeError (pending exception from N-API).
# ---------------------------------------------------------------------------
fn coerce_to_string_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        return js_coerce_to_string(b, env, arg0)
    except:
        # May have a pending exception (e.g., Symbol coercion TypeError)
        # Don't overwrite it — just return
        return NapiValue()

# ---------------------------------------------------------------------------
# coerceToObject(val) — exposed as addon.coerceToObject()
#
# Equivalent to Object(value) in JavaScript.
# ---------------------------------------------------------------------------
fn coerce_to_object_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        return js_coerce_to_object(b, env, arg0)
    except:
        # May have a pending exception (e.g., null/undefined TypeError)
        # Don't overwrite it — just return
        return NapiValue()

# ---------------------------------------------------------------------------
# setPropertyByKey(obj, key, value) — exposed as addon.setPropertyByKey()
#
# Sets obj[key] = value using napi_set_property (napi_value key).
# Works with string keys, symbol keys, or any napi_value key.
# Returns the mutated object.
# ---------------------------------------------------------------------------
fn set_property_by_key_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var argc = CbArgs.argc(b, env, info)
        var argv = alloc[NapiValue](Int(argc))
        CbArgs.get_argv(b, env, info, argc, argv)
        var obj = argv[0]
        var key = argv[1]
        var val = argv[2]
        JsObject(obj).set(b, env, key, val)
        argv.free()
        return obj
    except:
        throw_js_error(env, "setPropertyByKey failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# hasPropertyByKey(obj, key) — exposed as addon.hasPropertyByKey()
#
# Checks if obj has the property using napi_has_property (napi_value key).
# Walks the prototype chain (unlike hasOwn).
# ---------------------------------------------------------------------------
fn has_property_by_key_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var result = JsObject(args[0]).has(b, env, args[1])
        return JsBoolean.create(b, env, result).value
    except:
        throw_js_error(env, "hasPropertyByKey failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# throwValue(val) — exposed as addon.throwValue()
#
# Throws any JavaScript value as an exception. Unlike throwTypeError/
# throwRangeError which create new Error objects, this throws the value
# directly — enabling re-throw of caught exceptions, or throwing strings,
# numbers, objects, etc.
# ---------------------------------------------------------------------------
fn throw_value_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        js_throw(b, env, arg0)
    except:
        pass
    return NapiValue()

# ---------------------------------------------------------------------------
# catchAndReturn(val) — exposed as addon.catchAndReturn()
#
# Demonstrates programmatic exception recovery: throws the argument as an
# exception via napi_throw, then immediately catches it with
# napi_get_and_clear_last_exception, and returns the caught value.
# ---------------------------------------------------------------------------
fn catch_and_return_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        # Throw the value to set a pending exception
        js_throw(b, env, arg0)
        # Now catch (clear) the pending exception and return it
        var caught = js_get_and_clear_last_exception(b, env)
        return caught
    except:
        return NapiValue()

# ---------------------------------------------------------------------------
# getNapiVersion() — exposed as addon.getNapiVersion()
#
# Returns the highest N-API version supported by this Node.js runtime.
# ---------------------------------------------------------------------------
fn get_napi_version_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var ver = get_napi_version(b, env)
        return JsNumber.create_int(b, env, Int(ver)).value
    except:
        throw_js_error(env, "getNapiVersion failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# getNodeVersion() — exposed as addon.getNodeVersion()
#
# Returns {major, minor, patch} object with the Node.js version.
# ---------------------------------------------------------------------------
fn get_node_version_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var ver = get_node_version_ptr(b, env)
        var obj = JsObject.create(b, env)
        obj.set_property(b, env, "major", JsNumber.create_int(b, env, Int(ver[0])).value)
        obj.set_property(b, env, "minor", JsNumber.create_int(b, env, Int(ver[1])).value)
        obj.set_property(b, env, "patch", JsNumber.create_int(b, env, Int(ver[2])).value)
        return obj.value
    except:
        throw_js_error(env, "getNodeVersion failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# External ArrayBuffer + Finalizer callbacks
# ---------------------------------------------------------------------------

## Finalizer for external arraybuffer — frees the Mojo-allocated byte buffer
fn external_ab_finalize(
    env: NapiEnv,
    data: OpaquePointer[MutAnyOrigin],
    hint: OpaquePointer[MutAnyOrigin],
):
    var ptr = data.bitcast[Byte]()
    ptr.free()

## createExternalArrayBuffer(size) — alloc Mojo memory, wrap as ArrayBuffer
fn create_external_arraybuffer_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var size = JsNumber.from_napi_value(b, env, arg0)
        var byte_len = UInt(Int(size))
        # Allocate Mojo-owned memory and fill with incrementing bytes
        var data_ptr = alloc[Byte](Int(byte_len))
        for i in range(Int(byte_len)):
            data_ptr[i] = Byte(i)
        # Get finalizer function pointer
        var fin_ref = external_ab_finalize
        var fin_ptr = UnsafePointer(to=fin_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
        # Create external arraybuffer — if this fails, free the Mojo-owned buffer
        var result = NapiValue()
        try:
            check_status(raw_create_external_arraybuffer(b, env,
                data_ptr.bitcast[NoneType](),
                byte_len,
                fin_ptr,
                OpaquePointer[MutAnyOrigin](),
                UnsafePointer(to=result).bitcast[NoneType]()))
        except e:
            data_ptr.free()
            raise e^
        return result
    except:
        throw_js_error(env, "createExternalArrayBuffer failed")
        return NapiValue()

## No-op finalizer for attachFinalizer — just frees a dummy byte
fn noop_finalize(
    env: NapiEnv,
    data: OpaquePointer[MutAnyOrigin],
    hint: OpaquePointer[MutAnyOrigin],
):
    # Free the dummy 1-byte allocation
    var ptr = data.bitcast[Byte]()
    ptr.free()

## attachFinalizer(obj) — attach a no-op native finalizer to any JS object
fn attach_finalizer_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        # Allocate a dummy 1-byte native object (napi_add_finalizer needs non-NULL data)
        var dummy = alloc[Byte](1)
        dummy[0] = Byte(0)
        var fin_ref = noop_finalize
        var fin_ptr = UnsafePointer(to=fin_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
        check_status(raw_add_finalizer(b, env, arg0,
            dummy.bitcast[NoneType](),
            fin_ptr,
            OpaquePointer[MutAnyOrigin](),
            OpaquePointer[MutAnyOrigin]()))
        return arg0
    except:
        throw_js_error(env, "attachFinalizer failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# Instance Data + Cleanup Hooks + Cancel Async callbacks
# ---------------------------------------------------------------------------

## Instance data finalizer — frees the Float64 allocation
fn instance_data_finalize(
    env: NapiEnv,
    data: OpaquePointer[MutAnyOrigin],
    hint: OpaquePointer[MutAnyOrigin],
):
    var ptr = data.bitcast[Float64]()
    ptr.destroy_pointee()
    ptr.free()

## setInstanceData(n) — stores a Float64 as per-env singleton
fn set_instance_data_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var n = JsNumber.from_napi_value(b, env, arg0)
        var data_ptr = alloc[Float64](1)
        data_ptr.init_pointee_move(n)
        var fin_ref = instance_data_finalize
        var fin_ptr = UnsafePointer(to=fin_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
        check_status(raw_set_instance_data(b, env,
            data_ptr.bitcast[NoneType](),
            fin_ptr,
            OpaquePointer[MutAnyOrigin]()))
        return JsUndefined.create(b, env).value
    except:
        throw_js_error(env, "setInstanceData failed")
        return NapiValue()

## getInstanceData() — retrieves the Float64 stored as instance data
fn get_instance_data_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var data = OpaquePointer[MutAnyOrigin]()
        check_status(raw_get_instance_data(b, env,
            UnsafePointer(to=data).bitcast[NoneType]()))
        if Int(data) == 0:
            return JsNull.create(b, env).value
        var ptr = data.bitcast[Float64]()
        return JsNumber.create(b, env, ptr[]).value
    except:
        throw_js_error(env, "getInstanceData failed")
        return NapiValue()

## No-op cleanup hook callback — fn(void*)
fn cleanup_hook_noop(arg: OpaquePointer[MutAnyOrigin]):
    pass

## addCleanupHook() — registers a no-op cleanup hook with a unique arg, returns true
fn add_cleanup_hook_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var hook_ref = cleanup_hook_noop
        var hook_ptr = UnsafePointer(to=hook_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
        # Allocate a unique 1-byte arg to make each (fun, arg) pair unique
        var arg_ptr = alloc[Byte](1)
        arg_ptr[0] = Byte(0)
        check_status(raw_add_env_cleanup_hook(b, env, hook_ptr, arg_ptr.bitcast[NoneType]()))
        return JsBoolean.create(b, env, True).value
    except:
        throw_js_error(env, "addCleanupHook failed")
        return NapiValue()

## removeCleanupHook() — unregisters the most recently added cleanup hook
## Note: we can't easily track the arg, so this is a best-effort test helper.
## In practice, addCleanupHook allocates unique args, making removal hard without tracking.
## For testing, we register and immediately remove with the same arg.
fn remove_cleanup_hook_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var hook_ref = cleanup_hook_noop
        var hook_ptr = UnsafePointer(to=hook_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
        # Register with a known arg, then immediately remove it
        var arg_ptr = alloc[Byte](1)
        arg_ptr[0] = Byte(0)
        check_status(raw_add_env_cleanup_hook(b, env, hook_ptr, arg_ptr.bitcast[NoneType]()))
        check_status(raw_remove_env_cleanup_hook(b, env, hook_ptr, arg_ptr.bitcast[NoneType]()))
        arg_ptr.free()
        return JsBoolean.create(b, env, True).value
    except:
        throw_js_error(env, "removeCleanupHook failed")
        return NapiValue()

## async_cleanup_hook_noop — no-op callback for async cleanup hook testing
##
## Signature: fn(napi_async_cleanup_hook_handle handle, void* arg)
fn async_cleanup_hook_noop(handle: OpaquePointer[MutAnyOrigin], arg: OpaquePointer[MutAnyOrigin]):
    pass

# ---------------------------------------------------------------------------
# Phase 26a: addAsyncCleanupHook() — registers an async cleanup hook
# ---------------------------------------------------------------------------
fn add_async_cleanup_hook_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var hook_ref = async_cleanup_hook_noop
        var hook_ptr = UnsafePointer(to=hook_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
        _ = add_async_cleanup_hook(b, env, hook_ptr, OpaquePointer[MutAnyOrigin]())
        return JsBoolean.create(b, env, True).value
    except:
        throw_js_error(env, "addAsyncCleanupHook failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# Phase 26a: removeAsyncCleanupHook() — registers then removes an async hook
# ---------------------------------------------------------------------------
fn remove_async_cleanup_hook_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var hook_ref = async_cleanup_hook_noop
        var hook_ptr = UnsafePointer(to=hook_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
        var handle = add_async_cleanup_hook(b, env, hook_ptr, OpaquePointer[MutAnyOrigin]())
        remove_async_cleanup_hook(b, handle)
        return JsBoolean.create(b, env, True).value
    except:
        throw_js_error(env, "removeAsyncCleanupHook failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# Phase 26b: getUvEventLoop() — returns the libuv loop pointer as BigInt
# ---------------------------------------------------------------------------
fn get_uv_event_loop_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var loop_ptr = get_uv_event_loop(b, env)
        # Return as BigInt so JS can compare equality (pointer values > 2^53)
        return JsBigInt.from_uint64(b, env, UInt64(Int(loop_ptr.bitcast[UInt8]()))).value
    except:
        throw_js_error(env, "getUvEventLoop failed")
        return NapiValue()

## Cancel async work data struct
struct CancelAsyncData(Movable):
    var deferred: NapiDeferred
    var work: NapiAsyncWork

    fn __init__(out self, deferred: NapiDeferred):
        self.deferred = deferred
        self.work = NapiAsyncWork()

    fn __moveinit__(out self, deinit take: Self):
        self.deferred = take.deferred
        self.work = take.work

## Cancel async execute — no-op (does nothing on worker thread)
fn cancel_async_execute(env: NapiEnv, data: OpaquePointer[MutAnyOrigin]):
    pass

## Cancel async complete — resolves or rejects based on status
fn cancel_async_complete(env: NapiEnv, status: NapiStatus, data: OpaquePointer[MutAnyOrigin]):
    var ptr = data.bitcast[CancelAsyncData]()
    try:
        _ = raw_delete_async_work(env, ptr[].work)
        if status == NAPI_OK:
            var result_val = JsString.create_literal(env, "completed")
            _ = raw_resolve_deferred(env, ptr[].deferred, result_val.value)
        else:
            # Cancelled or failed — reject with an Error
            var msg = JsString.create_literal(env, "cancelled")
            var null_code = NapiValue()
            var error_val = NapiValue()
            var error_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=error_val).bitcast[NoneType]()
            _ = raw_create_error(env, null_code, msg.value, error_ptr)
            _ = raw_reject_deferred(env, ptr[].deferred, error_val)
    except:
        pass
    ptr.destroy_pointee()
    ptr.free()

## cancelAsyncWork() — queues then immediately cancels async work
fn cancel_async_work_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var p = JsPromise.create(b, env)
        var data_ptr = alloc[CancelAsyncData](1)
        data_ptr.init_pointee_move(CancelAsyncData(p.deferred))

        var exec_ref = cancel_async_execute
        var complete_ref = cancel_async_complete
        var exec_ptr = UnsafePointer(to=exec_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
        var complete_ptr = UnsafePointer(to=complete_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]

        var resource_name = JsString.create_literal(b, env, "cancelTest")
        var work = NapiAsyncWork()
        var work_out_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=work).bitcast[NoneType]()
        check_status(raw_create_async_work(b, env,
            NapiValue(), resource_name.value,
            exec_ptr, complete_ptr,
            data_ptr.bitcast[NoneType](),
            work_out_ptr))
        data_ptr[].work = work

        check_status(raw_queue_async_work(b, env, work))
        # Immediately try to cancel
        _ = raw_cancel_async_work(b, env, work)

        return p.value
    except:
        throw_js_error(env, "cancelAsyncWork failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# BigInt words callbacks
# ---------------------------------------------------------------------------

## bigIntFromWords(sign, wordsArray) — create BigInt from sign + UInt64 word array
fn bigint_from_words_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var sign_bit = Int32(JsNumber.from_napi_value(b, env, args[0]))
        var arr_val = args[1]
        var arr = JsArray(arr_val)
        var arr_len = arr.length(b, env)
        var words_ptr = alloc[UInt64](Int(arr_len))
        for i in range(Int(arr_len)):
            var elem = arr.get(b, env, UInt32(i))
            var num = JsNumber.from_napi_value(b, env, elem)
            words_ptr[i] = UInt64(num)
        var result = JsBigInt.from_words(b, env, sign_bit, words_ptr.bitcast[NoneType](), UInt(arr_len))
        words_ptr.free()
        return result.value
    except:
        throw_js_error(env, "bigIntFromWords failed")
        return NapiValue()

## bigIntToWords(bi) — extract sign and UInt64 words from a BigInt
fn bigint_to_words_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        # Allocate an initial buffer (16 words = 128 bytes, handles up to 1024-bit BigInts)
        var sign: Int32 = 0
        var count: UInt = 16
        var words_ptr = alloc[UInt64](16)
        check_status(raw_get_value_bigint_words(b, env, arg0,
            UnsafePointer(to=sign).bitcast[NoneType](),
            UnsafePointer(to=count).bitcast[NoneType](),
            words_ptr.bitcast[NoneType]()))
        # Build result object {sign, words}
        var obj = JsObject.create(b, env)
        obj.set_property(b, env, "sign", JsNumber.create_int(b, env, Int(sign)).value)
        var arr = JsArray.create_with_length(b, env, count)
        for i in range(Int(count)):
            var word_val = JsNumber.create(b, env, Float64(words_ptr[i]))
            arr.set(b, env, UInt32(i), word_val.value)
        obj.set_property(b, env, "words", arr.value)
        words_ptr.free()
        return obj.value
    except:
        throw_js_error(env, "bigIntToWords failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# DataView callbacks
# ---------------------------------------------------------------------------

## createDataView(arraybuffer, byteOffset, byteLength) — create DataView over ArrayBuffer
fn create_dataview_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var argc = CbArgs.argc(b, env, info)
        if argc < 3:
            throw_js_type_error(b, env, "createDataView requires 3 arguments")
            return NapiValue()
        var argv_ptr = alloc[NapiValue](Int(argc))
        CbArgs.get_argv(b, env, info, argc, argv_ptr)
        var ab = argv_ptr[0]
        var byte_offset = JsNumber.from_napi_value(b, env, argv_ptr[1])
        var byte_length = JsNumber.from_napi_value(b, env, argv_ptr[2])
        argv_ptr.free()
        var dv = JsDataView.create(b, env, UInt(Int(byte_length)), ab, UInt(Int(byte_offset)))
        return dv.value
    except:
        throw_js_error(env, "createDataView failed")
        return NapiValue()

## getDataViewInfo(dv) — returns {byteLength, byteOffset}
fn get_dataview_info_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var dv = JsDataView(arg0)
        var bl = dv.byte_length(b, env)
        var bo = dv.byte_offset(b, env)
        var obj = JsObject.create(b, env)
        obj.set_property(b, env, "byteLength", JsNumber.create_int(b, env, Int(bl)).value)
        obj.set_property(b, env, "byteOffset", JsNumber.create_int(b, env, Int(bo)).value)
        return obj.value
    except:
        throw_js_error(env, "getDataViewInfo failed")
        return NapiValue()

## isDataView(val) — returns true if val is a DataView
fn is_dataview_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var result = JsDataView.is_dataview(b, env, arg0)
        return JsBoolean.create(b, env, result).value
    except:
        throw_js_error(env, "isDataView failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# Phase 21: isError(val) — checks if a value is an Error object
# ---------------------------------------------------------------------------
fn is_error_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        return JsBoolean.create(b, env, js_is_error(b, env, arg0)).value
    except:
        throw_js_error(env, "isError requires one argument")
        return NapiValue()

# ---------------------------------------------------------------------------
# Phase 21: adjustExternalMemory(changeInBytes) — inform V8 GC about native memory
# ---------------------------------------------------------------------------
fn adjust_external_memory_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var change = JsNumber.from_napi_value(b, env, arg0)
        var result = js_adjust_external_memory(b, env, Int64(Int(change)))
        return JsNumber.create(b, env, Float64(Int(result))).value
    except:
        throw_js_error(env, "adjustExternalMemory failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# Phase 21: runScript(code) — evaluate a JavaScript string (like eval())
# ---------------------------------------------------------------------------
fn run_script_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        return js_run_script(b, env, arg0)
    except:
        throw_js_error(env, "runScript failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# Phase 21: throwSyntaxError() — throws a SyntaxError
# ---------------------------------------------------------------------------
fn throw_syntax_error_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        throw_js_syntax_error(b, env, "test syntax error")
    except:
        throw_js_error(env, "throwSyntaxError failed")
    return NapiValue()

# ---------------------------------------------------------------------------
# Phase 22: isDetachedArrayBuffer(val) — check if an ArrayBuffer is detached
# ---------------------------------------------------------------------------
fn is_detached_arraybuffer_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        return JsBoolean.create(b, env, JsArrayBuffer.is_detached(b, env, arg0)).value
    except:
        throw_js_error(env, "isDetachedArrayBuffer failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# Phase 22: detachArrayBuffer(ab) — detach an ArrayBuffer
# ---------------------------------------------------------------------------
fn detach_arraybuffer_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var ab = JsArrayBuffer(arg0)
        ab.detach(b, env)
        return JsBoolean.create(b, env, True).value
    except:
        throw_js_error(env, "detachArrayBuffer failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# Phase 22: typeTagObject(obj, lower, upper) — tag an object with a UUID
# ---------------------------------------------------------------------------
fn type_tag_object_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
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
        var tag_ptr: OpaquePointer[ImmutAnyOrigin] = UnsafePointer(to=tag).bitcast[NoneType]()
        check_status(raw_type_tag_object(b, env, obj, tag_ptr))
        return JsBoolean.create(b, env, True).value
    except:
        throw_js_error(env, "typeTagObject failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# Phase 22: checkObjectTypeTag(obj, lower, upper) — check type tag
# ---------------------------------------------------------------------------
fn check_object_type_tag_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
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
        var tag_ptr: OpaquePointer[ImmutAnyOrigin] = UnsafePointer(to=tag).bitcast[NoneType]()
        var result: Bool = False
        check_status(raw_check_object_type_tag(b, env, obj, tag_ptr,
            UnsafePointer(to=result).bitcast[NoneType]()))
        return JsBoolean.create(b, env, result).value
    except:
        throw_js_error(env, "checkObjectTypeTag failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# Phase 23: testWeakRef(obj) — create weak ref (refcount=0) and retrieve value
# ---------------------------------------------------------------------------
fn test_weak_ref_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
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

# ---------------------------------------------------------------------------
# Phase 23: getAllPropertyNames(obj, mode, filter, conversion)
#
# Exposes the full napi_get_all_property_names API.
# mode: 0=INCLUDE_PROTOTYPES, 1=OWN_ONLY
# filter: bitmask of NAPI_KEY_* (e.g. ENUMERABLE=2, SKIP_SYMBOLS=16)
# conversion: 0=KEEP_NUMBERS, 1=NUMBERS_TO_STRINGS
# Returns an array of property keys.
# ---------------------------------------------------------------------------
fn get_all_property_names_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
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
        var result = JsObject(obj).keys_filtered(b, env, mode, filter, conversion)
        return result
    except:
        throw_js_error(env, "getAllPropertyNames failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# Phase 25a: createNamedFn() — creates a JS function with explicit name+length
#
# Returns a function named "myFn" with length=2. Demonstrates
# JsFunction.create_named(b, env, name, length, cb_ptr).
# ---------------------------------------------------------------------------
fn create_named_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var cb_ref = inner_callback_fn
        var name = String("myFn")
        var func = JsFunction.create_named(b, env, name, 2, fn_ptr(cb_ref))
        return func.value
    except:
        throw_js_error(env, "createNamedFn failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# Phase 25b: newCounterFromRegistry(n) — creates Counter(n) via ClassRegistry
#
# Retrieves the ClassRegistry from NapiBindings.registry and calls
# registry.new_instance("Counter", n). Demonstrates creating a class
# instance from arbitrary Mojo code (not just static methods).
# ---------------------------------------------------------------------------
fn new_counter_from_registry_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var registry = b[].registry.bitcast[ClassRegistry]()
        var argv_ptr: OpaquePointer[ImmutAnyOrigin] = UnsafePointer(to=arg0).bitcast[NoneType]()
        return registry[].new_instance(b, env, "Counter", 1, argv_ptr)
    except:
        throw_js_error(env, "newCounterFromRegistry failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# Phase 24a: getErrorMessage(err) — reads .message from a JS Error object
# ---------------------------------------------------------------------------
fn get_error_message_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var msg = js_get_error_message(b, env, arg0)
        return JsString.create(b, env, msg).value
    except:
        throw_js_error(env, "getErrorMessage failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# Phase 24a: getErrorStack(err) — reads .stack from a JS Error object
# ---------------------------------------------------------------------------
fn get_error_stack_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var stack = js_get_error_stack(b, env, arg0)
        return JsString.create(b, env, stack).value
    except:
        throw_js_error(env, "getErrorStack failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# Phase 24b: getOptValue(obj) — reads obj.x via get_opt, null if missing
# ---------------------------------------------------------------------------
fn get_opt_value_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
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

# ---------------------------------------------------------------------------
# Phase 24c: toJsString(val) — converts any JS value to string via js_to_string
# ---------------------------------------------------------------------------
fn to_js_string_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var s = js_to_string(b, env, arg0)
        return JsString.create(b, env, s).value
    except:
        throw_js_error(env, "toJsString failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# Module entry point
#
# Node.js finds "napi_register_module_v1" via dlsym after dlopen-ing our
# .node file. The @export decorator ensures C linkage and the exact symbol
# name Node.js expects.
#
# Each fn_ref var binds the function reference (8 bytes holding the code
# address). The UnsafePointer.bitcast[]()[] pattern reads it as an
# OpaquePointer for the NapiPropertyDescriptor.method field.
# All fn_ref vars are declared before the try block so they remain alive
# through all register_method calls (ASAP destruction safety).
# ---------------------------------------------------------------------------
@export("napi_register_module_v1", ABI="C")
fn register_module(env: NapiEnv, exports: NapiValue) -> NapiValue:
    # Allocate and initialize NapiBindings — resolves all 118 N-API symbols
    # once via a single OwnedDLHandle. The pointer is passed as callback data
    # to every registered function so callbacks can retrieve it cheaply.
    var bindings_ptr = alloc[NapiBindings](1)
    try:
        var bindings = NapiBindings()
        init_bindings(bindings)
        bindings_ptr.init_pointee_move(bindings^)
    except:
        bindings_ptr.free()
        return exports
    var cb_data = bindings_ptr.bitcast[NoneType]()

    # All fn_ref vars are declared before the try block so they remain alive
    # through all registration calls (ASAP destruction safety).
    var hello_ref = hello_fn
    var create_object_ref = create_object_fn
    var make_greeting_ref = make_greeting_fn
    var greet_ref = greet_fn
    var add_ref = add_fn
    var is_positive_ref = is_positive_fn
    var get_null_ref = get_null_fn
    var get_undefined_ref = get_undefined_fn
    var sum_array_ref = sum_array_fn
    var get_property_ref = get_property_fn
    var call_function_ref = call_function_fn
    var map_array_ref = map_array_fn
    var resolve_with_ref = resolve_with_fn
    var reject_with_ref = reject_with_fn
    var async_double_ref = async_double_fn
    var async_triple_ref = async_triple_fn
    var add_ints_ref = add_ints_fn
    var bitwise_or_ref = bitwise_or_fn
    var throw_type_error_ref = throw_type_error_fn
    var throw_range_error_ref = throw_range_error_fn
    var add_ints_strict_ref = add_ints_strict_fn
    var create_arraybuffer_ref = create_arraybuffer_fn
    var arraybuffer_length_ref = arraybuffer_length_fn
    var sum_buffer_ref = sum_buffer_fn
    var create_buffer_ref = create_buffer_fn
    var double_float64_array_ref = double_float64_array_fn
    var create_typed_array_view_ref = create_typed_array_view_fn
    var get_typed_array_type_ref = get_typed_array_type_fn
    var get_typed_array_length_ref = get_typed_array_length_fn
    var counter_constructor_ref = counter_constructor_fn
    var counter_get_value_ref = counter_get_value_fn
    var counter_set_value_ref = counter_set_value_fn
    var counter_increment_ref = counter_increment_fn
    var counter_reset_ref = counter_reset_fn
    var counter_is_counter_ref = counter_is_counter_fn
    var counter_from_value_ref = counter_from_value_fn
    var sum_args_ref = sum_args_fn
    var create_callback_ref = create_callback_fn
    var create_adder_ref = create_adder_fn
    var get_global_ref = get_global_fn
    var test_ref_ref = test_ref_fn
    var test_ref_object_ref = test_ref_object_fn
    var test_ref_string_ref = test_ref_string_fn
    var build_in_scope_ref = build_in_scope_fn
    var add_bigints_ref = add_bigints_fn
    var create_date_ref = create_date_fn
    var get_date_value_ref = get_date_value_fn
    var create_symbol_ref = create_symbol_fn
    var symbol_for_ref = symbol_for_fn
    var get_keys_ref = get_keys_fn
    var has_own_ref = has_own_fn
    var delete_property_ref = delete_property_fn
    var strict_equals_ref = strict_equals_fn
    var is_instance_of_ref = is_instance_of_fn
    var freeze_object_ref = freeze_object_fn
    var seal_object_ref = seal_object_fn
    var array_has_element_ref = array_has_element_fn
    var array_delete_element_ref = array_delete_element_fn
    var get_prototype_ref = get_prototype_fn
    var async_progress_ref = async_progress_fn
    var create_external_ref = create_external_fn
    var get_external_data_ref = get_external_data_fn
    var is_external_ref = is_external_fn
    var coerce_to_bool_ref = coerce_to_bool_fn
    var coerce_to_number_ref = coerce_to_number_fn
    var coerce_to_string_ref = coerce_to_string_fn
    var coerce_to_object_ref = coerce_to_object_fn
    var set_property_by_key_ref = set_property_by_key_fn
    var has_property_by_key_ref = has_property_by_key_fn
    var throw_value_ref = throw_value_fn
    var catch_and_return_ref = catch_and_return_fn
    var get_napi_version_ref = get_napi_version_fn
    var get_node_version_ref = get_node_version_fn
    var create_external_arraybuffer_ref = create_external_arraybuffer_fn
    var attach_finalizer_ref = attach_finalizer_fn
    var set_instance_data_ref = set_instance_data_fn
    var get_instance_data_ref = get_instance_data_fn
    var add_cleanup_hook_ref = add_cleanup_hook_fn
    var remove_cleanup_hook_ref = remove_cleanup_hook_fn
    var cancel_async_work_ref = cancel_async_work_fn
    var bigint_from_words_ref = bigint_from_words_fn
    var bigint_to_words_ref = bigint_to_words_fn
    var create_dataview_ref = create_dataview_fn
    var get_dataview_info_ref = get_dataview_info_fn
    var is_dataview_ref = is_dataview_fn
    var animal_constructor_ref = animal_constructor_fn
    var animal_get_name_ref = animal_get_name_fn
    var animal_speak_ref = animal_speak_fn
    var animal_is_animal_ref = animal_is_animal_fn
    var dog_constructor_ref = dog_constructor_fn
    var dog_get_breed_ref = dog_get_breed_fn
    # Phase 21-22
    var is_error_ref = is_error_fn
    var adjust_external_memory_ref = adjust_external_memory_fn
    var run_script_ref = run_script_fn
    var throw_syntax_error_ref = throw_syntax_error_fn
    var is_detached_arraybuffer_ref = is_detached_arraybuffer_fn
    var detach_arraybuffer_ref = detach_arraybuffer_fn
    var type_tag_object_ref = type_tag_object_fn
    var check_object_type_tag_ref = check_object_type_tag_fn
    var test_weak_ref_ref = test_weak_ref_fn
    var get_all_property_names_ref = get_all_property_names_fn
    # Phase 24
    var get_error_message_ref = get_error_message_fn
    var get_error_stack_ref = get_error_stack_fn
    var get_opt_value_ref = get_opt_value_fn
    var to_js_string_ref = to_js_string_fn
    # Phase 25
    var create_named_fn_ref = create_named_fn
    var new_counter_from_registry_ref = new_counter_from_registry_fn
    # Phase 26
    var add_async_cleanup_hook_fn_ref = add_async_cleanup_hook_fn
    var remove_async_cleanup_hook_fn_ref = remove_async_cleanup_hook_fn
    var get_uv_event_loop_fn_ref = get_uv_event_loop_fn

    try:
        var m = ModuleBuilder(env, exports, cb_data)

        # Generated functions (from src/exports.toml)
        register_generated(m)

        # Simple methods
        m.method("hello", fn_ptr(hello_ref))
        m.method("createObject", fn_ptr(create_object_ref))
        m.method("makeGreeting", fn_ptr(make_greeting_ref))
        m.method("greet", fn_ptr(greet_ref))
        m.method("add", fn_ptr(add_ref))
        m.method("isPositive", fn_ptr(is_positive_ref))
        m.method("getNull", fn_ptr(get_null_ref))
        m.method("getUndefined", fn_ptr(get_undefined_ref))
        m.method("sumArray", fn_ptr(sum_array_ref))
        m.method("getProperty", fn_ptr(get_property_ref))
        m.method("callFunction", fn_ptr(call_function_ref))
        m.method("mapArray", fn_ptr(map_array_ref))
        m.method("resolveWith", fn_ptr(resolve_with_ref))
        m.method("rejectWith", fn_ptr(reject_with_ref))
        m.method("asyncDouble", fn_ptr(async_double_ref))
        m.method("asyncTriple", fn_ptr(async_triple_ref))
        m.method("addInts", fn_ptr(add_ints_ref))
        m.method("bitwiseOr", fn_ptr(bitwise_or_ref))
        m.method("throwTypeError", fn_ptr(throw_type_error_ref))
        m.method("throwRangeError", fn_ptr(throw_range_error_ref))
        m.method("addIntsStrict", fn_ptr(add_ints_strict_ref))
        m.method("createArrayBuffer", fn_ptr(create_arraybuffer_ref))
        m.method("arrayBufferLength", fn_ptr(arraybuffer_length_ref))
        m.method("sumBuffer", fn_ptr(sum_buffer_ref))
        m.method("createBuffer", fn_ptr(create_buffer_ref))
        m.method("doubleFloat64Array", fn_ptr(double_float64_array_ref))
        m.method("createTypedArrayView", fn_ptr(create_typed_array_view_ref))
        m.method("getTypedArrayType", fn_ptr(get_typed_array_type_ref))
        m.method("getTypedArrayLength", fn_ptr(get_typed_array_length_ref))
        m.method("sumArgs", fn_ptr(sum_args_ref))
        m.method("createCallback", fn_ptr(create_callback_ref))
        m.method("createAdder", fn_ptr(create_adder_ref))
        m.method("getGlobal", fn_ptr(get_global_ref))
        m.method("testRef", fn_ptr(test_ref_ref))
        m.method("testRefObject", fn_ptr(test_ref_object_ref))
        m.method("testRefString", fn_ptr(test_ref_string_ref))
        m.method("buildInScope", fn_ptr(build_in_scope_ref))
        m.method("addBigInts", fn_ptr(add_bigints_ref))
        m.method("createDate", fn_ptr(create_date_ref))
        m.method("getDateValue", fn_ptr(get_date_value_ref))
        m.method("createSymbol", fn_ptr(create_symbol_ref))
        m.method("symbolFor", fn_ptr(symbol_for_ref))
        m.method("getKeys", fn_ptr(get_keys_ref))
        m.method("hasOwn", fn_ptr(has_own_ref))
        m.method("deleteProperty", fn_ptr(delete_property_ref))
        m.method("strictEquals", fn_ptr(strict_equals_ref))
        m.method("isInstanceOf", fn_ptr(is_instance_of_ref))
        m.method("freezeObject", fn_ptr(freeze_object_ref))
        m.method("sealObject", fn_ptr(seal_object_ref))
        m.method("arrayHasElement", fn_ptr(array_has_element_ref))
        m.method("arrayDeleteElement", fn_ptr(array_delete_element_ref))
        m.method("getPrototype", fn_ptr(get_prototype_ref))
        m.method("asyncProgress", fn_ptr(async_progress_ref))
        m.method("createExternal", fn_ptr(create_external_ref))
        m.method("getExternalData", fn_ptr(get_external_data_ref))
        m.method("isExternal", fn_ptr(is_external_ref))
        m.method("coerceToBool", fn_ptr(coerce_to_bool_ref))
        m.method("coerceToNumber", fn_ptr(coerce_to_number_ref))
        m.method("coerceToString", fn_ptr(coerce_to_string_ref))
        m.method("coerceToObject", fn_ptr(coerce_to_object_ref))
        m.method("setPropertyByKey", fn_ptr(set_property_by_key_ref))
        m.method("hasPropertyByKey", fn_ptr(has_property_by_key_ref))
        m.method("throwValue", fn_ptr(throw_value_ref))
        m.method("catchAndReturn", fn_ptr(catch_and_return_ref))
        m.method("getNapiVersion", fn_ptr(get_napi_version_ref))
        m.method("getNodeVersion", fn_ptr(get_node_version_ref))
        m.method("createExternalArrayBuffer", fn_ptr(create_external_arraybuffer_ref))
        m.method("attachFinalizer", fn_ptr(attach_finalizer_ref))
        m.method("setInstanceData", fn_ptr(set_instance_data_ref))
        m.method("getInstanceData", fn_ptr(get_instance_data_ref))
        m.method("addCleanupHook", fn_ptr(add_cleanup_hook_ref))
        m.method("removeCleanupHook", fn_ptr(remove_cleanup_hook_ref))
        m.method("cancelAsyncWork", fn_ptr(cancel_async_work_ref))
        m.method("bigIntFromWords", fn_ptr(bigint_from_words_ref))
        m.method("bigIntToWords", fn_ptr(bigint_to_words_ref))
        m.method("createDataView", fn_ptr(create_dataview_ref))
        m.method("getDataViewInfo", fn_ptr(get_dataview_info_ref))
        m.method("isDataView", fn_ptr(is_dataview_ref))
        # Phase 21-22
        m.method("isError", fn_ptr(is_error_ref))
        m.method("adjustExternalMemory", fn_ptr(adjust_external_memory_ref))
        m.method("runScript", fn_ptr(run_script_ref))
        m.method("throwSyntaxError", fn_ptr(throw_syntax_error_ref))
        m.method("isDetachedArrayBuffer", fn_ptr(is_detached_arraybuffer_ref))
        m.method("detachArrayBuffer", fn_ptr(detach_arraybuffer_ref))
        m.method("typeTagObject", fn_ptr(type_tag_object_ref))
        m.method("checkObjectTypeTag", fn_ptr(check_object_type_tag_ref))
        m.method("testWeakRef", fn_ptr(test_weak_ref_ref))
        m.method("getAllPropertyNames", fn_ptr(get_all_property_names_ref))
        # Phase 24
        m.method("getErrorMessage", fn_ptr(get_error_message_ref))
        m.method("getErrorStack", fn_ptr(get_error_stack_ref))
        m.method("getOptValue", fn_ptr(get_opt_value_ref))
        m.method("toJsString", fn_ptr(to_js_string_ref))
        # Phase 25
        m.method("createNamedFn", fn_ptr(create_named_fn_ref))
        m.method("newCounterFromRegistry", fn_ptr(new_counter_from_registry_ref))
        # Phase 26
        m.method("addAsyncCleanupHook", fn_ptr(add_async_cleanup_hook_fn_ref))
        m.method("removeAsyncCleanupHook", fn_ptr(remove_async_cleanup_hook_fn_ref))
        m.method("getUvEventLoop", fn_ptr(get_uv_event_loop_fn_ref))

        # Counter class
        var counter = m.class_def("Counter", fn_ptr(counter_constructor_ref))
        counter.instance_method("increment", fn_ptr(counter_increment_ref))
        counter.instance_method("reset", fn_ptr(counter_reset_ref))
        counter.getter_setter("value", fn_ptr(counter_get_value_ref), fn_ptr(counter_set_value_ref))
        counter.static_method("isCounter", fn_ptr(counter_is_counter_ref))
        counter.static_method("fromValue", fn_ptr(counter_from_value_ref))
        # Phase 25b: ClassRegistry — store Counter constructor for new_instance
        var registry = ClassRegistry()
        registry.register(bindings_ptr, env, "Counter", counter.ctor)
        var registry_ptr = alloc[ClassRegistry](1)
        registry_ptr.init_pointee_move(registry^)
        bindings_ptr[].registry = registry_ptr.bitcast[NoneType]()

        # Animal class
        var animal = m.class_def("Animal", fn_ptr(animal_constructor_ref))
        animal.getter("name", fn_ptr(animal_get_name_ref))
        animal.instance_method("speak", fn_ptr(animal_speak_ref))
        animal.static_method("isAnimal", fn_ptr(animal_is_animal_ref))

        # Dog class (inherits from Animal)
        var dog = m.class_def("Dog", fn_ptr(dog_constructor_ref))
        dog.getter("breed", fn_ptr(dog_get_breed_ref))
        dog.inherits(animal)
    except:
        pass

    return exports
