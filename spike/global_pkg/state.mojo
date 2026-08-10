## spike/global_pkg/state.mojo — package-module global for the global_probe spike.
##
## The question this half answers: does a module-level `var` in an IMPORTED
## PACKAGE module (the lazily-elaborated kind — where NapiBindings lives)
## behave in a dlopen'd shared lib with no compiler-generated main()?
## Trivial zero initializer on purpose: zero-init data lands in .bss, which
## the loader zeroes with no runtime initializer needed. A non-trivial
## initializer would need global-ctor support at dlopen time — NOT probed
## here, and not needed for the bindings cache (written at registration).

var g_pkg_slot: Int = 0


def set_pkg_slot(v: Int):
    g_pkg_slot = v


def get_pkg_slot() -> Int:
    return g_pkg_slot
