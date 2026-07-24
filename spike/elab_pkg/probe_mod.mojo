## spike/elab_pkg/probe_mod.mojo — the "framework module" half of the
## elaboration spike. Stands in for src/napi/framework/*.mojo: an IMPORTED
## package module, reached via -I, not the main module being compiled.
##
## The distinction matters and is the entire point of the spike. See
## spike/elaboration_probe.mojo for what each method is for.

comptime NapiEnv = OpaquePointer[MutAnyOrigin]
comptime NapiValue = OpaquePointer[MutAnyOrigin]


## Stands in for a raw N-API entry point: a C-FFI signature whose pointer
## parameter's origin is fixed at MutAnyOrigin and cannot be inferred from
## the caller.
def _sink(p: OpaquePointer[MutAnyOrigin]):
    _ = p


struct Probe:
    @staticmethod
    def good(env: NapiEnv) -> NapiValue:
        return env

    @staticmethod
    def broken(env: NapiEnv):
        ## Planted bug — missing `.as_unsafe_any_origin()` on the argument.
        ## Exactly the class 5161dfc fixed.
        var slot: Int = 0
        _sink(UnsafePointer(to=slot).bitcast[NoneType]())

    @staticmethod
    def fixed(env: NapiEnv):
        ## Same body, correctly widened — this is what the fix looks like.
        var slot: Int = 0
        _sink(UnsafePointer(to=slot).bitcast[NoneType]().as_unsafe_any_origin())
