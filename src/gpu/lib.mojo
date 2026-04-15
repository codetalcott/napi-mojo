## src/gpu/lib.mojo — napi-mojo GPU addon entry point
##
## Separate from src/lib.mojo so GPU linkage doesn't taint the core CPU
## binary. Compiled into build/gpu.node and lazily required by index.js; on
## hosts without CUDA/Metal runtime support, require fails and the main
## export object simply doesn't include the GPU functions.
##
## Registers loadMatrixGpu, matmulHandle, searchHandle, releaseMatrixGpu.

from std.memory import alloc
from napi.types import NapiEnv, NapiValue
from napi.bindings import NapiBindings, init_bindings
from napi.raw import raw_create_error, raw_fatal_exception
from napi.framework.js_string import JsString
from napi.framework.register import ModuleBuilder
from addon.gpu_linalg import register_gpu_linalg


@export("napi_register_module_v1", ABI="C")
def register_module(env: NapiEnv, exports: NapiValue) -> NapiValue:
    var bindings_ptr = alloc[NapiBindings](1)
    try:
        var bindings = NapiBindings()
        init_bindings(bindings)
        bindings_ptr.init_pointee_move(bindings^)
    except:
        bindings_ptr.free()
        return exports
    var cb_data = bindings_ptr.bitcast[NoneType]()

    try:
        var m = ModuleBuilder(env, exports, cb_data)
        register_gpu_linalg(m, bindings_ptr)
        m.flush()
    except:
        try:
            var null_code = NapiValue()
            var err_msg = JsString.create_literal(
                env, "napi-mojo gpu: register_module failed"
            )
            var err_val = NapiValue()
            var err_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
                to=err_val
            ).bitcast[NoneType]()
            _ = raw_create_error(env, null_code, err_msg.value, err_ptr)
            _ = raw_fatal_exception(env, err_val)
        except:
            pass

    return exports
