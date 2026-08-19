## src/addon/struct_fns.mojo — pure Mojo functions that use generated struct types
##
## These functions import from generated.callbacks for struct definitions.
## Kept separate from user_fns.mojo to avoid circular imports
## (callbacks.mojo imports user_fns.mojo, struct_fns.mojo imports callbacks.mojo).

from generated.structs import ConfigData


## echo_config_pure — pass a struct through unchanged (round-trip test)
def echo_config_pure(c: ConfigData) -> ConfigData:
    return ConfigData(copy=c)


## config_summary_pure — extract fields and return a computed string
def config_summary_pure(c: ConfigData) -> String:
    return c.host + ":" + String(Int(c.port))


## --- Tally: the pure half of a native-state class ---
##
## The generator wraps a heap TallyStateData onto each JS instance and hands
## every member the unwrapped state. Mutating members take it `mut`; static
## methods take no state at all, because there is no instance behind them.

from generated.structs import TallyStateData


## tally_new — the constructor's mojo_fn builds the state that gets wrapped
def tally_new(label: String, initial: Float64) -> TallyStateData:
    return TallyStateData(initial, label.copy())


## tally_add — mutate through `mut` and return the running total
def tally_add(mut s: TallyStateData, n: Float64) -> Float64:
    s.total += n
    return s.total


## tally_total — getter over borrowed state
def tally_total(s: TallyStateData) -> Float64:
    return s.total


## tally_set_total — setter: mutates, returns nothing
def tally_set_total(mut s: TallyStateData, n: Float64):
    s.total = n


## tally_label — proves a String field survives the wrap/unwrap round trip
def tally_label(s: TallyStateData) -> String:
    return s.label.copy()


## tally_zero — static: no state parameter
def tally_zero() -> Float64:
    return 0.0


## tally_combine — static with two args
def tally_combine(a: Float64, b: Float64) -> Float64:
    return a + b


## tally_parse_total — static returning Optional[T] -> `number | null`
def tally_parse_total(text: String) -> Optional[Float64]:
    if text == "zero":
        return Optional(0.0)
    if text == "one":
        return Optional(1.0)
    return None
