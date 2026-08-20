## src/napi/framework/threadsafe_function.mojo — ergonomic wrapper for thread-safe functions
##
## ThreadsafeFunction enables calling JavaScript functions from Mojo worker threads.
## The key N-API primitive for streaming, progress reporting, and event-driven patterns.
##
##   var tsfn = ThreadsafeFunction.create(b, env, js_func, resource_name, 0, call_js_ptr, ...)
##   # on worker thread (cached pointer — no loader lock):
##   tsfn.call_blocking(b, data_ptr)
##   # when done (on main thread):
##   tsfn.release(b)

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
    ##
    ## The cached-bindings pointer is registered as the TSFN context. N-API
    ## hands that context to call_js_cb as its third parameter AND to
    ## finalize_cb as `finalize_hint`, so both callbacks recover cached
    ## bindings via bindings_from_context().
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
        var tsfn = NapiThreadsafeFunction(unsafe_from_address=Int(0))
        var null_resource = NapiValue(unsafe_from_address=Int(0))
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
                # context = the cached-bindings pointer. N-API passes it to
                # call_js_cb (3rd param) and to finalize_cb (finalize_hint),
                # so both can run on cached pointers via
                # bindings_from_context() — no per-call dlsym.
                b.unsafe_bitcast[NoneType](),
                call_js_cb,
                Pointer(to=tsfn).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        return ThreadsafeFunction(tsfn)

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

    def acquire(self, b: Bindings) raises:
        check_status(raw_acquire_threadsafe_function(b, self.tsfn))

    def release(self, b: Bindings) raises:
        check_status(
            raw_release_threadsafe_function(b, self.tsfn, NAPI_TSFN_RELEASE)
        )

    def abort(self, b: Bindings) raises:
        check_status(
            raw_release_threadsafe_function(b, self.tsfn, NAPI_TSFN_ABORT)
        )
