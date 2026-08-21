## spike/keepalive_probe.mojo — the counterfactual behind src/napi/keepalive.mojo
##
## docs/plan-origin-migration.md prescribes `_ = x^` (a move-discard) to keep a
## local's stack slot alive across an N-API call. That is correct for a type
## with something to move — a `String`, a `List` — and a NO-OP for a trivially
## register-passable one, which is what nearly every slot in this framework is:
## `UInt` argc, `Bool` copied, `Int32` sign, and every `OpaquePointer` alias
## including `NapiValue`. The compiler says so itself when it sees `_ = slot^`
## below:
##
##     warning: transfer from a value of trivial register type 'Int' has no
##     effect and can be removed
##
## That warning is expected output from this file, not a defect in it.
##
## Both functions here do the same thing: take a local's address, launder it
## through the bitcast/widen pair every raw_* wrapper uses, hand it to an
## opaque consumer, and then try to keep the slot alive. Compare the emitted
## IR (scripts/check-keepalive-barrier.mjs does this in CI):
##
##   without_pin:  ret i64 %0                    <- the alloca is GONE
##   with_pin:     alloca ... asm sideeffect ""  <- slot survives the barrier
##
## If N-API were writing through that pointer, `without_pin` would be writing
## into a slot the compiler has already reclaimed. This is the whole argument
## for `pin_across_ffi`, and it is checked rather than asserted because the
## alternative — waiting for a crash — is exactly what the plan document warns
## produces silent corruption instead of a symptom.
##
## Build:
##   pixi run mojo build --emit llvm -I src spike/keepalive_probe.mojo -o probe.ll

from napi.keepalive import pin_across_ffi


## with_pin — slot pinned with the real barrier. The alloca must survive.
@export("keepalive_probe_with_pin")
def with_pin(n: Int) abi("C") -> Int:
    var slot: Int = 0
    var p = Pointer(to=slot).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
    _ = Int(p)  # stand-in for the FFI call that would read/write the slot
    pin_across_ffi(slot)
    return n


## without_pin — the same slot, kept with the move-discard the plan prescribed.
## Emits the "no effect and can be removed" warning, and loses its alloca.
@export("keepalive_probe_without_pin")
def without_pin(n: Int) abi("C") -> Int:
    var slot: Int = 0
    var p = Pointer(to=slot).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
    _ = Int(p)
    _ = slot^
    return n
