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
## IMPORTANT: Mojo has no RAII destructors. You MUST call close() explicitly.
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

    ## open — create a new handle scope
    @staticmethod
    def open(env: NapiEnv) raises -> HandleScope:
        var scope: NapiHandleScope = NapiHandleScope()
        var scope_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=scope).bitcast[NoneType]()
        check_status(raw_open_handle_scope(env, scope_ptr))
        return HandleScope(scope)

    @staticmethod
    def open(b: Bindings, env: NapiEnv) raises -> HandleScope:
        var scope: NapiHandleScope = NapiHandleScope()
        var scope_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=scope).bitcast[NoneType]()
        check_status(raw_open_handle_scope(b, env, scope_ptr))
        return HandleScope(scope)

    ## close — destroy this handle scope, releasing all handles within it
    def close(self, env: NapiEnv) raises:
        check_status(raw_close_handle_scope(env, self.scope))

    def close(self, b: Bindings, env: NapiEnv) raises:
        check_status(raw_close_handle_scope(b, env, self.scope))
