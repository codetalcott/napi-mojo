## src/napi/framework/async_work.mojo — ergonomic async work helpers
##
## Centralizes the promise + async work creation ceremony.
##
## Usage (entry-point callback):
##   var data_ptr = alloc[MyData](1)
##   data_ptr.init_pointee_move(MyData(args))
##   var exec_ref = my_execute
##   var comp_ref = my_complete
##   var aw = AsyncWork.queue(env, "name", data_ptr.bitcast[NoneType](),
##       fn_ptr(exec_ref), fn_ptr(comp_ref))
##   data_ptr[].deferred = aw.deferred
##   data_ptr[].work = aw.work
##   return aw.value
##
## Usage (complete callback):
##   AsyncWork.resolve(env, ptr[].deferred, ptr[].work, result_val)
##   ptr.destroy_pointee()
##   ptr.free()

from napi.types import (
    NapiEnv,
    NapiValue,
    NapiStatus,
    NapiDeferred,
    NapiAsyncWork,
)
from napi.bindings import Bindings
from napi.raw import (
    raw_create_async_work,
    raw_queue_async_work,
    raw_delete_async_work,
    raw_resolve_deferred,
    raw_reject_deferred,
    raw_create_error,
)
from napi.error import check_status
from napi.framework.js_promise import JsPromise
from napi.framework.js_string import JsString


## AsyncWorkResult — returned by AsyncWork.queue()
##
## Contains the promise value (to return to JS), the deferred handle
## (to store in user's data struct), and the work handle (same).
struct AsyncWorkResult:
    var value: NapiValue
    var deferred: NapiDeferred
    var work: NapiAsyncWork

    def __init__(
        out self, value: NapiValue, deferred: NapiDeferred, work: NapiAsyncWork
    ):
        self.value = value
        self.deferred = deferred
        self.work = work


