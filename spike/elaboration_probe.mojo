## elaboration_probe.mojo — per-method elaboration spike
##
## PURPOSE: throwaway validation code, same role as ffi_probe.mojo. It states,
## runnably, the compiler behaviour that tests/compile/framework_coverage.mojo
## depends on. Re-run it after a Mojo nightly bump before trusting that target.
##
## THE PROBLEM IT PROBES:
##
##   Mojo elaborates `def` bodies in IMPORTED PACKAGE MODULES lazily, per
##   method. A method body containing a hard type error compiles, packages and
##   ships as long as nothing in the compiled graph calls that specific method.
##   napi-mojo 0.5.1 shipped four broken framework modules exactly this way,
##   with the build and 609 tests green (see 5161dfc). JsBigInt.to_int64 was
##   called, so it elaborated and was fine; JsBigInt.to_uint64 was called
##   nowhere, so its identical bug shipped.
##
##   The lazy/eager split is by MODULE ROLE, not by decorator: bodies in the
##   MAIN module (the .mojo file named on the mojo build command line) are
##   type-checked eagerly whether or not anything calls them. Bodies reached
##   through -I as an imported package are not. That is why the coverage
##   target must live in a main module that CALLS into src/napi/framework/,
##   and why this spike splits itself across two files — putting the planted
##   bug in the main module would prove nothing.
##
## QUESTIONS THIS ANSWERS:
##
##   1. Does an UNCALLED public method of an imported package module with a
##      hard type error compile clean? (negative control — if this ever fails,
##      the coverage target is unnecessary and should be deleted)
##   2. Does calling it from an @export-rooted main-module function force
##      elaboration, and therefore surface the error at build time — even
##      though the exported function is never actually invoked?
##   3. Does a CUSTOM @export name (not napi_register_module_v1) emit? The
##      coverage target deliberately uses a non-addon export name so its
##      artifact can never be dlopen'd by Node as an addon.
##
## The planted error is the exact bug class 5161dfc fixed: dev2026072306
## removed the implicit UnsafePointer -> MutAnyOrigin conversion, so a
## concrete-origin pointer handed to a C-FFI-shaped MutAnyOrigin parameter
## needs an explicit .as_unsafe_any_origin().
##
## HOW TO RUN:
##
##   # BUILD A — as checked in. MUST SUCCEED (answers Q1 and Q3).
##   pixi run mojo build --emit shared-lib -I spike spike/elaboration_probe.mojo \
##     -o build/elab_probe.dylib
##   nm -gU build/elab_probe.dylib | grep elaboration_probe_anchor
##
##   # BUILD B — uncomment the line marked BUILD B in anchor(). MUST FAIL
##   # inside Probe.broken (elab_pkg/probe_mod.mojo) with an origin-conversion
##   # diagnostic (answers Q2). Re-comment afterwards so the file stays green.

from elab_pkg.probe_mod import Probe, NapiEnv, NapiValue


@export("elaboration_probe_anchor")
def anchor(env: NapiEnv, exports: NapiValue) abi("C") -> NapiValue:
    ## Never invoked. Its only job is to root elaboration: everything it calls,
    ## transitively, must type-check for this build to succeed.
    _ = Probe.good(env)
    Probe.fixed(env)
    # Probe.broken(env)   ## BUILD B: uncomment — the build MUST now fail.
    return exports
