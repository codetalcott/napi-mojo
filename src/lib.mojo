## src/lib.mojo — napi-mojo module entry point
##
## Exports: hello, createObject, makeGreeting, greet, add, isPositive,
##          getNull, getUndefined, sumArray, getProperty, callFunction, mapArray,
##          resolveWith, rejectWith
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
from napi.types import NapiEnv, NapiValue, NapiStatus, NapiDeferred, NapiAsyncWork, NAPI_TYPE_STRING, NAPI_TYPE_OBJECT, NAPI_TYPE_FUNCTION, NAPI_OK
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
from napi.framework.js_value import js_typeof, js_type_name, js_is_array
from napi.framework.handle_scope import HandleScope
from napi.error import throw_js_error, throw_js_error_dynamic, check_status

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
    except:
        pass

    return exports
