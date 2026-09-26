## src/napi/framework/async_work.mojo — ergonomic async work helpers
##
## Centralizes the promise + async work creation ceremony.
##
## Usage (entry-point callback):
##   var data_ptr = alloc[MyData](1)
##   data_ptr.unsafe_write(MyData(args))
##   var exec_ref = my_execute
##   var comp_ref = my_complete
##   var aw = AsyncWork.queue(env, "name", data_ptr.unsafe_bitcast[NoneType](),
##       fn_ptr(exec_ref), fn_ptr(comp_ref))
##   data_ptr[].deferred = aw.deferred
##   data_ptr[].work = aw.work
##   return aw.value
##
## Usage (complete callback):
##   AsyncWork.resolve(env, ptr[].deferred, ptr[].work, result_val)
##   ptr.unsafe_deinit_pointee()
##   ptr.unsafe_free()
##
## AsyncWork.queue_on_thread takes the same arguments and runs the same two
## callbacks, with `execute` on a thread of its own instead of libuv's thread
## pool. Its result carries a null work handle, which resolve and the
## reject_with_error forms accept.

from std.atomic import Atomic
from std.ffi import c_int, external_call
from std.memory.alloc import unsafe_alloc

from napi.types import (
    NapiEnv,
    NapiValue,
    NapiStatus,
    NapiStore,
    NapiDeferred,
    NapiAsyncWork,
    NapiThreadsafeFunction,
    NAPI_OK,
    NAPI_CLOSING,
    NAPI_TSFN_NONBLOCKING,
    NAPI_TSFN_RELEASE,
)
from napi.bindings import Bindings
from napi.raw import (
    raw_create_async_work,
    raw_queue_async_work,
    raw_delete_async_work,
    raw_resolve_deferred,
    raw_reject_deferred,
    raw_create_error,
    raw_call_threadsafe_function,
    raw_release_threadsafe_function,
    raw_add_env_cleanup_hook,
    raw_remove_env_cleanup_hook,
)
from napi.error import check_status
from napi.framework.js_promise import JsPromise
from napi.framework.js_string import JsString
from napi.framework.threadsafe_function import ThreadsafeFunction


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

        var work = NapiAsyncWork(unsafe_from_address=Int(0))
        var work_out: OpaquePointer[MutAnyOrigin] = Pointer(
            to=work
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var null_resource = NapiValue(unsafe_from_address=Int(0))

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

    @staticmethod
    def queue_on_thread(
        b: Bindings,
        env: NapiEnv,
        name: StringLiteral,
        data_opaque: OpaquePointer[MutAnyOrigin],
        execute_ptr: OpaquePointer[MutAnyOrigin],
        complete_ptr: OpaquePointer[MutAnyOrigin],
    ) raises -> AsyncWorkResult:
        """Run `execute` on a thread of its own, then `complete` on the JS thread.

        Takes the same arguments and the same two callbacks as `queue`. Use it
        for a job long enough to matter to libuv's thread pool, which is where
        `queue` runs `execute`: four threads by default (`UV_THREADPOOL_SIZE`),
        shared with `fs`, `dns.lookup`, `crypto` and `zlib`, so four jobs that
        each take a second stall every file read in the process for that
        second. This starts a thread per call, with the 8 MiB stack libuv
        gives its own threads, and hands the job back to the JS thread
        through a threadsafe function.

        Where it differs from `queue`:

        - The result's `work` is null and there is nothing to cancel. `resolve`
          and the `reject_with_error` forms accept the null handle.
        - Starting a thread costs tens of microseconds, so short jobs belong
          on `queue`.
        - If the environment is torn down with the job in flight (a
          terminated `Worker`), teardown waits for `execute` to return, as it
          does for queued work, and `complete` then runs with a null `env` and
          status `napi_closing`, possibly on the job's thread. It must only
          free its data then, which is all `resolve` and the
          `reject_with_error` forms do for a null env.
        - A job in flight keeps the event loop alive, as queued work does.

        Args:
            b: The cached bindings.
            env: The current environment.
            name: Resource name for async diagnostics.
            data_opaque: The job's data, handed to both callbacks.
            execute_ptr: `def(env, data)`, run on the job's thread. It must
                not call N-API.
            complete_ptr: `def(env, status, data)`, run on the JS thread once
                `execute` returns. It owns `data` and frees it.

        Returns:
            The promise, its deferred, and a null work handle.

        Raises:
            If the promise, the threadsafe function, the cleanup hook or the
            thread cannot be created. Neither callback runs then, and the
            caller still owns `data`.
        """
        var p = JsPromise.create(b, env)
        var resource_name = JsString.create_literal(b, env, name)
        var call_js_ref = _job_call_js
        # No JS function: _job_call_js does the work. An unlimited queue
        # (max_queue_size 0) means the hand-off never waits.
        var tsfn = ThreadsafeFunction.create(
            b,
            env,
            NapiValue(unsafe_from_address=Int(0)),
            resource_name.value,
            UInt(0),
            Pointer(to=call_js_ref).unsafe_bitcast[
                OpaquePointer[MutAnyOrigin]
            ]()[],
            OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0)),
            OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0)),
        )

        var job = unsafe_alloc[_ThreadJob](1)
        job.unsafe_write(
            _ThreadJob(
                execute_ptr.unsafe_origin_cast[MutUntrackedOrigin](),
                complete_ptr.unsafe_origin_cast[MutUntrackedOrigin](),
                data_opaque.unsafe_origin_cast[MutUntrackedOrigin](),
                env,
                tsfn.tsfn,
                Int(b),
            )
        )
        var job_arg = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(job))

        # Registered AFTER the threadsafe function, so it runs BEFORE that
        # function's own teardown: cleanup hooks run newest first.
        var hook_ref = _job_env_teardown
        var hook_ptr = Pointer(to=hook_ref).unsafe_bitcast[
            OpaquePointer[MutAnyOrigin]
        ]()[]
        # _job_call_js removes the hook with this exact pointer, never its own
        # reference to _job_env_teardown: see _ThreadJob.hook.
        job[].hook = hook_ptr.unsafe_origin_cast[MutUntrackedOrigin]()
        var added = raw_add_env_cleanup_hook(b, env, hook_ptr, job_arg)
        if added != NAPI_OK:
            _ = raw_release_threadsafe_function(
                b, tsfn.tsfn, NAPI_TSFN_RELEASE
            )
            job.unsafe_deinit_pointee()
            job.unsafe_free()
            check_status(added)

        var main_ref = _job_thread_main
        var rc = _spawn_thread(
            Pointer(to=main_ref).unsafe_bitcast[Int]()[], job.as_unsafe_any_origin()
        )
        if rc != 0:
            _ = raw_remove_env_cleanup_hook(b, env, hook_ptr, job_arg)
            _ = raw_release_threadsafe_function(
                b, tsfn.tsfn, NAPI_TSFN_RELEASE
            )
            job.unsafe_deinit_pointee()
            job.unsafe_free()
            raise Error("napi-mojo: pthread_create failed with ", rc)

        return AsyncWorkResult(
            p.value, p.deferred, NapiAsyncWork(unsafe_from_address=Int(0))
        )

    @staticmethod
    def resolve(
        b: Bindings,
        env: NapiEnv,
        deferred: NapiDeferred,
        work: NapiAsyncWork,
        result: NapiValue,
    ) raises:
        if Int(env) == 0:
            return  # environment gone: there is no promise left to settle
        try:
            check_status(raw_resolve_deferred(b, env, deferred, result))
        except e:
            try:
                _delete_work(b, env, work)
            except:
                pass  # keep the settle failure as the reported error
            raise e^
        _delete_work(b, env, work)

    @staticmethod
    def reject_with_error(
        b: Bindings,
        env: NapiEnv,
        deferred: NapiDeferred,
        work: NapiAsyncWork,
        msg: StringLiteral,
    ) raises:
        if Int(env) == 0:
            return  # environment gone: there is no promise left to settle
        try:
            var msg_val = JsString.create_literal(b, env, msg)
            var null_code = NapiValue(unsafe_from_address=Int(0))
            var error_val = NapiValue(unsafe_from_address=Int(0))
            var error_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
                to=error_val
            ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
            check_status(
                raw_create_error(b, env, null_code, msg_val.value, error_ptr)
            )
            check_status(raw_reject_deferred(b, env, deferred, error_val))
        except e:
            try:
                _delete_work(b, env, work)
            except:
                pass  # keep the reject failure as the reported error
            raise e^
        _delete_work(b, env, work)

    @staticmethod
    def reject_with_error_dynamic(
        b: Bindings,
        env: NapiEnv,
        deferred: NapiDeferred,
        work: NapiAsyncWork,
        msg: String,
    ) raises:
        if Int(env) == 0:
            return  # environment gone: there is no promise left to settle
        try:
            var msg_copy = msg
            var msg_val = JsString.create(b, env, msg_copy)
            _ = msg_copy^
            var null_code = NapiValue(unsafe_from_address=Int(0))
            var error_val = NapiValue(unsafe_from_address=Int(0))
            var error_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
                to=error_val
            ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
            check_status(
                raw_create_error(b, env, null_code, msg_val.value, error_ptr)
            )
            check_status(raw_reject_deferred(b, env, deferred, error_val))
        except e:
            try:
                _delete_work(b, env, work)
            except:
                pass  # keep the reject failure as the reported error
            raise e^
        _delete_work(b, env, work)


