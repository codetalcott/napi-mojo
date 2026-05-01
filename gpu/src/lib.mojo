## gpu/src/lib.mojo — @napi-mojo/gpu addon entry point
##
## Compiled into gpu/build/gpu.node. Separate from napi-mojo's CPU addon
## so GPU runtime linkage doesn't taint the CPU binary — hosts without
## CUDA/Metal won't have this .node file at all and the CPU package
## continues to work.
##
## This module owns one process-lifetime `GpuModuleData` (allocated on
## the heap, never freed). It carries:
##   * NapiBindings for cached N-API symbols
##   * a DeviceContext (or a placeholder if GPU init failed)
##   * a pointer to the MatrixRegistry
##
## Per-callback access flows through `ModuleBuilder`'s cb_data; we point
## that at the GpuModuleData. Because GpuModuleData puts NapiBindings as
## its first field, downstream code that calls `CbArgs.get_bindings(...)`
## works unchanged.

from std.memory import alloc
from std.gpu.host import DeviceContext
from napi.types import NapiEnv, NapiValue
from napi.bindings import init_bindings
from napi.raw import raw_create_error, raw_fatal_exception
from napi.framework.js_string import JsString
from napi.framework.register import ModuleBuilder

from module_data import GpuModuleData
from registry import MatrixRegistry
from ops.load_matrix import register_load_matrix


@export("napi_register_module_v1", ABI="C")
def register_module(env: NapiEnv, exports: NapiValue) -> NapiValue:
    var module_ptr = alloc[GpuModuleData](1)

    # Build the heap pointee in a local first, then move it into the slot.
    # Failures during init_bindings or DeviceContext construction need to
    # leave us in a sensible state: if N-API symbol resolution itself fails
    # we have no way to even throw a JS error, so just return early.
    var module = GpuModuleData()
    try:
        init_bindings(module.bindings)
    except:
        module_ptr.free()
        return exports

    # Try to bring up a DeviceContext. Failure is the no-GPU-on-this-host
    # case — registration still succeeds (so `require()` on JS side works)
    # but every op throws a clear "no GPU" error when called.
    try:
        module.ctx = Optional[DeviceContext](DeviceContext())
    except:
        module.ctx = Optional[DeviceContext](None)

    # Heap-allocate the registry. Process-lifetime; never freed.
    var registry_ptr = alloc[MatrixRegistry](1)
    registry_ptr.init_pointee_move(MatrixRegistry())
    module.registry = registry_ptr

    module_ptr.init_pointee_move(module^)
    var cb_data = module_ptr.bitcast[NoneType]()

    try:
        var m = ModuleBuilder(env, exports, cb_data)
        register_load_matrix(m)
        m.flush()
    except:
        try:
            var null_code = NapiValue()
            var err_msg = JsString.create_literal(
                env, "@napi-mojo/gpu: register_module failed"
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
