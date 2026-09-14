"""JavaScript promises, in both directions.

**Producing a promise** — `JsPromise` pairs a Promise napi_value with its
deferred handle. Settle it once, then hand `value` to JavaScript:

```mojo
var p = JsPromise.create(b, env)
p.resolve(b, env, some_value)    # or p.reject(b, env, error_value)
return p.value
```

**Consuming a promise** — `JsPromise.on_settled` attaches a Mojo continuation,
and the continuation reads its outcome with `Settlement.read`:

```mojo
# in the calling callback — `on_done` is an ordinary napi callback
var cb_ref = on_done
return JsPromise.on_settled(b, env, promise, fn_ptr(cb_ref), captures)

# in on_done(env, info), inside its try block
var s = Settlement.read(env, info)
if not s.ok:
    ...                      # s.value is the rejection reason
...                          # s.value is the fulfilled value

# and in its except block — this rejects the promise on_settled returned
throw_js_error_dynamic(env, String(e))
```

Mojo code cannot wait for a promise. A napi callback runs on the JS thread,
and a promise settles only after that callback returns to the event loop, so
a continuation is the only shape: the callback returns, the loop runs, and the
continuation fires on a later tick. N-API offers no way to read a promise's
state or result, and re-entering the event loop from inside a callback runs
other JavaScript without ever running promise reactions.
"""

from std.memory.alloc import unsafe_alloc
from napi.types import (
    NapiEnv,
    NapiValue,
    NapiDeferred,
    NapiStore,
)
from napi.bindings import Bindings
from napi.raw import (
    raw_create_promise,
    raw_resolve_deferred,
    raw_reject_deferred,
)
from napi.error import check_status
from napi.framework.args import CbArgs
from napi.framework.js_boolean import JsBoolean
from napi.framework.js_function import JsFunction
from napi.framework.js_object import JsObject
from napi.framework.js_undefined import JsUndefined
from napi.framework.js_value import js_get_global