struct AsyncWork:
    ## queue — create promise, create async work, queue it
    ##
    ## The caller must:
    ##   1. Heap-allocate their data struct with alloc[T](1) + init_pointee_move()
    ##   2. Pass data_ptr.bitcast[NoneType]() as data_opaque
    ##   3. After this call, patch deferred and work into their data struct
    ##
    ## Returns AsyncWorkResult with {value, deferred, work}.
    @staticmethod
    def queue(
        env: NapiEnv,
        name: StringLiteral,
        data_opaque: OpaquePointer[MutAnyOrigin],
        execute_ptr: OpaquePointer[MutAnyOrigin],
        complete_ptr: OpaquePointer[MutAnyOrigin],
    ) raises -> AsyncWorkResult:
        var p = JsPromise.create(env)
        var resource_name = JsString.create_literal(env, name)

        var work = NapiAsyncWork()
        var work_out: OpaquePointer[MutAnyOrigin] = UnsafePointer(
            to=work
        ).bitcast[NoneType]()
        var null_resource = NapiValue()

        check_status(
            raw_create_async_work(
                env,
                null_resource,
                resource_name.value,
                execute_ptr,
                complete_ptr,
                data_opaque,
                work_out,
            )
        )

        check_status(raw_queue_async_work(env, work))
        return AsyncWorkResult(p.value, p.deferred, work)

    @staticmethod
    def queue(
        b: Bindings,
        env: NapiEnv,
        name: StringLiteral,
        data_opaque: OpaquePointer[MutAnyOrigin],
        execute_ptr: OpaquePointer[MutAnyOrigin],
        complete_ptr: OpaquePointer[MutAnyOrigin],
    ) raises -> AsyncWorkResult:
        var p = JsPromise.create(b, env)
        var resource_name = JsString.create_literal(b, env, name)

        var work = NapiAsyncWork()
        var work_out: OpaquePointer[MutAnyOrigin] = UnsafePointer(
            to=work
        ).bitcast[NoneType]()
        var null_resource = NapiValue()

        check_status(
            raw_create_async_work(
                b,
                env,
                null_resource,
                resource_name.value,
                execute_ptr,
                complete_ptr,
                data_opaque,
                work_out,
            )
        )

        check_status(raw_queue_async_work(b, env, work))
        return AsyncWorkResult(p.value, p.deferred, work)

    ## resolve — resolve deferred + delete async work
    @staticmethod
    def resolve(
        env: NapiEnv,
        deferred: NapiDeferred,
        work: NapiAsyncWork,
        result: NapiValue,
    ) raises:
        check_status(raw_resolve_deferred(env, deferred, result))
        check_status(raw_delete_async_work(env, work))

    @staticmethod
    def resolve(
        b: Bindings,
        env: NapiEnv,
        deferred: NapiDeferred,
        work: NapiAsyncWork,
        result: NapiValue,
    ) raises:
        check_status(raw_resolve_deferred(b, env, deferred, result))
        check_status(raw_delete_async_work(b, env, work))

    ## reject_with_error — create Error, reject deferred, delete async work
    @staticmethod
    def reject_with_error(
        env: NapiEnv,
        deferred: NapiDeferred,
        work: NapiAsyncWork,
        msg: StringLiteral,
    ) raises:
        var msg_val = JsString.create_literal(env, msg)
        var null_code = NapiValue()
        var error_val = NapiValue()
        var error_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
            to=error_val
        ).bitcast[NoneType]()
        check_status(raw_create_error(env, null_code, msg_val.value, error_ptr))
        check_status(raw_reject_deferred(env, deferred, error_val))
        check_status(raw_delete_async_work(env, work))

    @staticmethod
    def reject_with_error(
        b: Bindings,
        env: NapiEnv,
        deferred: NapiDeferred,
        work: NapiAsyncWork,
        msg: StringLiteral,
    ) raises:
        var msg_val = JsString.create_literal(b, env, msg)
        var null_code = NapiValue()
        var error_val = NapiValue()
        var error_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
            to=error_val
        ).bitcast[NoneType]()
        check_status(
            raw_create_error(b, env, null_code, msg_val.value, error_ptr)
        )
        check_status(raw_reject_deferred(b, env, deferred, error_val))
        check_status(raw_delete_async_work(b, env, work))

    ## reject_with_error_dynamic — reject with a computed String message
    ##
    ## Use when the error message is known only at runtime (e.g., includes
    ## a file path or status code). Mirrors throw_js_error_dynamic pattern:
    ## msg_copy owns the bytes; explicit transfer keeps them alive past the
    ## napi_create_string_utf8 call inside JsString.create.
    @staticmethod
    def reject_with_error_dynamic(
        env: NapiEnv, deferred: NapiDeferred, work: NapiAsyncWork, msg: String
    ) raises:
        var msg_copy = msg
        var msg_val = JsString.create(env, msg_copy)
        _ = msg_copy^
        var null_code = NapiValue()
        var error_val = NapiValue()
        var error_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
            to=error_val
        ).bitcast[NoneType]()
        check_status(raw_create_error(env, null_code, msg_val.value, error_ptr))
        check_status(raw_reject_deferred(env, deferred, error_val))
        check_status(raw_delete_async_work(env, work))

    @staticmethod
    def reject_with_error_dynamic(
        b: Bindings,
        env: NapiEnv,
        deferred: NapiDeferred,
        work: NapiAsyncWork,
        msg: String,
    ) raises:
        var msg_copy = msg
        var msg_val = JsString.create(b, env, msg_copy)
        _ = msg_copy^
        var null_code = NapiValue()
        var error_val = NapiValue()
        var error_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
            to=error_val
        ).bitcast[NoneType]()
        check_status(
            raw_create_error(b, env, null_code, msg_val.value, error_ptr)
        )
        check_status(raw_reject_deferred(b, env, deferred, error_val))
        check_status(raw_delete_async_work(b, env, work))
