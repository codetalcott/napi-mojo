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
from napi.types import NapiEnv, NapiValue, NapiStatus, NapiDeferred, NapiAsyncWork, NapiThreadsafeFunction, NAPI_TYPE_STRING, NAPI_TYPE_NUMBER, NAPI_TYPE_OBJECT, NAPI_TYPE_FUNCTION, NAPI_TYPE_BIGINT, NAPI_TYPE_EXTERNAL, NAPI_OK, NAPI_TSFN_BLOCKING, NAPI_TSFN_RELEASE
from napi.raw import raw_create_error, raw_resolve_deferred, raw_reject_deferred, raw_create_async_work, raw_queue_async_work, raw_delete_async_work, raw_call_threadsafe_function, raw_release_threadsafe_function, raw_new_instance, raw_get_value_bigint_words, raw_add_finalizer, raw_create_external_arraybuffer, raw_set_instance_data, raw_get_instance_data, raw_add_env_cleanup_hook, raw_remove_env_cleanup_hook, raw_cancel_async_work
from napi.framework.threadsafe_function import ThreadsafeFunction
from napi.framework.js_string import JsString
from napi.framework.js_object import JsObject
from napi.framework.js_number import JsNumber
from napi.framework.js_boolean import JsBoolean
from napi.framework.js_null import JsNull
from napi.framework.js_undefined import JsUndefined
from napi.framework.js_array import JsArray
from napi.framework.js_function import JsFunction
from napi.framework.js_promise import JsPromise
from napi.framework.args import CbArgs
from napi.framework.js_value import js_typeof, js_type_name, js_is_array, js_get_global, js_strict_equals
from napi.framework.handle_scope import HandleScope
from napi.framework.js_int32 import JsInt32
from napi.framework.js_uint32 import JsUInt32
from napi.framework.js_arraybuffer import JsArrayBuffer
from napi.framework.js_buffer import JsBuffer
from napi.framework.js_typedarray import JsTypedArray
from napi.framework.js_class import unwrap_native
from napi.framework.register import fn_ptr, ModuleBuilder
from generated.callbacks import register_generated
from napi.framework.js_ref import JsRef
from napi.framework.escapable_handle_scope import EscapableHandleScope
from napi.framework.js_bigint import JsBigInt
from napi.framework.js_date import JsDate
from napi.framework.js_symbol import JsSymbol
from napi.framework.js_external import JsExternal
from napi.framework.js_coerce import js_coerce_to_bool, js_coerce_to_number, js_coerce_to_string, js_coerce_to_object
from napi.framework.js_exception import js_throw, js_is_exception_pending, js_get_and_clear_last_exception
from napi.framework.js_dataview import JsDataView
from napi.framework.js_version import get_napi_version, get_node_version_ptr
from napi.raw import raw_wrap
from napi.error import throw_js_error, throw_js_error_dynamic, throw_js_type_error, throw_js_type_error_dynamic, throw_js_range_error, check_status

# ---------------------------------------------------------------------------
# hello() — exposed as addon.hello()
#
# Returns the JavaScript string "Hello from Mojo!".
# Signature matches napi_callback: fn(NapiEnv, NapiValue) -> NapiValue.
# Cannot be `raises` — Node.js calls this directly via C function pointer.
# ---------------------------------------------------------------------------
fn hello_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        return JsString.create_literal(env, "Hello from Mojo!").value
    except:
        return NapiValue()

# ---------------------------------------------------------------------------
# createObject() — exposed as addon.createObject()
#
# Returns a new empty JavaScript object {}.
# ---------------------------------------------------------------------------
fn create_object_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        return JsObject.create(env).value
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
        var obj = JsObject.create(env)
        var msg = JsString.create_literal(env, "Hello!")
        obj.set_property(env, "message", msg.value)
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
        var arg0 = CbArgs.get_one(env, info)
        var t = js_typeof(env, arg0)
        if t != NAPI_TYPE_STRING:
            throw_js_error_dynamic(env, "greet: expected string, got " + js_type_name(t))
            return NapiValue()
        var name = JsString.from_napi_value(env, arg0)
        return JsString.create(env, "Hello, " + name + "!").value
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
        var args = CbArgs.get_two(env, info)
        var a = JsNumber.from_napi_value(env, args[0])
        var b = JsNumber.from_napi_value(env, args[1])
        return JsNumber.create(env, a + b).value
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
        var arg0 = CbArgs.get_one(env, info)
        var n = JsNumber.from_napi_value(env, arg0)
        return JsBoolean.create(env, n > 0).value
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
        return JsNull.create(env).value
    except:
        return NapiValue()

