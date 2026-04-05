## src/napi/framework/threadsafe_function.mojo — ergonomic wrapper for thread-safe functions
##
## ThreadsafeFunction enables calling JavaScript functions from Mojo worker threads.
## The key N-API primitive for streaming, progress reporting, and event-driven patterns.
##
##   var tsfn = ThreadsafeFunction.create(env, js_func, resource_name, 0, call_js_ptr)
##   # on worker thread:
##   tsfn.call_blocking(data_ptr)
##   # when done (on main thread):
##   tsfn.release()

from napi.types import (
    NapiEnv,
    NapiValue,
    NapiThreadsafeFunction,
    NAPI_TSFN_BLOCKING,
    NAPI_TSFN_NONBLOCKING,
    NAPI_TSFN_RELEASE,
    NAPI_TSFN_ABORT,
)
from napi.bindings import Bindings
from napi.raw import (
    raw_create_threadsafe_function,
    raw_call_threadsafe_function,
    raw_acquire_threadsafe_function,
    raw_release_threadsafe_function,
)
from napi.error import check_status


struct ThreadsafeFunction:
    var tsfn: NapiThreadsafeFunction

    def __init__(out self, tsfn: NapiThreadsafeFunction):
        self.tsfn = tsfn

    ## create — create a thread-safe function wrapper
    ##
    ## `func`:              the JS function to call (passed to call_js_cb as js_callback)
    ## `resource_name_val`: napi_value string for async diagnostics
    ## `max_queue_size`:    0 = unlimited queue
    ## `call_js_cb`:        fn(env, js_callback, context, data) — invoked on main thread
    ## `finalize_data`:     data pointer passed to finalize_cb (NULL if none)
    ## `finalize_cb`:       cleanup callback — fires AFTER all call_js_cb invocations (NULL if none)
    @staticmethod
    def create(
        env: NapiEnv,
        func: NapiValue,
        resource_name_val: NapiValue,
        max_queue_size: UInt,
        call_js_cb: OpaquePointer[MutAnyOrigin],
        finalize_data: OpaquePointer[MutAnyOrigin],
        finalize_cb: OpaquePointer[MutAnyOrigin],
    ) raises -> ThreadsafeFunction:
        var tsfn = NapiThreadsafeFunction()
        var null_resource = NapiValue()
        var null_ptr = OpaquePointer[MutAnyOrigin]()
        check_status(
            raw_create_threadsafe_function(
                env,
                func,
                null_resource,  # async_resource (NULL)
                resource_name_val,
                max_queue_size,
                UInt(1),  # initial_thread_count
                finalize_data,
                finalize_cb,
                null_ptr,  # context
                call_js_cb,
                UnsafePointer(to=tsfn).bitcast[NoneType](),
            )
        )
        return ThreadsafeFunction(tsfn)

    @staticmethod
    def create(
        b: Bindings,
        env: NapiEnv,
        func: NapiValue,
        resource_name_val: NapiValue,
        max_queue_size: UInt,
        call_js_cb: OpaquePointer[MutAnyOrigin],
        finalize_data: OpaquePointer[MutAnyOrigin],
        finalize_cb: OpaquePointer[MutAnyOrigin],
    ) raises -> ThreadsafeFunction:
        var tsfn = NapiThreadsafeFunction()
        var null_resource = NapiValue()
        var null_ptr = OpaquePointer[MutAnyOrigin]()
        check_status(
            raw_create_threadsafe_function(
                b,
                env,
                func,
                null_resource,  # async_resource (NULL)
                resource_name_val,
                max_queue_size,
                UInt(1),  # initial_thread_count
                finalize_data,
                finalize_cb,
                null_ptr,  # context
                call_js_cb,
                UnsafePointer(to=tsfn).bitcast[NoneType](),
            )
        )
        return ThreadsafeFunction(tsfn)

    ## call_blocking — queue data, block if queue is full
    ##
    ## Can be called from ANY thread. The data pointer is passed to call_js_cb.
    def call_blocking(self, data: OpaquePointer[MutAnyOrigin]) raises:
        check_status(
            raw_call_threadsafe_function(
                self.tsfn,
                data,
                NAPI_TSFN_BLOCKING,
            )
        )

    def call_blocking(
        self, b: Bindings, data: OpaquePointer[MutAnyOrigin]
    ) raises:
        check_status(
            raw_call_threadsafe_function(
                b,
                self.tsfn,
                data,
                NAPI_TSFN_BLOCKING,
            )
        )

    ## call_nonblocking — queue data, return napi_queue_full if queue is full
    def call_nonblocking(self, data: OpaquePointer[MutAnyOrigin]) raises:
        check_status(
            raw_call_threadsafe_function(
                self.tsfn,
                data,
                NAPI_TSFN_NONBLOCKING,
            )
        )

    def call_nonblocking(
        self, b: Bindings, data: OpaquePointer[MutAnyOrigin]
    ) raises:
        check_status(
            raw_call_threadsafe_function(
                b,
                self.tsfn,
                data,
                NAPI_TSFN_NONBLOCKING,
            )
        )

    ## acquire — increment the TSFN thread reference count
    def acquire(self) raises:
        check_status(raw_acquire_threadsafe_function(self.tsfn))

    def acquire(self, b: Bindings) raises:
        check_status(raw_acquire_threadsafe_function(b, self.tsfn))

    ## release — decrement the thread reference count (normal release)
    ##
    ## When the count reaches 0, the TSFN is destroyed.
    def release(self) raises:
        check_status(
            raw_release_threadsafe_function(self.tsfn, NAPI_TSFN_RELEASE)
        )

    def release(self, b: Bindings) raises:
        check_status(
            raw_release_threadsafe_function(b, self.tsfn, NAPI_TSFN_RELEASE)
        )

    ## abort — immediately close the TSFN, discard pending items
    def abort(self) raises:
        check_status(
            raw_release_threadsafe_function(self.tsfn, NAPI_TSFN_ABORT)
        )

    def abort(self, b: Bindings) raises:
        check_status(
            raw_release_threadsafe_function(b, self.tsfn, NAPI_TSFN_ABORT)
        )
