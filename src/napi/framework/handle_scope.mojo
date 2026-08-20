## src/napi/framework/handle_scope.mojo — explicit handle scope management
##
## Every napi_value created inside a callback lives in the current handle scope.
## For loops that create many temporary values, open a sub-scope per iteration
## and close it to release handles:
##
##   for i in range(len):
##       var hs = HandleScope.open(env)
##       # ... create napi_values ...
##       hs.close(env)
##
## IMPORTANT: close() must be called explicitly, and that is DELIBERATE — not
## a missing-language-feature workaround. Mojo does have destructors
## (__deinit__), but ASAP destruction runs them at the value's LAST USE, not
## at end of scope: an auto-closing HandleScope would close right after
## open() (or mid-body) and invalidate every handle created after it. Keeping
## close() explicit is the only ordering that is correct under ASAP semantics.
## Consequence: a `raise` between open() and close() leaks the scope, and a
## leaked inner scope makes the outer close() fail with
## napi_handle_scope_mismatch — wrap raising bodies in try/except and close in
## both paths.
## Values set on objects/arrays outside the scope survive scope closure
## (they are referenced by the parent object, not the scope).

from napi.types import NapiEnv, NapiHandleScope
from napi.raw import raw_open_handle_scope, raw_close_handle_scope
from napi.error import check_status
from napi.bindings import Bindings


## HandleScope — typed wrapper for napi_handle_scope
struct HandleScope:
    var scope: NapiHandleScope

    def __init__(out self, scope: NapiHandleScope):
        self.scope = scope

    @staticmethod
    def open(b: Bindings, env: NapiEnv) raises -> HandleScope:
        var scope: NapiHandleScope = NapiHandleScope(unsafe_from_address=Int(0))
        var scope_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
            to=scope
        ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        check_status(raw_open_handle_scope(b, env, scope_ptr))
        return HandleScope(scope)

    def close(self, b: Bindings, env: NapiEnv) raises:
        check_status(raw_close_handle_scope(b, env, self.scope))


def with_handle_scope[
    body: def () capturing raises -> None
](b: Bindings, env: NapiEnv) raises:
    """Run `body` inside its own handle scope, closing it on both paths.

    This is the encapsulated form of the try/except discipline this module's
    header describes. It matters most when Mojo drives a loop that calls into
    JavaScript: every napi_value the iteration creates is pinned to the
    enclosing scope until that scope closes, so a long Mojo-driven loop
    without a per-iteration scope grows handles without bound.

        for i in range(n):
            @parameter
            def _step():
                _ = fs.call_method(b, env, "readFileSync", args)
            with_handle_scope[_step](b, env)

    The body's error wins: if `body` raises, the scope is still closed, and
    the original error propagates unchanged rather than being replaced by a
    generic wrapper. A failure to close is deliberately swallowed in that
    path, because the body's error is the more useful diagnosis.

    Parameters:
        body: The work to run inside the scope.

    Args:
        b: Cached N-API bindings.
        env: The N-API environment.

    Raises:
        Error: Whatever `body` raised, or a scope open/close failure.
    """
    var hs = HandleScope.open(b, env)
    try:
        body()
    except e:
        try:
            hs.close(b, env)
        except:
            pass
        raise e^
    hs.close(b, env)
