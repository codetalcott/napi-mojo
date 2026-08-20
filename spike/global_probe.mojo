## spike/global_probe.mojo — THROWAWAY: module-level globals in a dlopen'd .node
##
## ===========================================================================
## VERDICT (2026-08-09, dev2026080905): `var` at module scope DOES NOT COMPILE:
##
##     error: global variables are not supported; move this into a function
##     body or use 'comptime' to declare a constant
##
## That is still true. But the conclusion this file drew from it — "a
## process-global NapiBindings cache is impossible in today's Mojo" — was
## WRONG, and stood for the life of this file until it was measured.
##
## SUPERSEDED (2026-08-20, Mojo 1.0.0): the LANGUAGE SURFACE has no global
## `var`; the MLIR layer underneath has `pop.global_alloc`, the mutable sibling
## of the op behind `builtin/globals.global_constant`. It lowers to
## `llvm.mlir.global internal @<name>` — a zero-initialised, module-private
## slot in the data segment. `src/napi/global_cache.mojo` uses it to hold the
## `napi_get_cb_info` address, which removed ~346 ns from EVERY callback and
## took bench/napi-rs from 3.95x slower to 0.42x.
##
## Verified: stable address across call sites, across a `-I` package boundary,
## and across separate JS->Mojo callback entries on later event-loop ticks.
## `@no_inline` on the accessor is load-bearing — the op is `Pure`, so each
## inlined copy otherwise materialises its own global.
##
## Only the symbol ADDRESS is cached, never the NapiBindings struct: its
## `registry` holds env-specific napi_refs, so sharing it across envs
## (worker_threads) would be a real bug.
##
## This probe is kept because the `var` result is still the honest answer to
## "does Mojo have global variables" — and as a reminder that "the language
## cannot express X" is not the same as "X is impossible". Re-run it if a
## changelog ever mentions global variables; a first-class one would be
## preferable to an internal MLIR op with no stability guarantee.
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
