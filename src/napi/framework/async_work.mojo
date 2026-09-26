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
from std.ffi import OwnedDLHandle, c_char, c_int, external_call
from std.memory.alloc import unsafe_alloc
from std.sys.info import CompilationTarget

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
        second. This starts a detached thread per call, with the 8 MiB stack
        libuv gives its own threads, and hands the job back to the JS thread
        through a threadsafe function.

        Where it differs from `queue`:

        - The result's `work` is null and there is nothing to cancel. `resolve`
          and the `reject_with_error` forms accept the null handle.
        - Starting a thread costs tens of microseconds, so short jobs belong
          on `queue`.
        - If the environment is torn down first (a terminated `Worker`),
          `complete` runs with a null `env` and status `napi_closing`,
          possibly on the job's thread. It must then only free its data, which
          is all `resolve` and the `reject_with_error` forms do for a null env.
        - A job in flight keeps the event loop alive, as queued work does.
        - The addon's image is pinned: never unloaded, even after the last
          `Worker` that loaded it exits, because a job's thread can still be
          running its code then.

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
            If the image cannot be pinned, or the promise, the threadsafe
            function, the cleanup hook or the thread cannot be created.
            Neither callback runs then, and the caller still owns `data`.
        """
        _pin_this_image()
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
        var added = raw_add_env_cleanup_hook(b, env, hook_ptr, job_arg)
        if added != NAPI_OK:
            _ = raw_release_threadsafe_function(
                b, tsfn.tsfn, NAPI_TSFN_RELEASE
            )
            job.unsafe_deinit_pointee()
            job.unsafe_free()
            check_status(added)

        var main_ref = _job_thread_main
        var rc = _spawn_detached(
            Pointer(to=main_ref).unsafe_bitcast[Int]()[], Int(job)
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
# The job's thread runs this image's code, and Node dlcloses a Worker's
# addons when that Worker's environment is destroyed: for an addon only a
# Worker loaded, that unmaps it under a thread still sleeping in `execute`,
# which then faults on return (measured: SIGSEGV at an unnamed address, every
# run). A thread cannot release a hold on the code it is running, so
# queue_on_thread pins the image for good before it starts one.
#
# Three parties touch a job: its thread, the threadsafe function's call_js_cb
# (_job_call_js, on the JS thread) and an environment cleanup hook
# (_job_env_teardown, on the JS thread at teardown). The hook exists because
# Node 22 and 24 FREE a threadsafe function when its environment is torn
# down, even while a thread still holds it, so a thread that finishes after a
# Worker was terminated would call into freed memory. (Node's main branch
# waits for the last holder; the versions this framework supports do not.)
#
# `state` settles who completes the job. The thread and the hook race to
# leave _JOB_RUNNING: if the thread wins it hands the job over, and the hook
# waits out the two threadsafe-function calls, which are what the teardown
# after it frees; if the hook wins, the thread never touches the threadsafe
# function and runs `complete` itself with a null env. `refs` is one
# reference for the thread and one for the JS side, and whichever party
# drops the last one frees the job.
# ---------------------------------------------------------------------------

comptime _JOB_RUNNING: Int64 = 0
comptime _JOB_HANDING_OFF: Int64 = 1  # the thread is inside the two TSFN calls
comptime _JOB_QUEUED: Int64 = 2  # handed over: _job_call_js completes the job
comptime _JOB_NOT_QUEUED: Int64 = 3  # the hand-off failed: the thread completed it
comptime _JOB_ENV_GONE: Int64 = 4  # the hook won: the thread completes it

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
    var state: Int64  # atomic: _JOB_*
    var refs: Int64  # atomic: the thread's reference and the JS side's
    var hook_ran: Bool  # JS thread only
    var completed: Bool  # JS thread only: completed with a null env

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
        self.state = _JOB_RUNNING
        self.refs = 2
        self.hook_ran = False
        self.completed = False


comptime _JobPtr = Pointer[_ThreadJob, MutAnyOrigin]


@always_inline
def _atomic(ref word: Int64) -> Pointer[Atomic[Int64], MutUntrackedOrigin]:
    return Pointer[Atomic[Int64], MutUntrackedOrigin](
        unsafe_from_address=Int(Pointer(to=word))
    )


def _drop_ref(job: _JobPtr):
    if _atomic(job[].refs)[].fetch_sub(1) == 1:
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
    var expected = _JOB_RUNNING
    if _atomic(job[].state)[].compare_exchange(expected, _JOB_HANDING_OFF):
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
            _atomic(job[].state)[].store(_JOB_QUEUED)
        else:
            # Not queued, so _job_call_js never sees this job. On napi_closing
            # the call has already given up this thread's hold: no release.
            _atomic(job[].state)[].store(_JOB_NOT_QUEUED)
            _run_complete(job, no_env, NAPI_CLOSING)
    else:
        # The environment is gone and so, possibly, is the threadsafe function.
        _run_complete(job, no_env, NAPI_CLOSING)
    _drop_ref(job)
    return 0


def _job_call_js(
    env: NapiEnv,
    js_callback: NapiValue,
    context: OpaquePointer[MutAnyOrigin],
    data: OpaquePointer[MutAnyOrigin],
):
    var job = data.unsafe_bitcast[_ThreadJob]()
    if Int(env) == 0:
        # Teardown drained the queue: the job was handed over, the env is gone.
        _run_complete(job, env, NAPI_CLOSING)
        job[].completed = True
        if job[].hook_ran:
            _drop_ref(job)
        return
    var b = Bindings(unsafe_from_address=job[].bindings_addr)
    var hook_ref = _job_env_teardown
    _ = raw_remove_env_cleanup_hook(
        b,
        env,
        Pointer(to=hook_ref).unsafe_bitcast[OpaquePointer[MutAnyOrigin]]()[],
        data,
    )
    _run_complete(job, env, NAPI_OK)
    _drop_ref(job)


def _job_env_teardown(arg: OpaquePointer[MutAnyOrigin]):
    var job = arg.unsafe_bitcast[_ThreadJob]()
    job[].hook_ran = True
    var expected = _JOB_RUNNING
    if _atomic(job[].state)[].compare_exchange(expected, _JOB_ENV_GONE):
        _drop_ref(job)  # _job_call_js will never see this job
        return
    # The thread is handing the job over, or has. The teardown after this hook
    # frees the threadsafe function, so wait until the thread is out of it.
    while _atomic(job[].state)[].load() == _JOB_HANDING_OFF:
        _ = external_call["sched_yield", c_int]()
    if _atomic(job[].state)[].load() == _JOB_NOT_QUEUED or job[].completed:
        _drop_ref(job)
    # Otherwise queued: teardown drains it into _job_call_js with a null env,
    # which drops the JS side's reference.


def _pin_flags() -> Int:
    # RTLD_LAZY | RTLD_NOLOAD | RTLD_NODELETE. glibc refuses a mode with no
    # binding mode (mojo-http's m0-postgres measured it), NOLOAD so this can
    # never map a second image, and no RTLD_GLOBAL: Node opened the addon local.
    comptime if CompilationTarget.is_macos():
        return 1 | 0x10 | 0x80
    else:
        return 1 | 4 | 0x1000


def _pin_this_image() raises:
    # Re-open this image by the name the loader knows it by, flagged
    # RTLD_NODELETE, which both glibc and dyld apply to an image already
    # loaded: no dlclose unmaps it after that, this handle's own included.
    # Through OwnedDLHandle because the stdlib already declares dlopen.
    var info = unsafe_alloc[Int](4)  # Dl_info: four words, dli_fname first
    var main_ref = _job_thread_main
    var found = external_call["dladdr", c_int, Int, Int](
        Pointer(to=main_ref).unsafe_bitcast[Int]()[], Int(info)
    )
    var fname = info[]
    info.unsafe_free()
    if found == 0 or fname == 0:
        raise Error("napi-mojo: dladdr could not name this addon's image")
    var path = String(
        unsafe_from_utf8_ptr=Pointer[c_char, MutUntrackedOrigin](
            unsafe_from_address=fname
        )
    )
    _ = OwnedDLHandle(path, _pin_flags())


def _spawn_detached(body: Int, arg: Int) -> Int:
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
                Int(tid), Int(attr), body, arg
            )
        )
        _ = external_call["pthread_attr_destroy", c_int, Int](Int(attr))
        if rc == 0:
            _ = external_call["pthread_detach", c_int, Int](tid[])
    attr.unsafe_free()
    tid.unsafe_free()
    return rc
