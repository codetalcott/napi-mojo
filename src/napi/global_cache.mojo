## src/napi/global_cache.mojo — one process-lifetime slot, for the bootstrap symbol
##
## WHY THIS EXISTS
##
## Every napi-mojo callback begins by fetching its cached NapiBindings out of
## callback data, and reading callback data requires `napi_get_cb_info` — whose
## pointer cannot itself come from the cache it is fetching. So the env-only
## `raw_get_cb_info` ran `OwnedDLHandle()` + `get_symbol` on EVERY call.
##
## Measured, that bootstrap is ~346 ns/call (of which ~280 ns is dlsym itself;
## the Mojo wrapper adds ~66 ns and the String copy inside `get_symbol` only
## ~8 ns — bypassing the wrapper alone was never going to be the fix). Against
## napi-rs, napi-mojo showed a FLAT ~330 ns per-call delta across calls whose
## absolute cost varied 8x. The bootstrap was essentially the entire gap.
##
## HOW IT WORKS, AND WHY IT IS NOT "GLOBAL VARIABLES ARE SUPPORTED NOW"
##
## Mojo's *language surface* still has no module-level `var` — that hard error
## is real and `spike/global_probe.mojo` still records it. But the MLIR op
## underneath `builtin/globals.global_constant` has a mutable sibling,
## `pop.global_alloc`, which lowers to `llvm.mlir.global internal @<name>` — a
## zero-initialized, module-private slot in the data segment.
##
## `@no_inline` IS LOAD-BEARING. `pop.global_alloc` is marked `Pure`, so every
## inlined copy materialises its OWN global: without it the probe handed back
## sequential addresses 8 bytes apart and stores were lost. With it, one
## emission, one address. Do not remove it, and do not add `@always_inline`.
##
## WHY ONLY THE FUNCTION POINTER, NOT THE WHOLE `NapiBindings`
##
## Caching the Bindings struct here would be a real cross-env bug. Its
## `registry` field holds `NapiRef`s to class constructors, and a napi_ref is
## ENV-SPECIFIC: under `worker_threads` each env loads its own bindings, and a
## callback in env B could read env A's constructor refs. A resolved symbol
## address is process-image state and has no such problem, so that is all this
## file stores. Per-env bindings still travel through callback data exactly as
## before.
##
## FAILURE MODE: GRACEFUL BY CONSTRUCTION
##
## The slot is zero until something fills it. If a future toolchain stops
## honouring `@no_inline` here, each call site simply sees 0 and falls back to
## the dlsym path — the pre-existing behaviour. That is a performance
## regression, never a correctness one, which is why this needs no magic
## sentinel. `globalCacheActive()` in `src/addon/global_cache_ops.mojo` exports
## the state so a test can catch the silent regression.
##
## `__mlir_op` is an internal compiler interface with no stability guarantee,
## and `_get_kgen_string` is a private stdlib import. Both are deliberate: the
## fallback above is what makes the risk affordable.

from std.collections.string.string_span import _get_kgen_string


@no_inline
def _cb_info_slot() -> Pointer[Int, MutUntrackedOrigin]:
    """Return the module-private global slot holding `napi_get_cb_info`'s address.

    Zero-initialised (BSS) until `cache_cb_info_addr` fills it. `@no_inline` is
    required for the address to be stable — see this file's header.

    Returns:
        A pointer to the one-word slot for this module image.
    """
    return {
        _mlir_value = __mlir_op.`pop.global_alloc`[
            name = _get_kgen_string["napi_mojo_cb_info_addr"](),
            count = Int(1).__mlir_index__(),
            _type = Pointer[Int, MutUntrackedOrigin]._mlir_type,
            alignment = Int(8).__mlir_index__(),
        ]()
    }


def cached_cb_info_addr() -> Int:
    """Read the cached `napi_get_cb_info` address, or 0 if not yet resolved.

    Returns:
        The symbol address, or 0 meaning "resolve it the slow way".
    """
    return _cb_info_slot()[]


def cache_cb_info_addr(addr: Int):
    """Publish a resolved `napi_get_cb_info` address for subsequent calls.

    Racing threads write the same process-image address, and the store is a
    single aligned word, so no lock is needed.

    Args:
        addr: The resolved symbol address. Passing 0 is a no-op re-resolve.
    """
    _cb_info_slot()[] = addr


def global_cache_is_active() -> Bool:
    """Report whether the bootstrap symbol is being served from the global slot.

    False after a fresh load and True once any callback has run — unless the
    `@no_inline` guarantee has silently broken, which is exactly what
    `tests/global_cache.test.js` exists to catch.

    Returns:
        True if the slot is populated.
    """
    return _cb_info_slot()[] != 0