def _delete_work(b: Bindings, env: NapiEnv, work: NapiAsyncWork) raises:
    # queue_on_thread has no napi_async_work to delete.
    if Int(work) != 0:
        check_status(raw_delete_async_work(b, env, work))


# ---------------------------------------------------------------------------
# queue_on_thread's job
#
# Three parties touch a job: its thread, the threadsafe function's call_js_cb
# (_job_call_js) and an environment cleanup hook (_job_env_teardown). The
# last two run on the environment's own thread, and whichever runs first
# joins the job's thread before it reads anything the thread wrote. That join
# is the whole of the synchronisation.
#
# The hook is for a Worker terminated with the job in flight, and it joins,
# so teardown waits for the job exactly as it waits for queued
# napi_async_work (measured: a terminated Worker exits ~950 ms after
# terminate() with a one-second job in flight, on either path). Returning
# sooner is a crash two ways over:
#   - Node 22 and 24 free a threadsafe function at teardown even while a
#     thread still holds it (Node's main branch waits for the last holder);
#   - Node dlcloses a Worker's addons when its environment is destroyed,
#     which unmapped this image under a thread still in `execute` (SIGSEGV on
#     Linux, every run).
# Pinning the image instead is not portable. dyld ignores RTLD_NODELETE on an
# RTLD_NOLOAD re-open, and without NOLOAD it keeps only the image's own pages
# mapped: it still runs the image's terminators and unmaps the Mojo runtime
# libraries it depends on (dyld's DyldAPIs.cpp and DyldRuntimeState.cpp).
# The hook is registered AFTER the threadsafe function, so it runs before
# that function's own teardown: cleanup hooks run newest first.
#
# The hook also raises `closing` before it joins, and a thread that sees it
# after `execute` completes the job itself instead of queuing it. Node drains
# a torn-down threadsafe function's queue into call_js_cb with a null env;
# Deno 2.9.6 and Bun 1.3.11 do not, so a job queued at teardown leaked its
# data there (check-runtimes.mjs, ownThreadTeardown).
#
# _job_call_js joins as well, because the thread still calls
# napi_release_threadsafe_function after its job is queued, and a Worker
# terminated inside that window would free the function under it. By then
# `execute` has returned, so the wait is the thread's last few calls.
# ---------------------------------------------------------------------------