struct JsPromise:
    """A JavaScript Promise and the deferred handle that settles it."""

    var value: NapiValue
    """The promise itself — return this to JavaScript."""

    var deferred: NapiDeferred
    """Settles the promise. Usable exactly once."""

    def __init__(out self, value: NapiValue, deferred: NapiDeferred):
        """Pair an existing promise with its deferred handle.

        Prefer `create`, which makes both.

        Args:
            value: The promise napi_value.
            deferred: The deferred handle napi_create_promise returned with it.
        """
        self.value = value
        self.deferred = deferred

    @staticmethod
    def create(b: Bindings, env: NapiEnv) raises -> JsPromise:
        """Create a pending promise and its deferred handle.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.

        Returns:
            A JsPromise whose `value` is pending until `resolve` or `reject`.

        Raises:
            If napi_create_promise does not return napi_ok.
        """
        var deferred = NapiDeferred(unsafe_from_address=Int(0))
        var promise = NapiValue(unsafe_from_address=Int(0))
        var deferred_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=deferred
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var promise_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=promise
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var status = raw_create_promise(b, env, deferred_ptr, promise_ptr)
        check_status(status)
        return JsPromise(promise, deferred)

    def resolve(self, b: Bindings, env: NapiEnv, resolution: NapiValue) raises:
        """Fulfil the promise with `resolution`.

        The deferred handle is consumed: do not call `resolve` or `reject`
        on this JsPromise again.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            resolution: The value the promise fulfils with.

        Raises:
            If napi_resolve_deferred does not return napi_ok.
        """
        var status = raw_resolve_deferred(b, env, self.deferred, resolution)
        check_status(status)

    def reject(self, b: Bindings, env: NapiEnv, rejection: NapiValue) raises:
        """Reject the promise with `rejection`.

        Build the reason with `raw_create_error` rather than a throw helper, so
        no exception is left pending. The deferred handle is consumed.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            rejection: The rejection reason, usually an Error object.

        Raises:
            If napi_reject_deferred does not return napi_ok.
        """
        var status = raw_reject_deferred(b, env, self.deferred, rejection)
        check_status(status)

    @staticmethod
    def on_settled(
        b: Bindings,
        env: NapiEnv,
        value: NapiValue,
        cb_ptr: OpaquePointer[MutAnyOrigin],
        captures: List[NapiValue],
    ) raises -> NapiValue:
        """Attach a Mojo continuation that runs once `value` settles.

        The overload for a continuation that needs only JavaScript values.
        See the `data` overload for the full contract.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            value: A promise, a thenable, or any value — treated like `await`.
            cb_ptr: The continuation, a napi callback, via `fn_ptr(...)`.
            captures: JavaScript values the continuation needs later.

        Returns:
            The promise `.then()` returned. It settles with whatever the
            continuation returns or throws.

        Raises:
            If the continuation could not be attached.
        """
        return JsPromise.on_settled(
            b,
            env,
            value,
            cb_ptr,
            captures,
            OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0)),
            OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0)),
        )

    @staticmethod
    def on_settled(
        b: Bindings,
        env: NapiEnv,
        value: NapiValue,
        cb_ptr: OpaquePointer[MutAnyOrigin],
        captures: List[NapiValue],
        data: OpaquePointer[MutAnyOrigin],
        finalize_cb: OpaquePointer[MutAnyOrigin],
    ) raises -> NapiValue:
        """Attach a Mojo continuation that runs once `value` settles.

        Equivalent to `Promise.resolve(value).then(onFulfilled, onRejected)`,
        where both handlers are the one continuation `cb_ptr`. It reads the
        outcome with `Settlement.read(env, info)`. Because both handlers are
        attached, a rejection is always observed — it never surfaces as an
        unhandled rejection unless the continuation itself throws and nobody
        handles the returned promise, exactly as in JavaScript.

        **Nothing here is freed when the continuation fires**, because a
        continuation may never fire: the promise can stay pending forever.
        Everything is tied to the garbage collector instead:

        - `captures` become bound arguments of the handler functions, so the
          GC traces them. No napi_ref roots them, so a capture that refers
          back to the promise cannot keep the whole graph alive.
        - `data` is ADOPTED on every path, success or failure:
          `finalize_cb(env, data, null)` runs exactly once — when the handler
          functions are collected, or before this raises if the continuation
          could not be created. Never free `data` yourself after passing it.

        Do not rely on the continuation running at most once. A thenable with
        its own `then` can call a handler repeatedly, or both handlers; since
        nothing is freed on the call path, that is memory-safe.

        Args:
            b: Cached N-API bindings.
            env: The N-API environment.
            value: A promise, a thenable, or any value — treated like `await`.
            cb_ptr: The continuation, a napi callback, via `fn_ptr(...)`.
            captures: JavaScript values the continuation needs later, read
                back from `Settlement.captures` in the same order.
            data: Native state for the continuation, read back from
                `Settlement.user_data()`. May be null.
            finalize_cb: A `def(env, data, hint)` that frees `data`. May be
                null when `data` needs no freeing.

        Returns:
            The promise `.then()` returned. It settles with whatever the
            continuation returns or throws.

        Raises:
            If the continuation could not be attached. `data` has been
            finalized or is owned by the collector either way.
        """
        var ctx = unsafe_alloc[_SettleContext](1)
        ctx.unsafe_write(
            _SettleContext(Int(b), len(captures), data, finalize_cb)
        )
        var ctx_data = ctx.unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var settle = _create_settle_function(b, env, cb_ptr, ctx_data)

        # From here the finalizer owns ctx and the adopted data, so a failure
        # below only propagates — freeing anything would race the collector.
        var fulfilled = _bind_settle(b, env, settle, captures, True)
        var rejected = _bind_settle(b, env, settle, captures, False)

        var resolve_args = List[NapiValue]()
        resolve_args.append(value)
        var promise_ctor = JsObject(
            js_get_global(b, env).get_property(b, env, "Promise")
        )
        var promise = promise_ctor.call_method(b, env, "resolve", resolve_args)

        var then_args = List[NapiValue]()
        then_args.append(fulfilled)
        then_args.append(rejected)
        return JsObject(promise).call_method(b, env, "then", then_args)


struct Settlement(Movable):
    """The outcome a continuation attached by `JsPromise.on_settled` sees."""

    var b: Bindings
    """Cached N-API bindings, recovered from the continuation's context."""

    var ok: Bool
    """True if the promise fulfilled, False if it rejected."""

    var value: NapiValue
    """The fulfilled value, or the rejection reason when `ok` is False."""

    var captures: List[NapiValue]
    """The `captures` passed to `on_settled`, in the same order."""

    var _user_data: NapiStore

    def __init__(
        out self,
        b: Bindings,
        ok: Bool,
        value: NapiValue,
        var captures: List[NapiValue],
        user_data: OpaquePointer[MutAnyOrigin],
    ):
        """Assemble a settlement. Continuations use `read` instead.

        Args:
            b: Cached N-API bindings.
            ok: Whether the promise fulfilled.
            value: The fulfilled value or rejection reason.
            captures: The captured JavaScript values.
            user_data: The native `data` passed to `on_settled`.
        """
        self.b = b
        self.ok = ok
        self.value = value
        self.captures = captures^
        self._user_data = user_data.unsafe_origin_cast[MutUntrackedOrigin]()

    @staticmethod
    def read(env: NapiEnv, info: NapiValue) raises -> Settlement:
        """Read the outcome inside a continuation attached by `on_settled`.

        Needs no bindings argument: the continuation's context carries them,
        which is why this is the first call a continuation makes.

        Args:
            env: The N-API environment.
            info: The continuation's callback info.

        Returns:
            The settlement: bindings, outcome, value, captures and data.

        Raises:
            If the callback was not attached by `on_settled`.
        """
        var raw = CbArgs.get_data(env, info)
        if Int(raw) == 0:
            raise Error("Settlement.read: not a JsPromise.on_settled continuation")
        var ctx = raw.unsafe_bitcast[_SettleContext]()
        var b = Bindings(unsafe_from_address=ctx[].bindings_addr)
        var n = ctx[].capture_count

        # Bound arguments arrive first: captures, then the ok flag, then the
        # value `.then()` passed. Size from the context, not from argc, so a
        # thenable calling a handler with extra arguments cannot shift them.
        var argv = unsafe_alloc[NapiValue](n + 2)
        try:
            _ = CbArgs.get_argv(
                b, env, info, UInt(n + 2), argv.as_unsafe_any_origin()
            )
        except e:
            argv.unsafe_free()
            raise e^
        var captures = List[NapiValue]()
        for i in range(n):
            captures.append(argv[unsafe_offset=i])
        var ok_val = argv[unsafe_offset=n]
        var value = argv[unsafe_offset=n + 1]
        argv.unsafe_free()

        var ok = JsBoolean.from_napi_value(b, env, ok_val)
        return Settlement(
            b, ok, value, captures^, ctx[].user_data.as_unsafe_any_origin()
        )

    def user_data(self) -> OpaquePointer[MutAnyOrigin]:
        """Return the native `data` passed to `on_settled`, or null.

        Returns:
            The data pointer. It stays valid for as long as the continuation
            can run; do not free it — `on_settled` adopted it.
        """
        return self._user_data.as_unsafe_any_origin()


