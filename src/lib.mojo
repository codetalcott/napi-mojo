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
##          Counter (class: constructor, increment, reset, value getter/setter),
##          sumArgs, createCallback, createAdder, getGlobal
##
## Module structure:
##   src/napi/types.mojo                  — NapiEnv, NapiValue, NapiStatus, NapiDeferred, etc.
##   src/napi/raw.mojo                    — sole OwnedDLHandle user; raw_* bindings
##   src/napi/error.mojo                  — check_status(), throw_js_error()
##   src/napi/module.mojo                 — define_property(), register_method()
##   src/napi/framework/js_string.mojo    — JsString.create(), create_literal(), from_napi_value()
##   src/napi/framework/js_object.mojo    — JsObject.create(), set_property(), get(), get_property()
##   src/napi/framework/js_number.mojo    — JsNumber.create(), from_napi_value()
##   src/napi/framework/js_boolean.mojo   — JsBoolean.create(), from_napi_value()
##   src/napi/framework/args.mojo         — CbArgs.get_one(), get_two()
##   src/napi/framework/js_value.mojo     — js_typeof(), js_type_name()
##   src/napi/framework/js_null.mojo      — JsNull.create()
##   src/napi/framework/js_undefined.mojo — JsUndefined.create()
##   src/napi/framework/js_array.mojo     — JsArray.create_with_length(), set(), get(), length()
##   src/napi/framework/js_promise.mojo   — JsPromise.create(), resolve(), reject()
##
## This file contains only:
##   1. Imports from the napi/ package
##   2. The napi_callback implementations
##   3. The @export entry point (register_module)

from memory import alloc
from napi.types import NapiEnv, NapiValue, NapiStatus, NapiDeferred, NapiAsyncWork, NAPI_TYPE_STRING, NAPI_TYPE_NUMBER, NAPI_TYPE_OBJECT, NAPI_TYPE_FUNCTION, NAPI_TYPE_BIGINT, NAPI_OK
from napi.raw import raw_create_error, raw_resolve_deferred, raw_reject_deferred, raw_create_async_work, raw_queue_async_work, raw_delete_async_work
from napi.module import register_method
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
from napi.framework.js_value import js_typeof, js_type_name, js_is_array, js_get_global
from napi.framework.handle_scope import HandleScope
from napi.framework.js_int32 import JsInt32
from napi.framework.js_uint32 import JsUInt32
from napi.framework.js_arraybuffer import JsArrayBuffer
from napi.framework.js_buffer import JsBuffer
from napi.framework.js_typedarray import JsTypedArray
from napi.framework.js_class import define_class, register_instance_method, register_getter_setter
from napi.framework.js_ref import JsRef
from napi.framework.escapable_handle_scope import EscapableHandleScope
from napi.framework.js_bigint import JsBigInt
from napi.framework.js_date import JsDate
from napi.framework.js_symbol import JsSymbol
from napi.raw import raw_wrap, raw_unwrap
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
        var this_val = CbArgs.get_this(env, info)
        var data = OpaquePointer[MutAnyOrigin]()
        check_status(raw_unwrap(env, this_val,
            UnsafePointer(to=data).bitcast[NoneType]()))
        var ptr = data.bitcast[CounterData]()
        return JsNumber.create(env, ptr[].count).value
    except:
        throw_js_error(env, "Counter.value getter failed")
        return NapiValue()