comptime _JOB_STACK_BYTES = 8 << 20
"""What libuv gives each pool thread. `execute` is written for either place,
and macOS would otherwise give a new thread 512 KiB."""


struct _ThreadJob(Movable):
    var execute: NapiStore
    var complete: NapiStore
    var data: NapiStore
    var env: NapiEnv
    var tsfn: NapiThreadsafeFunction
    var bindings_addr: Int
    # The cleanup hook exactly as registered. A `def` taken as a value is a
    # closure materialised at that use site, so _job_env_teardown's address
    # in _job_call_js is not the one queue_on_thread registered (measured
    # 0x1A0 apart), and napi_remove_env_cleanup_hook returns napi_ok whether
    # it found the pair or not: the hook silently stayed, and Node aborted on
    # the duplicate pair when a later job reused this job's address.
    var hook: NapiStore
    var tid: Int  # pthread_t: set after pthread_create, read by whoever joins
    var closing: Int64  # atomic: set by the hook before it joins
    var joined: Bool  # environment thread only
    var queued: Bool  # written by the job's thread, read after it is joined
    var hook_ran: Bool  # environment thread only
    var completed: Bool  # environment thread only: completed with a null env

    def __init__(
        out self,
        execute: NapiStore,
        complete: NapiStore,
        data: NapiStore,
        env: NapiEnv,
        tsfn: NapiThreadsafeFunction,
        bindings_addr: Int,
    ):
        self.execute = execute
        self.complete = complete
        self.data = data
        self.env = env
        self.tsfn = tsfn
        self.bindings_addr = bindings_addr
        self.hook = NapiStore(unsafe_from_address=Int(0))
        self.tid = 0
        self.closing = 0
        self.joined = False
        self.queued = False
        self.hook_ran = False
        self.completed = False


comptime _JobPtr = Pointer[_ThreadJob, MutAnyOrigin]


@always_inline
def _atomic(ref word: Int64) -> Pointer[Atomic[Int64], MutUntrackedOrigin]:
    return Pointer[Atomic[Int64], MutUntrackedOrigin](
        unsafe_from_address=Int(Pointer(to=word))
    )


