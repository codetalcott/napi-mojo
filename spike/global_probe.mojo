## spike/global_probe.mojo — THROWAWAY: module-level globals in a dlopen'd .node
##
## ===========================================================================
## VERDICT (2026-08-09, dev2026080905): DOES NOT COMPILE — and that IS the
## result. `var` at module scope errors with:
##
##     error: global variables are not supported; move this into a function
##     body or use 'comptime' to declare a constant
##
## So a process-global NapiBindings cache is impossible in today's Mojo, in
## both the main module and package modules. Consequences:
##   - The dual env-only/Bindings overload surface cannot be collapsed via a
##     global. The two viable alternatives, in preference order:
##     (a) thread the bindings pointer through the payload the context already
##         carries (async data struct, TSFN context, finalizer hint) — zero
##         dlsym, implemented for generated async completes in
##         scripts/generate-addon.mjs;
##     (b) claim napi_set_instance_data for a framework EnvSlot {bindings,
##         user_data} and layer the user-facing instance-data API over it —
##         one bootstrap dlsym per env-only-context call, but works for
##         except-blocks too. Bigger refactor of instance_data.mojo; deferred.
##   - Re-run this probe when a nightly changelog mentions global variables;
##     if it ever compiles and returns 7042, design (a)/(b) can be revisited.
## ===========================================================================
##
## Answers the question gating the process-global NapiBindings cache:
##
##   Can a module-level `var` with a TRIVIAL ZERO initializer be written at
##   napi_register_module_v1 time and read back from a later N-API callback,
##   in a shared lib loaded by Node via dlopen (no compiler-generated main())?
##
## Two variants, because they have different elaboration/storage stories:
##   1. g_main_slot — global in the MAIN module (eagerly checked)
##   2. global_pkg.state.g_pkg_slot — global in an IMPORTED PACKAGE module
##      (the lazily-elaborated kind, which is where NapiBindings lives)
##
## Run:
##   pixi run mojo build --emit shared-lib -I src spike/global_probe.mojo \
##     -o build/global_probe.dylib && mv build/global_probe.dylib build/global_probe.node
##   node -e "const p=require('./build/global_probe.node'); const v=p.readGlobals(); \
##     if (v !== 7042) throw new Error('globals broken: '+v); console.log('global probe OK:', v)"
##
## Expected: 7042 (g_main_slot=7 → thousands, g_pkg_slot=42 → units).
## If this ever regresses on a nightly, the global bindings cache design in
## src/napi/bindings.mojo is invalid — see publish_global_bindings there.

from napi.types import NapiEnv, NapiValue
from napi.module import register_method
from napi.framework.register import fn_ptr
from napi.framework.js_int64 import JsInt64
from global_pkg.state import set_pkg_slot, get_pkg_slot

var g_main_slot: Int = 0


def read_globals_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var combined = Int64(g_main_slot * 1000 + get_pkg_slot())
        return JsInt64.create(env, combined).value
    except:
        return NapiValue(unsafe_from_address=Int(0))


@export("napi_register_module_v1")
def register_module(env: NapiEnv, exports: NapiValue) abi("C") -> NapiValue:
    # Read-before-write check happens implicitly: if .bss zero-init didn't
    # hold, the slots would already be garbage and 7042 wouldn't come back.
    g_main_slot = 7
    set_pkg_slot(42)
    try:
        var cb = read_globals_fn
        register_method(env, exports, "readGlobals", fn_ptr(cb))
        _ = cb
    except:
        pass
    return exports