# ---------------------------------------------------------------------------
# getUndefined() — exposed as addon.getUndefined()
#
# Returns the JavaScript undefined singleton. Demonstrates JsUndefined.create().
# ---------------------------------------------------------------------------
fn get_undefined_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        return JsUndefined.create(env).value
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
        var arg0 = CbArgs.get_one(env, info)
        if not js_is_array(env, arg0):
            var t = js_typeof(env, arg0)
            throw_js_error_dynamic(env, "sumArray: expected array, got " + js_type_name(t))
            return NapiValue()
        var arr = JsArray(arg0)
        var len = arr.length(env)
        var total: Float64 = 0.0
        for i in range(Int(len)):
            var elem = arr.get(env, UInt32(i))
            total += JsNumber.from_napi_value(env, elem)
        return JsNumber.create(env, total).value
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
        var args = CbArgs.get_two(env, info)
        var t0 = js_typeof(env, args[0])
        if t0 != NAPI_TYPE_OBJECT:
            throw_js_error_dynamic(env, "getProperty: expected object, got " + js_type_name(t0))
            return NapiValue()
        var t1 = js_typeof(env, args[1])
        if t1 != NAPI_TYPE_STRING:
            throw_js_error_dynamic(env, "getProperty: expected string key, got " + js_type_name(t1))
            return NapiValue()
        var obj = JsObject(args[0])
        return obj.get(env, args[1])
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
        var args = CbArgs.get_two(env, info)
        var t = js_typeof(env, args[0])
        if t != NAPI_TYPE_FUNCTION:
            throw_js_error_dynamic(env, "callFunction: expected function, got " + js_type_name(t))
            return NapiValue()
        var func = JsFunction(args[0])
        return func.call1(env, args[1])
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
        var args = CbArgs.get_two(env, info)
        if not js_is_array(env, args[0]):
            var t = js_typeof(env, args[0])
            throw_js_error_dynamic(env, "mapArray: expected array, got " + js_type_name(t))
            return NapiValue()
        var t1 = js_typeof(env, args[1])
        if t1 != NAPI_TYPE_FUNCTION:
            throw_js_error_dynamic(env, "mapArray: expected function, got " + js_type_name(t1))
            return NapiValue()
        var arr = JsArray(args[0])
        var func = JsFunction(args[1])
        var len = arr.length(env)
        var result = JsArray.create_with_length(env, UInt(len))
        for i in range(Int(len)):
            var hs = HandleScope.open(env)
            var ok = True
            try:
                var elem = arr.get(env, UInt32(i))
                var mapped = func.call1(env, elem)
                result.set(env, UInt32(i), mapped)
            except:
                ok = False
            hs.close(env)
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
        var arg0 = CbArgs.get_one(env, info)
        var p = JsPromise.create(env)
        p.resolve(env, arg0)
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
        var arg0 = CbArgs.get_one(env, info)
        var t = js_typeof(env, arg0)
        if t != NAPI_TYPE_STRING:
            throw_js_error_dynamic(env, "rejectWith: expected string, got " + js_type_name(t))
            return NapiValue()
        # Create an Error object from the message string (without throwing)
        var null_code = NapiValue()
        var error_val = NapiValue()
        var error_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=error_val).bitcast[NoneType]()
        check_status(raw_create_error(env, null_code, arg0, error_ptr))
        var p = JsPromise.create(env)
        p.reject(env, error_val)
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

    fn __init__(out self, deferred: NapiDeferred, work: NapiAsyncWork, input: Float64):
        self.deferred = deferred
        self.work = work
        self.input = input
        self.result = 0.0

    fn __moveinit__(out self, deinit take: Self):
        self.deferred = take.deferred
        self.work = take.work
        self.input = take.input
        self.result = take.result

# ---------------------------------------------------------------------------
# async_double_execute — worker thread callback
#
# Runs on a worker thread. MUST NOT call any N-API functions.
# Performs pure computation: result = input * 2.
# ---------------------------------------------------------------------------
fn async_double_execute(env: NapiEnv, data: OpaquePointer[MutAnyOrigin]):
    var ptr = data.bitcast[AsyncDoubleData]()
    ptr[].result = ptr[].input * 2.0

# ---------------------------------------------------------------------------
# async_double_complete — main thread callback
#
# Runs on the main thread after execute finishes. Resolves the promise
# with the computed result, then cleans up the async work handle and
# heap-allocated data.
# ---------------------------------------------------------------------------
fn async_double_complete(env: NapiEnv, status: NapiStatus, data: OpaquePointer[MutAnyOrigin]):
    var ptr = data.bitcast[AsyncDoubleData]()
    try:
        if status == NAPI_OK:
            var result_val = JsNumber.create(env, ptr[].result)
            _ = raw_resolve_deferred(env, ptr[].deferred, result_val.value)
        else:
            var msg = JsString.create_literal(env, "async work failed")
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
# asyncDouble(n) — exposed as addon.asyncDouble(n)
#
# Creates a promise, queues async work that computes n * 2 on a worker
# thread, and returns the promise. When the work completes, the promise
# is resolved with the result.
# ---------------------------------------------------------------------------
fn async_double_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var arg0 = CbArgs.get_one(env, info)
        var n = JsNumber.from_napi_value(env, arg0)

        # Create promise
        var p = JsPromise.create(env)

        # Create resource name for diagnostics
        var resource_name = JsString.create_literal(env, "asyncDouble")

        # Heap-allocate shared data (NapiAsyncWork() is placeholder — set after creation)
        var data_ptr = alloc[AsyncDoubleData](1)
        data_ptr.init_pointee_move(AsyncDoubleData(p.deferred, NapiAsyncWork(), n))

        # Get function pointers for execute and complete callbacks
        var exec_ref = async_double_execute
        var comp_ref = async_double_complete
        var exec_ptr = UnsafePointer(to=exec_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
        var comp_ptr = UnsafePointer(to=comp_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]

        # Create async work
        var work = NapiAsyncWork()
        var work_out: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=work).bitcast[NoneType]()
        var null_resource = NapiValue()
        var data_opaque: OpaquePointer[MutAnyOrigin] = data_ptr.bitcast[NoneType]()

        check_status(raw_create_async_work(
            env,
            null_resource,
            resource_name.value,
            exec_ptr,
            comp_ptr,
            data_opaque,
            work_out,
        ))

        # Store the work handle in the data struct so complete can delete it
        data_ptr[].work = work

        # Queue the work
        check_status(raw_queue_async_work(env, work))

        return p.value
    except:
        throw_js_error(env, "asyncDouble requires one number argument")
        return NapiValue()