def _reap(job: _JobPtr):
    # Wait for the job's thread to exit, once. Environment thread only.
    if not job[].joined:
        _ = external_call["pthread_join", c_int, Int, Int](job[].tid, 0)
        job[].joined = True


def _free_job(job: _JobPtr):
    job.unsafe_deinit_pointee()
    job.unsafe_free()


def _run_complete(job: _JobPtr, env: NapiEnv, status: NapiStatus):
    var complete = job[].complete
    var run = Pointer(to=complete).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin], NapiStatus, OpaquePointer[MutAnyOrigin]
        ) thin abi("C") -> None
    ]()[]
    run(env.as_unsafe_any_origin(), status, job[].data.as_unsafe_any_origin())


def _job_thread_main(arg: Int) -> Int:
    var job = OpaquePointer[MutAnyOrigin](
        unsafe_from_address=arg
    ).unsafe_bitcast[_ThreadJob]()
    var execute = job[].execute
    var run = Pointer(to=execute).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin], OpaquePointer[MutAnyOrigin]
        ) thin abi("C") -> None
    ]()[]
    run(job[].env.as_unsafe_any_origin(), job[].data.as_unsafe_any_origin())

    var no_env = NapiEnv(unsafe_from_address=Int(0))
    if _atomic(job[].closing)[].load() != 0:
        # The environment is being torn down and its hook is waiting on
        # this thread: complete here rather than queue behind the teardown.
        # The threadsafe function is left alone, not even released: that the
        # hook runs before the function's own teardown is Node's order, and
        # N-API does not promise it.
        _run_complete(job, no_env, NAPI_CLOSING)
        return 0
    var b = Bindings(unsafe_from_address=job[].bindings_addr)
    var tsfn = job[].tsfn
    var pushed = raw_call_threadsafe_function(
        b,
        tsfn,
        OpaquePointer[MutAnyOrigin](unsafe_from_address=arg),
        NAPI_TSFN_NONBLOCKING,
    )
    if pushed == NAPI_OK:
        _ = raw_release_threadsafe_function(b, tsfn, NAPI_TSFN_RELEASE)
        job[].queued = True  # safe after the push: every reader joins first
        return 0
    # Not queued, so _job_call_js never sees this job: complete it here. On
    # napi_closing the call has already given up this thread's hold.
    _run_complete(job, no_env, NAPI_CLOSING)
    return 0


def _job_call_js(
    env: NapiEnv,
    js_callback: NapiValue,
    context: OpaquePointer[MutAnyOrigin],
    data: OpaquePointer[MutAnyOrigin],
):
    var job = data.unsafe_bitcast[_ThreadJob]()
    _reap(job)
    if Int(env) == 0:
        # Teardown drained the queue: the job was queued, the env is gone.
        _run_complete(job, env, NAPI_CLOSING)
        job[].completed = True
        if job[].hook_ran:
            _free_job(job)
        return
    var b = Bindings(unsafe_from_address=job[].bindings_addr)
    _ = raw_remove_env_cleanup_hook(
        b, env, job[].hook.as_unsafe_any_origin(), data
    )
    _run_complete(job, env, NAPI_OK)
    _free_job(job)


def _job_env_teardown(arg: OpaquePointer[MutAnyOrigin]):
    var job = arg.unsafe_bitcast[_ThreadJob]()
    job[].hook_ran = True
    _atomic(job[].closing)[].store(1)
    _reap(job)
    if job[].completed or not job[].queued:
        _free_job(job)
    # Otherwise queued: on Node the threadsafe function's own teardown, which
    # runs after this hook, drains it into _job_call_js with a null env.


def _spawn_thread(body: Int, job: _JobPtr) -> Int:
    # Joinable, with libuv's stack size; returns pthread_create's result.
    # pthread_attr_t is 56 bytes on x86-64 Linux and 64 on arm64 and macOS.
    var attr = unsafe_alloc[Int](16)
    var tid = unsafe_alloc[Int](1)
    var rc = Int(external_call["pthread_attr_init", c_int, Int](Int(attr)))
    if rc == 0:
        _ = external_call["pthread_attr_setstacksize", c_int, Int, Int](
            Int(attr), _JOB_STACK_BYTES
        )
        rc = Int(
            external_call["pthread_create", c_int, Int, Int, Int, Int](
                Int(tid), Int(attr), body, Int(job)
            )
        )
        _ = external_call["pthread_attr_destroy", c_int, Int](Int(attr))
        if rc == 0:
            job[].tid = tid[]
    attr.unsafe_free()
    tid.unsafe_free()
    return rc
