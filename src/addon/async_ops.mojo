## src/addon/async_ops.mojo — all async work and TSFN callbacks
##
## Covers: resolveWith, rejectWith, asyncDouble, asyncTriple,
##         asyncProgress (with TSFN), cancelAsyncWork

from memory import alloc
from napi.types import NapiEnv, NapiValue, NapiStatus, NapiDeferred, NapiAsyncWork, NapiThreadsafeFunction, NAPI_OK, NAPI_TSFN_BLOCKING, NAPI_TSFN_RELEASE
from napi.bindings import Bindings
from napi.error import throw_js_error, check_status
from napi.raw import raw_create_error, raw_resolve_deferred, raw_reject_deferred, raw_create_async_work, raw_queue_async_work, raw_delete_async_work, raw_call_threadsafe_function, raw_release_threadsafe_function, raw_cancel_async_work
from napi.framework.js_string import JsString
from napi.framework.js_number import JsNumber
from napi.framework.js_function import JsFunction
from napi.framework.js_promise import JsPromise
from napi.framework.threadsafe_function import ThreadsafeFunction
from napi.framework.args import CbArgs
from napi.framework.async_work import AsyncWork
from napi.framework.register import fn_ptr, ModuleBuilder

# ---------------------------------------------------------------------------
# resolveWith / rejectWith
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

fn reject_with_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
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
# asyncDouble — worker-thread computation, AsyncWork helper
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
# asyncTriple — uses AsyncWork helper
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
# asyncProgress — TSFN-based progress callbacks + promise resolution
# ---------------------------------------------------------------------------

struct AsyncProgressData(Movable):
    var deferred: NapiDeferred
    var work: NapiAsyncWork
    var tsfn: NapiThreadsafeFunction
    var count: Int
    var status: NapiStatus

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

fn progress_call_js_cb(
    env: NapiEnv,
    js_callback: NapiValue,
    context: OpaquePointer[MutAnyOrigin],
    data: OpaquePointer[MutAnyOrigin],
):
    var val_ptr = data.bitcast[Float64]()
    var value = val_ptr[]
    val_ptr.destroy_pointee()
    val_ptr.free()
    if not env:
        return
    if not js_callback:
        return
    try:
        var js_val = JsNumber.create(env, value)
        _ = JsFunction(js_callback).call1(env, js_val.value)
    except:
        pass

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

fn async_progress_complete(env: NapiEnv, status: NapiStatus, data: OpaquePointer[MutAnyOrigin]):
    var ptr = data.bitcast[AsyncProgressData]()
    ptr[].status = status
    try:
        _ = raw_release_threadsafe_function(ptr[].tsfn, NAPI_TSFN_RELEASE)
    except:
        pass

fn async_progress_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var count_val = args[0]
        var callback_val = args[1]
        var count = JsNumber.from_napi_value(b, env, count_val)
        var p = JsPromise.create(b, env)
        var resource_name = JsString.create_literal(b, env, "asyncProgress")
        var call_js_ref = progress_call_js_cb
        var call_js_ptr = UnsafePointer(to=call_js_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
        var finalize_ref = progress_finalize_cb
        var finalize_ptr = UnsafePointer(to=finalize_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
        var data_ptr = alloc[AsyncProgressData](1)
        data_ptr.init_pointee_move(AsyncProgressData(
            p.deferred, NapiAsyncWork(), NapiThreadsafeFunction(), Int(count)
        ))
        var data_opaque: OpaquePointer[MutAnyOrigin] = data_ptr.bitcast[NoneType]()
        var tsfn = ThreadsafeFunction.create(
            b, env, callback_val, resource_name.value, UInt(0),
            call_js_ptr, data_opaque, finalize_ptr)
        data_ptr[].tsfn = tsfn.tsfn
        var exec_ref = async_progress_execute
        var comp_ref = async_progress_complete
        var exec_ptr = UnsafePointer(to=exec_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
        var comp_ptr = UnsafePointer(to=comp_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
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
        data_ptr[].work = work
        check_status(raw_queue_async_work(b, env, work))
        return p.value
    except:
        throw_js_error(env, "asyncProgress requires (count, callback)")
        return NapiValue()

# ---------------------------------------------------------------------------
# cancelAsyncWork — queues then immediately cancels async work
# ---------------------------------------------------------------------------

struct CancelAsyncData(Movable):
    var deferred: NapiDeferred
    var work: NapiAsyncWork

    fn __init__(out self, deferred: NapiDeferred):
        self.deferred = deferred
        self.work = NapiAsyncWork()

    fn __moveinit__(out self, deinit take: Self):
        self.deferred = take.deferred
        self.work = take.work

fn cancel_async_execute(env: NapiEnv, data: OpaquePointer[MutAnyOrigin]):
    pass

fn cancel_async_complete(env: NapiEnv, status: NapiStatus, data: OpaquePointer[MutAnyOrigin]):
    var ptr = data.bitcast[CancelAsyncData]()
    try:
        _ = raw_delete_async_work(env, ptr[].work)
        if status == NAPI_OK:
            var result_val = JsString.create_literal(env, "completed")
            _ = raw_resolve_deferred(env, ptr[].deferred, result_val.value)
        else:
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
        _ = raw_cancel_async_work(b, env, work)
        return p.value
    except:
        throw_js_error(env, "cancelAsyncWork failed")
        return NapiValue()

fn register_async(mut m: ModuleBuilder) raises:
    var resolve_with_ref = resolve_with_fn
    var reject_with_ref = reject_with_fn
    var async_double_ref = async_double_fn
    var async_triple_ref = async_triple_fn
    var async_progress_ref = async_progress_fn
    var cancel_async_work_ref = cancel_async_work_fn
    m.method("resolveWith", fn_ptr(resolve_with_ref))
    m.method("rejectWith", fn_ptr(reject_with_ref))
    m.method("asyncDouble", fn_ptr(async_double_ref))
    m.method("asyncTriple", fn_ptr(async_triple_ref))
    m.method("asyncProgress", fn_ptr(async_progress_ref))
    m.method("cancelAsyncWork", fn_ptr(cancel_async_work_ref))