# ---------------------------------------------------------------------------
# addInts(a, b) — exposed as addon.addInts(a, b)
#
# Takes two JavaScript number arguments, reads them as Int32, returns their sum.
# ---------------------------------------------------------------------------
fn add_ints_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var args = CbArgs.get_two(env, info)
        var ta = js_typeof(env, args[0])
        var tb = js_typeof(env, args[1])
        if ta != NAPI_TYPE_NUMBER or tb != NAPI_TYPE_NUMBER:
            throw_js_error(env, "addInts requires two number arguments")
            return NapiValue()
        var a = JsInt32.from_napi_value(env, args[0])
        var b = JsInt32.from_napi_value(env, args[1])
        return JsInt32.create(env, a + b).value
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
        var args = CbArgs.get_two(env, info)
        var ta = js_typeof(env, args[0])
        var tb = js_typeof(env, args[1])
        if ta != NAPI_TYPE_NUMBER or tb != NAPI_TYPE_NUMBER:
            throw_js_error(env, "bitwiseOr requires two number arguments")
            return NapiValue()
        var a = JsUInt32.from_napi_value(env, args[0])
        var b = JsUInt32.from_napi_value(env, args[1])
        return JsUInt32.create(env, a | b).value
    except:
        throw_js_error(env, "bitwiseOr requires two number arguments")
        return NapiValue()

# ---------------------------------------------------------------------------
# throwTypeError() — exposed as addon.throwTypeError()
#
# Throws a JavaScript TypeError with a fixed message.
# ---------------------------------------------------------------------------
fn throw_type_error_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    throw_js_type_error(env, "wrong type")
    return NapiValue()

# ---------------------------------------------------------------------------
# throwRangeError() — exposed as addon.throwRangeError()
#
# Throws a JavaScript RangeError with a fixed message.
# ---------------------------------------------------------------------------
fn throw_range_error_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    throw_js_range_error(env, "out of range")
    return NapiValue()

