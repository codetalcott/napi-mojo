## fns.mojo — pure Mojo. No N-API here; the generator writes that part.
##
## Each function is named by `mojo_fn` in exports.toml. Struct types come from
## generated/structs.mojo, which the generator writes from [structs.*].

from generated.structs import ConfigData


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
