## src/napi/framework/escapable_handle_scope.mojo — escapable handle scope
##
## EscapableHandleScope wraps napi_escapable_handle_scope. Like HandleScope,
## but allows ONE value to be "escaped" (promoted) to the outer scope.
##
## Usage:
##   var esc = EscapableHandleScope.open(env)
##   var obj = JsObject.create(env)
##   # ... build obj ...
##   var escaped = esc.escape(env, obj.value)  # ONCE only
##   esc.close(env)
##   return escaped

from napi.types import NapiEnv, NapiValue, NapiEscapableHandleScope
from napi.raw import (
    raw_open_escapable_handle_scope,
    raw_close_escapable_handle_scope,
    raw_escape_handle,
)
from napi.error import check_status

struct EscapableHandleScope:
    var scope: NapiEscapableHandleScope

    fn __init__(out self, scope: NapiEscapableHandleScope):
        self.scope = scope

    @staticmethod
    fn open(env: NapiEnv) raises -> EscapableHandleScope:
        var scope = NapiEscapableHandleScope()
        check_status(raw_open_escapable_handle_scope(env,
            UnsafePointer(to=scope).bitcast[NoneType]()))
        return EscapableHandleScope(scope)

    fn escape(self, env: NapiEnv, value: NapiValue) raises -> NapiValue:
        var result = NapiValue()
        check_status(raw_escape_handle(env, self.scope, value,
            UnsafePointer(to=result).bitcast[NoneType]()))
        return result

    fn close(self, env: NapiEnv) raises:
        check_status(raw_close_escapable_handle_scope(env, self.scope))
