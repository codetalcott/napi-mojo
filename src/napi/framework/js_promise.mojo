## src/napi/framework/js_promise.mojo — ergonomic wrapper for JavaScript promises
##
## JsPromise pairs a JavaScript Promise napi_value with its NapiDeferred handle:
##
##   var p = JsPromise.create(env)
##   p.resolve(env, some_value)    # resolves the promise
##   return p.value                # return the promise to JS
##
##   var p = JsPromise.create(env)
##   p.reject(env, error_value)    # rejects the promise
##   return p.value
##
## Each JsPromise can only be resolved OR rejected once. After settlement,
## the deferred handle is consumed and must not be used again.

from napi.types import NapiEnv, NapiValue, NapiDeferred
from napi.bindings import Bindings
from napi.raw import raw_create_promise, raw_resolve_deferred, raw_reject_deferred
from napi.error import check_status

struct JsPromise:
    var value: NapiValue       # the promise — return this to JavaScript
    var deferred: NapiDeferred # used once to resolve or reject

    fn __init__(out self, value: NapiValue, deferred: NapiDeferred):
        self.value = value
        self.deferred = deferred

    ## create — construct a new JavaScript Promise (env-only)
    ##
    ## env-only: for async complete, TSFN, finalizer, and except-block callbacks
    ## where NapiBindings is unavailable. Use create(b, env) in hot paths.
    ##
    ## Calls napi_create_promise. Returns a JsPromise holding both the promise
    ## napi_value (to return to JS) and the deferred handle (to settle it).
    @staticmethod
    fn create(env: NapiEnv) raises -> JsPromise:
        var deferred = NapiDeferred()
        var promise = NapiValue()
        var deferred_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=deferred).bitcast[NoneType]()
        var promise_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=promise).bitcast[NoneType]()
        var status = raw_create_promise(env, deferred_ptr, promise_ptr)
        check_status(status)
        return JsPromise(promise, deferred)

    ## resolve — resolve the promise with a value
    ##
    ## Calls napi_resolve_deferred. After this, the deferred is consumed.
    fn resolve(self, env: NapiEnv, resolution: NapiValue) raises:
        var status = raw_resolve_deferred(env, self.deferred, resolution)
        check_status(status)

    ## reject — reject the promise with a value
    ##
    ## Calls napi_reject_deferred. After this, the deferred is consumed.
    ## Typically `rejection` should be a JavaScript Error object.
    fn reject(self, env: NapiEnv, rejection: NapiValue) raises:
        var status = raw_reject_deferred(env, self.deferred, rejection)
        check_status(status)

    # --- Bindings-aware overloads ---

    @staticmethod
    fn create(b: Bindings, env: NapiEnv) raises -> JsPromise:
        var deferred = NapiDeferred()
        var promise = NapiValue()
        var deferred_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=deferred).bitcast[NoneType]()
        var promise_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=promise).bitcast[NoneType]()
        var status = raw_create_promise(b, env, deferred_ptr, promise_ptr)
        check_status(status)
        return JsPromise(promise, deferred)

    fn resolve(self, b: Bindings, env: NapiEnv, resolution: NapiValue) raises:
        var status = raw_resolve_deferred(b, env, self.deferred, resolution)
        check_status(status)

    fn reject(self, b: Bindings, env: NapiEnv, rejection: NapiValue) raises:
        var status = raw_reject_deferred(b, env, self.deferred, rejection)
        check_status(status)