# ---------------------------------------------------------------------------
# counter_set_value_fn — Counter.prototype.value setter
# ---------------------------------------------------------------------------
fn counter_set_value_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var result = CbArgs.get_this_and_one(env, info)
        var this_val = result[0]
        var arg0 = result[1]
        var t = js_typeof(env, arg0)
        if t != NAPI_TYPE_NUMBER:
            throw_js_type_error(env, "Counter.value setter requires a number")
            return NapiValue()
        var new_val = JsNumber.from_napi_value(env, arg0)
        var data = OpaquePointer[MutAnyOrigin]()
        check_status(raw_unwrap(env, this_val,
            UnsafePointer(to=data).bitcast[NoneType]()))
        var ptr = data.bitcast[CounterData]()
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
        var this_val = CbArgs.get_this(env, info)
        var data = OpaquePointer[MutAnyOrigin]()
        check_status(raw_unwrap(env, this_val,
            UnsafePointer(to=data).bitcast[NoneType]()))
        var ptr = data.bitcast[CounterData]()
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
        var this_val = CbArgs.get_this(env, info)
        var data = OpaquePointer[MutAnyOrigin]()
        check_status(raw_unwrap(env, this_val,
            UnsafePointer(to=data).bitcast[NoneType]()))
        var ptr = data.bitcast[CounterData]()
        ptr[].count = ptr[].initial
        return JsUndefined.create(env).value
    except:
        throw_js_error(env, "Counter.reset failed")
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
        return result
    except:
        throw_js_error(env, "symbolFor requires one string argument")
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

    try:
        register_method(env, exports, "hello",
            UnsafePointer(to=hello_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "createObject",
            UnsafePointer(to=create_object_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "makeGreeting",
            UnsafePointer(to=make_greeting_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "greet",
            UnsafePointer(to=greet_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "add",
            UnsafePointer(to=add_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "isPositive",
            UnsafePointer(to=is_positive_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "getNull",
            UnsafePointer(to=get_null_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "getUndefined",
            UnsafePointer(to=get_undefined_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "sumArray",
            UnsafePointer(to=sum_array_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "getProperty",
            UnsafePointer(to=get_property_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "callFunction",
            UnsafePointer(to=call_function_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "mapArray",
            UnsafePointer(to=map_array_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "resolveWith",
            UnsafePointer(to=resolve_with_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "rejectWith",
            UnsafePointer(to=reject_with_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "asyncDouble",
            UnsafePointer(to=async_double_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "addInts",
            UnsafePointer(to=add_ints_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "bitwiseOr",
            UnsafePointer(to=bitwise_or_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "throwTypeError",
            UnsafePointer(to=throw_type_error_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "throwRangeError",
            UnsafePointer(to=throw_range_error_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "addIntsStrict",
            UnsafePointer(to=add_ints_strict_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "createArrayBuffer",
            UnsafePointer(to=create_arraybuffer_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "arrayBufferLength",
            UnsafePointer(to=arraybuffer_length_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "sumBuffer",
            UnsafePointer(to=sum_buffer_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "createBuffer",
            UnsafePointer(to=create_buffer_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "doubleFloat64Array",
            UnsafePointer(to=double_float64_array_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])

        register_method(env, exports, "sumArgs",
            UnsafePointer(to=sum_args_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "createCallback",
            UnsafePointer(to=create_callback_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "createAdder",
            UnsafePointer(to=create_adder_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "getGlobal",
            UnsafePointer(to=get_global_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "testRef",
            UnsafePointer(to=test_ref_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "testRefObject",
            UnsafePointer(to=test_ref_object_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "testRefString",
            UnsafePointer(to=test_ref_string_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "buildInScope",
            UnsafePointer(to=build_in_scope_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "addBigInts",
            UnsafePointer(to=add_bigints_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "createDate",
            UnsafePointer(to=create_date_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "getDateValue",
            UnsafePointer(to=get_date_value_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "createSymbol",
            UnsafePointer(to=create_symbol_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_method(env, exports, "symbolFor",
            UnsafePointer(to=symbol_for_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])

        # Counter class registration
        var ctor_ptr = UnsafePointer(to=counter_constructor_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
        var ctor_val = define_class(env, "Counter", ctor_ptr)
        register_instance_method(env, ctor_val, "increment",
            UnsafePointer(to=counter_increment_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_instance_method(env, ctor_val, "reset",
            UnsafePointer(to=counter_reset_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        register_getter_setter(env, ctor_val, "value",
            UnsafePointer(to=counter_get_value_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[],
            UnsafePointer(to=counter_set_value_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
        JsObject(exports).set_property(env, "Counter", ctor_val)
    except:
        pass

    return exports