# ---------------------------------------------------------------------------
# addIntsStrict(a, b) — exposed as addon.addIntsStrict(a, b)
#
# Like addInts but throws TypeError (not Error) on type mismatch.
# ---------------------------------------------------------------------------
fn add_ints_strict_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var args = CbArgs.get_two(env, info)
        var ta = js_typeof(env, args[0])
        var tb = js_typeof(env, args[1])
        if ta != NAPI_TYPE_NUMBER or tb != NAPI_TYPE_NUMBER:
            throw_js_type_error_dynamic(env,
                "addIntsStrict: expected two numbers, got " + js_type_name(ta) + " and " + js_type_name(tb))
            return NapiValue()
        var a = JsInt32.from_napi_value(env, args[0])
        var b = JsInt32.from_napi_value(env, args[1])
        return JsInt32.create(env, a + b).value
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
        var arg0 = CbArgs.get_one(env, info)
        var ta = js_typeof(env, arg0)
        if ta != NAPI_TYPE_NUMBER:
            throw_js_error(env, "createArrayBuffer requires a number argument")
            return NapiValue()
        var size = JsNumber.from_napi_value(env, arg0)
        return JsArrayBuffer.create_and_fill(env, UInt(Int(size))).value
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
        var arg0 = CbArgs.get_one(env, info)
        if not JsArrayBuffer.is_arraybuffer(env, arg0):
            throw_js_error(env, "arrayBufferLength requires an ArrayBuffer argument")
            return NapiValue()
        var ab = JsArrayBuffer(arg0)
        var length = ab.byte_length(env)
        return JsNumber.create(env, Float64(length)).value
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
        var arg0 = CbArgs.get_one(env, info)
        if not JsBuffer.is_buffer(env, arg0):
            throw_js_error(env, "sumBuffer requires a Buffer argument")
            return NapiValue()
        var buf = JsBuffer(arg0)
        var ptr = buf.data_ptr(env)
        var len = buf.length(env)
        var total: Float64 = 0.0
        for i in range(Int(len)):
            total += Float64(Int(ptr[i]))
        return JsNumber.create(env, total).value
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
        var arg0 = CbArgs.get_one(env, info)
        var ta = js_typeof(env, arg0)
        if ta != NAPI_TYPE_NUMBER:
            throw_js_error(env, "createBuffer requires a number argument")
            return NapiValue()
        var size = JsNumber.from_napi_value(env, arg0)
        return JsBuffer.create_and_fill(env, UInt(Int(size))).value
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
        var arg0 = CbArgs.get_one(env, info)
        if not JsTypedArray.is_typedarray(env, arg0):
            throw_js_error(env, "doubleFloat64Array requires a TypedArray argument")
            return NapiValue()
        var ta = JsTypedArray(arg0)
        var len = ta.length(env)
        var byte_ptr = ta.data_ptr(env)
        var float_ptr = byte_ptr.bitcast[Float64]()
        for i in range(Int(len)):
            float_ptr[i] = float_ptr[i] * 2.0
        return arg0
    except:
        throw_js_error(env, "doubleFloat64Array requires a TypedArray argument")
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
        var this_val = CbArgs.get_this(env, info)
        var arg0 = CbArgs.get_one(env, info)
        var t = js_typeof(env, arg0)
        if t != NAPI_TYPE_NUMBER:
            throw_js_type_error(env, "Counter constructor requires a number argument")
            return NapiValue()
        var initial = JsNumber.from_napi_value(env, arg0)

        # Heap-allocate native data
        var data_ptr = alloc[CounterData](1)
        data_ptr.init_pointee_move(CounterData(initial))

        # Get finalize function pointer
        var fin_ref = counter_finalize
        var fin_ptr = UnsafePointer(to=fin_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]

        # Wrap native data onto this
        check_status(raw_wrap(
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
        var ptr = unwrap_native[CounterData](env, info)
        return JsNumber.create(env, ptr[].count).value
    except:
        throw_js_error(env, "Counter.value getter failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# counter_set_value_fn — Counter.prototype.value setter
# ---------------------------------------------------------------------------
fn counter_set_value_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var arg0 = CbArgs.get_one(env, info)
        var t = js_typeof(env, arg0)
        if t != NAPI_TYPE_NUMBER:
            throw_js_type_error(env, "Counter.value setter requires a number")
            return NapiValue()
        var new_val = JsNumber.from_napi_value(env, arg0)
        var ptr = unwrap_native[CounterData](env, info)
        ptr[].count = new_val
        return JsUndefined.create(env).value
    except:
        throw_js_error(env, "Counter.value setter failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# counter_increment_fn — Counter.prototype.increment()
# ---------------------------------------------------------------------------
fn counter_increment_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var ptr = unwrap_native[CounterData](env, info)
        ptr[].count += 1.0
        return JsUndefined.create(env).value
    except:
        throw_js_error(env, "Counter.increment failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# counter_reset_fn — Counter.prototype.reset()
# ---------------------------------------------------------------------------
fn counter_reset_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var ptr = unwrap_native[CounterData](env, info)
        ptr[].count = ptr[].initial
        return JsUndefined.create(env).value
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
        var this_val = CbArgs.get_this(env, info)
        var arg0 = CbArgs.get_one(env, info)
        # napi_instanceof requires object LHS — primitives are never instanceof
        var t = js_typeof(env, arg0)
        if t != NAPI_TYPE_OBJECT and t != NAPI_TYPE_FUNCTION:
            return JsBoolean.create(env, False).value
        var result = JsObject(arg0).instance_of(env, this_val)
        return JsBoolean.create(env, result).value
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
        var this_val = CbArgs.get_this(env, info)
        var arg0 = CbArgs.get_one(env, info)
        var t = js_typeof(env, arg0)
        if t != NAPI_TYPE_NUMBER:
            throw_js_type_error(env, "Counter.fromValue requires a number argument")
            return NapiValue()
        var result = NapiValue()
        var argv_ptr: OpaquePointer[ImmutAnyOrigin] = UnsafePointer(to=arg0).bitcast[NoneType]()
        check_status(raw_new_instance(
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
        var this_val = CbArgs.get_this(env, info)
        var arg0 = CbArgs.get_one(env, info)
        var t = js_typeof(env, arg0)
        if t != NAPI_TYPE_STRING:
            throw_js_type_error(env, "Animal constructor requires a string name")
            return NapiValue()
        var name_str = JsString.from_napi_value(env, arg0)
        var name_len = UInt(len(name_str))
        var name_buf = alloc[Byte](Int(name_len))
        for i in range(Int(name_len)):
            name_buf[i] = name_str.as_bytes()[i]

        var data_ptr = alloc[AnimalData](1)
        data_ptr.init_pointee_move(AnimalData(name_buf.bitcast[NoneType](), name_len))

        var fin_ref = animal_finalize
        var fin_ptr = UnsafePointer(to=fin_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]

        check_status(raw_wrap(
            env, this_val,
            data_ptr.bitcast[NoneType](),
            fin_ptr,
            OpaquePointer[MutAnyOrigin](),
            OpaquePointer[MutAnyOrigin](),
        ))
        return this_val
    except:
        throw_js_error(env, "Animal constructor failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# animal_get_name_fn — Animal.prototype.name getter
# ---------------------------------------------------------------------------
fn animal_get_name_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var ptr = unwrap_native[AnimalData](env, info)
        var name_bytes = ptr[].name_ptr.bitcast[Byte]()
        var span = Span[Byte](ptr=name_bytes, length=Int(ptr[].name_len))
        var name = String(from_utf8=span)
        return JsString.create(env, name).value
    except:
        throw_js_error(env, "Animal.name getter failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# animal_speak_fn — Animal.prototype.speak()
# ---------------------------------------------------------------------------
fn animal_speak_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var ptr = unwrap_native[AnimalData](env, info)
        var name_bytes = ptr[].name_ptr.bitcast[Byte]()
        var span = Span[Byte](ptr=name_bytes, length=Int(ptr[].name_len))
        var name = String(from_utf8=span)
        var msg = name + " says hello"
        return JsString.create(env, msg).value
    except:
        throw_js_error(env, "Animal.speak failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# animal_is_animal_fn — Animal.isAnimal(val) static method
# ---------------------------------------------------------------------------
fn animal_is_animal_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var this_val = CbArgs.get_this(env, info)
        var arg0 = CbArgs.get_one(env, info)
        var t = js_typeof(env, arg0)
        if t != NAPI_TYPE_OBJECT and t != NAPI_TYPE_FUNCTION:
            return JsBoolean.create(env, False).value
        var result = JsObject(arg0).instance_of(env, this_val)
        return JsBoolean.create(env, result).value
    except:
        throw_js_error(env, "Animal.isAnimal failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# dog_constructor_fn — Dog(name, breed) constructor
# ---------------------------------------------------------------------------
fn dog_constructor_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var this_val = CbArgs.get_this(env, info)
        var args = CbArgs.get_two(env, info)
        var t0 = js_typeof(env, args[0])
        var t1 = js_typeof(env, args[1])
        if t0 != NAPI_TYPE_STRING or t1 != NAPI_TYPE_STRING:
            throw_js_type_error(env, "Dog constructor requires (name: string, breed: string)")
            return NapiValue()

        var name_str = JsString.from_napi_value(env, args[0])
        var name_len = UInt(len(name_str))
        var name_buf = alloc[Byte](Int(name_len))
        for i in range(Int(name_len)):
            name_buf[i] = name_str.as_bytes()[i]

        var breed_str = JsString.from_napi_value(env, args[1])
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

        check_status(raw_wrap(
            env, this_val,
            data_ptr.bitcast[NoneType](),
            fin_ptr,
            OpaquePointer[MutAnyOrigin](),
            OpaquePointer[MutAnyOrigin](),
        ))
        return this_val
    except:
        throw_js_error(env, "Dog constructor failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# dog_get_breed_fn — Dog.prototype.breed getter
# ---------------------------------------------------------------------------
fn dog_get_breed_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var ptr = unwrap_native[DogData](env, info)
        var breed_bytes = ptr[].breed_ptr.bitcast[Byte]()
        var span = Span[Byte](ptr=breed_bytes, length=Int(ptr[].breed_len))
        var breed = String(from_utf8=span)
        return JsString.create(env, breed).value
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
        var count = CbArgs.argc(env, info)
        if count == 0:
            return JsNumber.create(env, 0.0).value
        var argv = alloc[NapiValue](Int(count))
        CbArgs.get_argv(env, info, count, argv)
        var total: Float64 = 0.0
        for i in range(Int(count)):
            var t = js_typeof(env, argv[i])
            if t != NAPI_TYPE_NUMBER:
                argv.free()
                throw_js_error_dynamic(env, "sumArgs: expected number, got " + js_type_name(t))
                return NapiValue()
            total += JsNumber.from_napi_value(env, argv[i])
        argv.free()
        return JsNumber.create(env, total).value
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
        var cb_ref = inner_callback_fn
        var cb_ptr = UnsafePointer(to=cb_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
        return JsFunction.create(env, "innerCallback", cb_ptr).value
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
        var arg0 = CbArgs.get_one(env, info)
        var n = JsNumber.from_napi_value(env, arg0)
        # Heap-allocate the captured value
        var n_ptr = alloc[Float64](1)
        n_ptr.init_pointee_move(n)
        var cb_ref = inner_adder_fn
        var cb_ptr = UnsafePointer(to=cb_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
        return JsFunction.create_with_data(
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
        return js_get_global(env).value
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
        var obj = JsObject.create(env)
        obj.set_property(env, "value", JsNumber.create(env, 42.0).value)
        var js_ref = JsRef.create(env, obj.value, 1)
        var retrieved = JsObject(js_ref.get(env))
        js_ref.delete(env)
        return retrieved.get_named_property(env, "value")
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
        var obj = JsObject.create(env)
        obj.set_property(env, "answer", JsNumber.create(env, 42.0).value)
        var js_ref = JsRef.create(env, obj.value, 1)
        var val = js_ref.get(env)
        js_ref.delete(env)
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
        var arg0 = CbArgs.get_one(env, info)
        var obj = JsObject.create(env)
        obj.set_property(env, "value", arg0)
        var js_ref = JsRef.create(env, obj.value, 1)
        var retrieved = JsObject(js_ref.get(env))
        js_ref.delete(env)
        return retrieved.get_named_property(env, "value")
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
        var esc = EscapableHandleScope.open(env)
        var obj = JsObject.create(env)
        obj.set_property(env, "created", JsBoolean.create(env, True).value)
        obj.set_property(env, "answer", JsNumber.create(env, 42.0).value)
        var escaped = esc.escape(env, obj.value)
        esc.close(env)
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
        var args = CbArgs.get_two(env, info)
        var ta = js_typeof(env, args[0])
        var tb = js_typeof(env, args[1])
        if ta != NAPI_TYPE_BIGINT or tb != NAPI_TYPE_BIGINT:
            throw_js_error_dynamic(env,
                "addBigInts: expected bigint, got " + js_type_name(ta) + " and " + js_type_name(tb))
            return NapiValue()
        var a = JsBigInt.to_int64(env, args[0])
        var b = JsBigInt.to_int64(env, args[1])
        return JsBigInt.from_int64(env, a + b).value
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
        var arg0 = CbArgs.get_one(env, info)
        var ts = JsNumber.from_napi_value(env, arg0)
        return JsDate.create(env, ts).value
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
        var arg0 = CbArgs.get_one(env, info)
        var d = JsDate(arg0)
        var ts = d.timestamp_ms(env)
        return JsNumber.create(env, ts).value
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
        var arg0 = CbArgs.get_one(env, info)
        return JsSymbol.create(env, arg0).value
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
        var arg0 = CbArgs.get_one(env, info)
        var key = JsString.from_napi_value(env, arg0)
        # node_api_symbol_for takes a C string + length, not a napi_value.
        # We use the Mojo String's unsafe_ptr for the C string.
        var key_ptr: OpaquePointer[ImmutAnyOrigin] = key.unsafe_ptr().bitcast[NoneType]()
        var key_len = UInt(len(key))
        var result = NapiValue()
        from napi.raw import raw_symbol_for
        check_status(raw_symbol_for(env, key_ptr, key_len,
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
        var arg0 = CbArgs.get_one(env, info)
        var t0 = js_typeof(env, arg0)
        if t0 != NAPI_TYPE_OBJECT:
            throw_js_error_dynamic(env, "getKeys: expected object, got " + js_type_name(t0))
            return NapiValue()
        var obj = JsObject(arg0)
        return obj.keys(env)
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
        var args = CbArgs.get_two(env, info)
        var t0 = js_typeof(env, args[0])
        if t0 != NAPI_TYPE_OBJECT:
            throw_js_error_dynamic(env, "hasOwn: expected object, got " + js_type_name(t0))
            return NapiValue()
        var obj = JsObject(args[0])
        var result = obj.has_own(env, args[1])
        return JsBoolean.create(env, result).value
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
        var args = CbArgs.get_two(env, info)
        var t0 = js_typeof(env, args[0])
        if t0 != NAPI_TYPE_OBJECT:
            throw_js_error_dynamic(env, "deleteProperty: expected object, got " + js_type_name(t0))
            return NapiValue()
        var obj = JsObject(args[0])
        _ = obj.delete_prop(env, args[1])
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
        var args = CbArgs.get_two(env, info)
        if not js_is_array(env, args[0]):
            throw_js_error(env, "arrayHasElement: first argument must be an array")
            return NapiValue()
        var arr = JsArray(args[0])
        var index = JsUInt32.from_napi_value(env, args[1])
        var result = arr.has(env, index)
        return JsBoolean.create(env, result).value
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
        var args = CbArgs.get_two(env, info)
        if not js_is_array(env, args[0]):
            throw_js_error(env, "arrayDeleteElement: first argument must be an array")
            return NapiValue()
        var arr = JsArray(args[0])
        var index = JsUInt32.from_napi_value(env, args[1])
        _ = arr.delete_element(env, index)
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
        var arg0 = CbArgs.get_one(env, info)
        var t0 = js_typeof(env, arg0)
        if t0 != NAPI_TYPE_OBJECT:
            throw_js_error_dynamic(env, "getPrototype: expected object, got " + js_type_name(t0))
            return NapiValue()
        var obj = JsObject(arg0)
        return obj.prototype(env)
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
        var args = CbArgs.get_two(env, info)
        var eq = js_strict_equals(env, args[0], args[1])
        return JsBoolean.create(env, eq).value
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
        var args = CbArgs.get_two(env, info)
        var t1 = js_typeof(env, args[1])
        if t1 != NAPI_TYPE_FUNCTION:
            throw_js_error_dynamic(env, "isInstanceOf: second arg must be a constructor, got " + js_type_name(t1))
            return NapiValue()
        var obj = JsObject(args[0])
        var result = obj.instance_of(env, args[1])
        return JsBoolean.create(env, result).value
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
        var arg0 = CbArgs.get_one(env, info)
        var t0 = js_typeof(env, arg0)
        if t0 != NAPI_TYPE_OBJECT:
            throw_js_error_dynamic(env, "freezeObject: expected object, got " + js_type_name(t0))
            return NapiValue()
        var obj = JsObject(arg0)
        obj.freeze(env)
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
        var arg0 = CbArgs.get_one(env, info)
        var t0 = js_typeof(env, arg0)
        if t0 != NAPI_TYPE_OBJECT:
            throw_js_error_dynamic(env, "sealObject: expected object, got " + js_type_name(t0))
            return NapiValue()
        var obj = JsObject(arg0)
        obj.seal(env)
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
        var args = CbArgs.get_two(env, info)
        var count_val = args[0]
        var callback_val = args[1]
        var count = JsNumber.from_napi_value(env, count_val)

        # Create promise
        var p = JsPromise.create(env)

        # Create resource name for diagnostics
        var resource_name = JsString.create_literal(env, "asyncProgress")

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
            env, callback_val, resource_name.value, UInt(0),
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

        check_status(raw_create_async_work(
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
        check_status(raw_queue_async_work(env, work))

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
        var args = CbArgs.get_two(env, info)
        var x = JsNumber.from_napi_value(env, args[0])
        var y = JsNumber.from_napi_value(env, args[1])
        var data_ptr = alloc[ExternalData](1)
        data_ptr.init_pointee_move(ExternalData(x, y))
        var fin_ref = external_finalize
        var fin_ptr = UnsafePointer(to=fin_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
        return JsExternal.create(env, data_ptr.bitcast[NoneType](), fin_ptr).value
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
        var arg0 = CbArgs.get_one(env, info)
        var t = js_typeof(env, arg0)
        if t != NAPI_TYPE_EXTERNAL:
            throw_js_type_error_dynamic(env,
                "getExternalData: expected external, got " + js_type_name(t))
            return NapiValue()
        var data = JsExternal.get_data(env, arg0)
        var ptr = data.bitcast[ExternalData]()
        var obj = JsObject.create(env)
        obj.set_property(env, "x", JsNumber.create(env, ptr[].x).value)
        obj.set_property(env, "y", JsNumber.create(env, ptr[].y).value)
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
        var arg0 = CbArgs.get_one(env, info)
        var t = js_typeof(env, arg0)
        return JsBoolean.create(env, t == NAPI_TYPE_EXTERNAL).value
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
        var arg0 = CbArgs.get_one(env, info)
        return js_coerce_to_bool(env, arg0)
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
        var arg0 = CbArgs.get_one(env, info)
        return js_coerce_to_number(env, arg0)
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
        var arg0 = CbArgs.get_one(env, info)
        return js_coerce_to_string(env, arg0)
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
        var arg0 = CbArgs.get_one(env, info)
        return js_coerce_to_object(env, arg0)
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
        var argc = CbArgs.argc(env, info)
        var argv = alloc[NapiValue](Int(argc))
        CbArgs.get_argv(env, info, argc, argv)
        var obj = argv[0]
        var key = argv[1]
        var val = argv[2]
        JsObject(obj).set(env, key, val)
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
        var args = CbArgs.get_two(env, info)
        var result = JsObject(args[0]).has(env, args[1])
        return JsBoolean.create(env, result).value
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
        var arg0 = CbArgs.get_one(env, info)
        js_throw(env, arg0)
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
        var arg0 = CbArgs.get_one(env, info)
        # Throw the value to set a pending exception
        js_throw(env, arg0)
        # Now catch (clear) the pending exception and return it
        var caught = js_get_and_clear_last_exception(env)
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
        var ver = get_napi_version(env)
        return JsNumber.create_int(env, Int(ver)).value
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
        var ver = get_node_version_ptr(env)
        var obj = JsObject.create(env)
        obj.set_property(env, "major", JsNumber.create_int(env, Int(ver[0])).value)
        obj.set_property(env, "minor", JsNumber.create_int(env, Int(ver[1])).value)
        obj.set_property(env, "patch", JsNumber.create_int(env, Int(ver[2])).value)
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
        var arg0 = CbArgs.get_one(env, info)
        var size = JsNumber.from_napi_value(env, arg0)
        var byte_len = UInt(Int(size))
        # Allocate Mojo-owned memory and fill with incrementing bytes
        var data_ptr = alloc[Byte](Int(byte_len))
        for i in range(Int(byte_len)):
            data_ptr[i] = Byte(i)
        # Get finalizer function pointer
        var fin_ref = external_ab_finalize
        var fin_ptr = UnsafePointer(to=fin_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
        # Create external arraybuffer
        var result = NapiValue()
        check_status(raw_create_external_arraybuffer(env,
            data_ptr.bitcast[NoneType](),
            byte_len,
            fin_ptr,
            OpaquePointer[MutAnyOrigin](),
            UnsafePointer(to=result).bitcast[NoneType]()))
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
        var arg0 = CbArgs.get_one(env, info)
        # Allocate a dummy 1-byte native object (napi_add_finalizer needs non-NULL data)
        var dummy = alloc[Byte](1)
        dummy[0] = Byte(0)
        var fin_ref = noop_finalize
        var fin_ptr = UnsafePointer(to=fin_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
        check_status(raw_add_finalizer(env, arg0,
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
        var arg0 = CbArgs.get_one(env, info)
        var n = JsNumber.from_napi_value(env, arg0)
        var data_ptr = alloc[Float64](1)
        data_ptr.init_pointee_move(n)
        var fin_ref = instance_data_finalize
        var fin_ptr = UnsafePointer(to=fin_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
        check_status(raw_set_instance_data(env,
            data_ptr.bitcast[NoneType](),
            fin_ptr,
            OpaquePointer[MutAnyOrigin]()))
        return JsUndefined.create(env).value
    except:
        throw_js_error(env, "setInstanceData failed")
        return NapiValue()

## getInstanceData() — retrieves the Float64 stored as instance data
fn get_instance_data_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var data = OpaquePointer[MutAnyOrigin]()
        check_status(raw_get_instance_data(env,
            UnsafePointer(to=data).bitcast[NoneType]()))
        if Int(data) == 0:
            return JsNull.create(env).value
        var ptr = data.bitcast[Float64]()
        return JsNumber.create(env, ptr[]).value
    except:
        throw_js_error(env, "getInstanceData failed")
        return NapiValue()

## No-op cleanup hook callback — fn(void*)
fn cleanup_hook_noop(arg: OpaquePointer[MutAnyOrigin]):
    pass

## addCleanupHook() — registers a no-op cleanup hook with a unique arg, returns true
fn add_cleanup_hook_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var hook_ref = cleanup_hook_noop
        var hook_ptr = UnsafePointer(to=hook_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
        # Allocate a unique 1-byte arg to make each (fun, arg) pair unique
        var arg_ptr = alloc[Byte](1)
        arg_ptr[0] = Byte(0)
        check_status(raw_add_env_cleanup_hook(env, hook_ptr, arg_ptr.bitcast[NoneType]()))
        return JsBoolean.create(env, True).value
    except:
        throw_js_error(env, "addCleanupHook failed")
        return NapiValue()

## removeCleanupHook() — unregisters the most recently added cleanup hook
## Note: we can't easily track the arg, so this is a best-effort test helper.
## In practice, addCleanupHook allocates unique args, making removal hard without tracking.
## For testing, we register and immediately remove with the same arg.
fn remove_cleanup_hook_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var hook_ref = cleanup_hook_noop
        var hook_ptr = UnsafePointer(to=hook_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
        # Register with a known arg, then immediately remove it
        var arg_ptr = alloc[Byte](1)
        arg_ptr[0] = Byte(0)
        check_status(raw_add_env_cleanup_hook(env, hook_ptr, arg_ptr.bitcast[NoneType]()))
        check_status(raw_remove_env_cleanup_hook(env, hook_ptr, arg_ptr.bitcast[NoneType]()))
        arg_ptr.free()
        return JsBoolean.create(env, True).value
    except:
        throw_js_error(env, "removeCleanupHook failed")
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
        var p = JsPromise.create(env)
        var data_ptr = alloc[CancelAsyncData](1)
        data_ptr.init_pointee_move(CancelAsyncData(p.deferred))

        var exec_ref = cancel_async_execute
        var complete_ref = cancel_async_complete
        var exec_ptr = UnsafePointer(to=exec_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
        var complete_ptr = UnsafePointer(to=complete_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]

        var resource_name = JsString.create_literal(env, "cancelTest")
        var work = NapiAsyncWork()
        var work_out_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=work).bitcast[NoneType]()
        check_status(raw_create_async_work(env,
            NapiValue(), resource_name.value,
            exec_ptr, complete_ptr,
            data_ptr.bitcast[NoneType](),
            work_out_ptr))
        data_ptr[].work = work

        check_status(raw_queue_async_work(env, work))
        # Immediately try to cancel
        _ = raw_cancel_async_work(env, work)

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
        var args = CbArgs.get_two(env, info)
        var sign_bit = Int32(JsNumber.from_napi_value(env, args[0]))
        var arr_val = args[1]
        var arr = JsArray(arr_val)
        var arr_len = arr.length(env)
        var words_ptr = alloc[UInt64](Int(arr_len))
        for i in range(Int(arr_len)):
            var elem = arr.get(env, UInt32(i))
            var num = JsNumber.from_napi_value(env, elem)
            words_ptr[i] = UInt64(num)
        var result = JsBigInt.from_words(env, sign_bit, words_ptr.bitcast[NoneType](), UInt(arr_len))
        words_ptr.free()
        return result.value
    except:
        throw_js_error(env, "bigIntFromWords failed")
        return NapiValue()

## bigIntToWords(bi) — extract sign and UInt64 words from a BigInt
fn bigint_to_words_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var arg0 = CbArgs.get_one(env, info)
        # Allocate an initial buffer (16 words = 128 bytes, handles up to 1024-bit BigInts)
        var sign: Int32 = 0
        var count: UInt = 16
        var words_ptr = alloc[UInt64](16)
        check_status(raw_get_value_bigint_words(env, arg0,
            UnsafePointer(to=sign).bitcast[NoneType](),
            UnsafePointer(to=count).bitcast[NoneType](),
            words_ptr.bitcast[NoneType]()))
        # Build result object {sign, words}
        var obj = JsObject.create(env)
        obj.set_property(env, "sign", JsNumber.create_int(env, Int(sign)).value)
        var arr = JsArray.create_with_length(env, count)
        for i in range(Int(count)):
            var word_val = JsNumber.create(env, Float64(words_ptr[i]))
            arr.set(env, UInt32(i), word_val.value)
        obj.set_property(env, "words", arr.value)
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
        var argc = CbArgs.argc(env, info)
        if argc < 3:
            throw_js_type_error(env, "createDataView requires 3 arguments")
            return NapiValue()
        var argv_ptr = alloc[NapiValue](Int(argc))
        CbArgs.get_argv(env, info, argc, argv_ptr)
        var ab = argv_ptr[0]
        var byte_offset = JsNumber.from_napi_value(env, argv_ptr[1])
        var byte_length = JsNumber.from_napi_value(env, argv_ptr[2])
        argv_ptr.free()
        var dv = JsDataView.create(env, UInt(Int(byte_length)), ab, UInt(Int(byte_offset)))
        return dv.value
    except:
        throw_js_error(env, "createDataView failed")
        return NapiValue()

## getDataViewInfo(dv) — returns {byteLength, byteOffset}
fn get_dataview_info_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var arg0 = CbArgs.get_one(env, info)
        var dv = JsDataView(arg0)
        var bl = dv.byte_length(env)
        var bo = dv.byte_offset(env)
        var obj = JsObject.create(env)
        obj.set_property(env, "byteLength", JsNumber.create_int(env, Int(bl)).value)
        obj.set_property(env, "byteOffset", JsNumber.create_int(env, Int(bo)).value)
        return obj.value
    except:
        throw_js_error(env, "getDataViewInfo failed")
        return NapiValue()

## isDataView(val) — returns true if val is a DataView
fn is_dataview_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var arg0 = CbArgs.get_one(env, info)
        var result = JsDataView.is_dataview(env, arg0)
        return JsBoolean.create(env, result).value
    except:
        throw_js_error(env, "isDataView failed")
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

    try:
        var m = ModuleBuilder(env, exports)

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

        # Counter class
        var counter = m.class_def("Counter", fn_ptr(counter_constructor_ref))
        counter.instance_method("increment", fn_ptr(counter_increment_ref))
        counter.instance_method("reset", fn_ptr(counter_reset_ref))
        counter.getter_setter("value", fn_ptr(counter_get_value_ref), fn_ptr(counter_set_value_ref))
        counter.static_method("isCounter", fn_ptr(counter_is_counter_ref))
        counter.static_method("fromValue", fn_ptr(counter_from_value_ref))

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
