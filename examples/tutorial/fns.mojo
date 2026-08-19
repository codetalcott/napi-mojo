## fns.mojo — pure Mojo. No N-API here; the generator writes that part.
##
## Each function is named by `mojo_fn` in exports.toml. Struct types come from
## generated/structs.mojo, which the generator writes from [structs.*].

from generated.structs import ConfigData, TallyStateData
from napi.framework.js_mojo_array import MojoFloat64Array


def greet_pure(name: String) -> String:
    return "Hello, " + name + "!"


def add_pure(a: Float64, b: Float64) -> Float64:
    return a + b


## Returning Optional[T] is what makes the declared `number?` honest: the
## generated callback returns JS null for None.
def safe_divide_pure(a: Float64, b: Float64) -> Optional[Float64]:
    if b == 0.0:
        return None
    return a / b


def describe_config_pure(c: ConfigData) -> String:
    var summary = c.host + ":" + String(Int(c.port))
    if c.verbose:
        return summary + " (verbose)"
    return summary


## The Span points into the JS engine's buffer and is valid only for the
## duration of this call. MojoFloat64Array allocates the output; to_js hands
## that allocation to JS, whose GC frees it.
def scale_vec(v: Span[Float64, MutAnyOrigin], k: Float64) -> MojoFloat64Array:
    var out = MojoFloat64Array(len(v))
    for i in range(len(v)):
        out.ptr[unsafe_offset=i] = v[i] * k
    return out^


## Arrays of structs come free once the struct exists: the generated struct
## implements ToJsValue/FromJsValue, and the parametric converters are generic
## over those traits.
def verbose_only(cs: List[ConfigData]) -> List[ConfigData]:
    var out = List[ConfigData]()
    for i in range(len(cs)):
        if cs[i].verbose:
            out.append(ConfigData(copy=cs[i]))
    return out^


## Native class state. The generator hands each member the unwrapped struct;
## a mutating method takes it `mut`, a getter borrows it.
def tally_new(initial: Float64) -> TallyStateData:
    return TallyStateData(initial)


def tally_add(mut s: TallyStateData, n: Float64) -> Float64:
    s.total += n
    return s.total


def tally_total(s: TallyStateData) -> Float64:
    return s.total


## A nullable argument arrives as Optional[T]: None for JS null or undefined,
## a converted value otherwise. A wrong type never reaches here.
def greet_maybe(name: Optional[String]) -> String:
    if name:
        return "Hello, " + name.value() + "!"
    return "Hello, whoever you are!"
