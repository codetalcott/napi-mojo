## gpu/src/module_data.mojo — per-module-load state for the GPU addon
##
## The cb_data passed to N-API callbacks points to a `GpuModuleData`
## allocated once in `napi_register_module_v1`. Layout puts NapiBindings
## first so callbacks that only want bindings can bitcast to NapiBindings*
## with no offset (preserves CbArgs.get_bindings as-is).
##
## ## Fields
##
##  * `bindings` — the standard NapiBindings (142 cached N-API fn ptrs).
##    First field by convention so cb_data is also NapiBindings*.
##
##  * `ctx` — `Optional[DeviceContext]`. None means GPU init failed (no
##    GPU on this host); ops should throw a clear "no GPU available"
##    error when the value is None.
##
##  * `registry` — pointer to the heap-allocated MatrixRegistry. All
##    handle storage lives there.

from std.gpu.host import DeviceContext
from napi.bindings import NapiBindings
from registry import MatrixRegistry


struct GpuModuleData(Movable):
    var bindings: NapiBindings
    var ctx: Optional[DeviceContext]
    var registry: UnsafePointer[MatrixRegistry, MutAnyOrigin]

    def __init__(out self):
        self.bindings = NapiBindings()
        self.ctx = Optional[DeviceContext](None)
        self.registry = UnsafePointer[
            MatrixRegistry, MutAnyOrigin
        ].unsafe_dangling()

    def __moveinit__(out self, deinit take: Self):
        self.bindings = take.bindings^
        self.ctx = take.ctx^
        self.registry = take.registry
