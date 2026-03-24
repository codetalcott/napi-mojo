## src/napi/framework/js_async_context.mojo — async context for napi_make_callback
##
## JsAsyncContext wraps napi_async_context, which tracks an async operation
## for Node.js async_hooks and AsyncLocalStorage integration.
##
## Usage:
##   # Create a named async context (resource_obj may be undefined)
##   var ctx = JsAsyncContext.create(b, env, resource_obj, resource_name)
##   # Call a JS function in that context (propagates ALS correctly)
##   var result = ctx.make_callback(b, env, recv, func, arg0)
##   ctx.destroy(b, env)
##
## napi_make_callback vs napi_call_function:
##   call_function: no async_hooks tracking, does NOT propagate ALS
##   make_callback: fires before/after hooks, propagates ALS context

from napi.types import NapiEnv, NapiValue, NapiAsyncContext
from napi.bindings import Bindings
from napi.raw import raw_async_init, raw_async_destroy, raw_make_callback
from napi.error import check_status

struct JsAsyncContext:
    var value: NapiAsyncContext

    def __init__(out self, value: NapiAsyncContext):
        self.value = value

    ## create — initialize an async context
    ##
    ## async_resource:      JS object representing the async resource, or
    ##                      pass js_get_undefined() if no object is needed
    ## async_resource_name: napi_value string naming the resource type
    ##                      (e.g. JsString.create_literal(b, env, "MyOp"))
    @staticmethod
    def create(
        b: Bindings,
        env: NapiEnv,
        async_resource: NapiValue,
        async_resource_name: NapiValue,
    ) raises -> JsAsyncContext:
        var result = NapiAsyncContext()
        check_status(raw_async_init(b, env, async_resource, async_resource_name,
            UnsafePointer(to=result).bitcast[NoneType]()))
        return JsAsyncContext(result)

    ## destroy — release the async context
    ##
    ## Must be called when the async operation is complete.
    ## After calling, self.value is invalid.
    def destroy(self, b: Bindings, env: NapiEnv) raises:
        check_status(raw_async_destroy(b, env, self.value))

    ## make_callback0 — call a JS function with no arguments in this context
    def make_callback0(
        self,
        b: Bindings,
        env: NapiEnv,
        recv: NapiValue,
        func: NapiValue,
    ) raises -> NapiValue:
        var result = NapiValue()
        check_status(raw_make_callback(b, env, self.value, recv, func, 0,
            OpaquePointer[ImmutAnyOrigin](),
            UnsafePointer(to=result).bitcast[NoneType]()))
        return result

    ## make_callback1 — call a JS function with one argument in this context
    def make_callback1(
        self,
        b: Bindings,
        env: NapiEnv,
        recv: NapiValue,
        func: NapiValue,
        arg0: NapiValue,
    ) raises -> NapiValue:
        var result = NapiValue()
        var argv_ptr: OpaquePointer[ImmutAnyOrigin] = UnsafePointer(to=arg0).bitcast[NoneType]()
        check_status(raw_make_callback(b, env, self.value, recv, func, 1,
            argv_ptr,
            UnsafePointer(to=result).bitcast[NoneType]()))
        return result

    ## make_callback2 — call a JS function with two arguments in this context
    def make_callback2(
        self,
        b: Bindings,
        env: NapiEnv,
        recv: NapiValue,
        func: NapiValue,
        arg0: NapiValue,
        arg1: NapiValue,
    ) raises -> NapiValue:
        var result = NapiValue()
        var args = InlineArray[NapiValue, 2](fill=NapiValue())
        args[0] = arg0
        args[1] = arg1
        var argv_ptr: OpaquePointer[ImmutAnyOrigin] = UnsafePointer(to=args[0]).bitcast[NoneType]()
        check_status(raw_make_callback(b, env, self.value, recv, func, 2,
            argv_ptr,
            UnsafePointer(to=result).bitcast[NoneType]()))
        return result