# --- on_settled internals ----------------------------------------------------


struct _SettleContext(Movable):
    # Heap state behind one continuation. Owned by the GC finalizer on the
    # native settle function — never by the call, which may never happen.
    var bindings_addr: Int
    var capture_count: Int
    var user_data: NapiStore
    var user_finalize: NapiStore

    def __init__(
        out self,
        bindings_addr: Int,
        capture_count: Int,
        user_data: OpaquePointer[MutAnyOrigin],
        user_finalize: OpaquePointer[MutAnyOrigin],
    ):
        self.bindings_addr = bindings_addr
        self.capture_count = capture_count
        self.user_data = user_data.unsafe_origin_cast[MutUntrackedOrigin]()
        self.user_finalize = user_finalize.unsafe_origin_cast[MutUntrackedOrigin]()


def _run_user_finalize(env: NapiEnv, ctx: Pointer[_SettleContext, MutAnyOrigin]):
    if Int(ctx[].user_finalize) == 0:
        return
    # Reinterpret the WORD holding the function address, never the address
    # itself — the same trap raw.mojo's _sym documents. Keep this the only
    # place the cast is spelled.
    var fn_word = ctx[].user_finalize.as_unsafe_any_origin()
    var finalize = Pointer(to=fn_word).unsafe_bitcast[
        def(
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
            OpaquePointer[MutAnyOrigin],
        ) thin abi("C") -> None
    ]()[]
    finalize(
        env.as_unsafe_any_origin(),
        ctx[].user_data.as_unsafe_any_origin(),
        OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0)),
    )


def _settle_context_finalize(
    env: NapiEnv,
    data: OpaquePointer[MutAnyOrigin],
    hint: OpaquePointer[MutAnyOrigin],
):
    var ctx = data.unsafe_bitcast[_SettleContext]()
    _run_user_finalize(env, ctx)
    ctx.unsafe_deinit_pointee()
    ctx.unsafe_free()


def _create_settle_function(
    b: Bindings,
    env: NapiEnv,
    cb_ptr: OpaquePointer[MutAnyOrigin],
    ctx_data: OpaquePointer[MutAnyOrigin],
) raises -> JsFunction:
    # Create the one native function both handlers are bound from, and hand
    # ctx to its finalizer. Until that finalizer is attached nothing else can
    # free ctx or the adopted data, so a failure here frees both before raising.
    # (A function that exists but has no finalizer is never handed out, so
    # freeing ctx under it is safe — it can never be called.)
    var ctx = ctx_data.unsafe_bitcast[_SettleContext]()
    try:
        var settle = JsFunction.create_with_data(
            b, env, "mojoSettle", cb_ptr, ctx_data
        )
        var fin_ref = _settle_context_finalize
        var fin_ptr = Pointer(to=fin_ref).unsafe_bitcast[
            OpaquePointer[MutAnyOrigin]
        ]()[]
        JsObject(settle.value).add_finalizer(b, env, ctx_data, fin_ptr)
        _ = fin_ref
        return settle^
    except e:
        _run_user_finalize(env, ctx)
        ctx.unsafe_deinit_pointee()
        ctx.unsafe_free()
        raise e^


def _bind_settle(
    b: Bindings,
    env: NapiEnv,
    settle: JsFunction,
    captures: List[NapiValue],
    ok: Bool,
) raises -> NapiValue:
    # settle.bind(undefined, ...captures, ok)
    var bind_args = List[NapiValue]()
    bind_args.append(JsUndefined.create(b, env).value)
    for i in range(len(captures)):
        bind_args.append(captures[i])
    bind_args.append(JsBoolean.create(b, env, ok).value)
    return JsObject(settle.value).call_method(b, env, "bind", bind_args)
