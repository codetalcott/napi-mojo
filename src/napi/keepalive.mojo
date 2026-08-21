## src/napi/keepalive.mojo — pin a local's stack slot across an N-API FFI call
##
## THE HAZARD. Mojo destroys a value at its last *tracked* use (ASAP
## destruction), and the pointer handed to N-API is not one: forming it goes
## through `.unsafe_bitcast[NoneType]()` / `.as_unsafe_any_origin()`, which
## erase the origin tying the pointer back to the local. The framework is
## correct today only because `AnyOrigin` in every FFI signature silently
## extends that local's lifetime anyway. Removing the dependency on that
## implicit extension is what docs/plan-origin-migration.md is for; this is
## the tool it needs.
##
## WHICH SITES NEED IT — only locals with no tracked use *after* the call:
##
##   - argv buffers          N-API reads them DURING the call
##   - in/out `argc`         napi_get_cb_info writes it; the wrapper never
##                           reads it back
##   - ignored output slots  `data` from napi_create_buffer, `copied` from
##                           napi_create_external_string_latin1, ... napi
##                           writes through a pointer into a slot the wrapper
##                           discards. This is the dangerous class: corruption
##                           produces no symptom at the call site.
##
## A local that is returned, or read afterwards, already has a tracked use
## pinning it and needs nothing.
##
## WHY NOT `_ = x^`. The move-discard docs/plan-origin-migration.md prescribes
## is a genuine use only for a type with something to move. For a trivially
## register-passable type — `UInt`, `Bool`, `Int32`, `NapiValue` and every
## other `OpaquePointer` alias, i.e. nearly all of this population — the
## compiler rejects it outright:
##
##     warning: transfer from a value of trivial register type 'UInt' has no
##     effect and can be removed
##
## An idiom the compiler offers to delete is not a keep-alive.
##
## WHAT THIS DOES INSTEAD. `std.benchmark.keep` takes its argument as
## `ref [origin]` — a tracked use, so the lifetime cannot end before it — and
## passes the address into empty inline assembly declared `~{memory}` with
## `has_side_effect=True`. That is the canonical escape-plus-clobber barrier:
## the slot must exist, must hold whatever N-API wrote into it, and the
## barrier itself cannot be optimized away. It emits no instructions.
##
## COST. Nominally zero, and specifically zero here: it sits immediately after
## an opaque external call that already clobbers memory, so it forbids nothing
## the FFI call did not already forbid. Guarded by scripts/check-benchmark.mjs.
##
## Taking `ref [origin]` also means it works on a BORROWED parameter directly,
## so no "copy the register-passable param into an owned local first" dance is
## needed to pin an argv slot.

from std.benchmark import keep


@always_inline
def pin_across_ffi[T: AnyType, origin: Origin, //](ref [origin] value: T):
    """Keep `value`'s stack slot alive and intact across an N-API call.

    Place it immediately after the `check_status(raw_*(...))` whose N-API call
    reads or writes through a pointer derived from `value`. Only needed when
    `value` has no other use after that call — see this module's header for
    the three classes that qualify.

    Parameters:
        T: The type of the pinned value.
        origin: The origin of the pinned value.

    Args:
        value: The local whose stack slot must survive the FFI call.
    """
    keep(value)
