## fns.mojo — Pure Mojo functions (no N-API dependencies)
##
## The code generator wraps these with type-checked N-API callbacks.
## Each function is referenced by name in exports.toml via `mojo_fn`.

from std.collections import Optional
from generated.structs import ServerConfigData


def greet_pure(name: String) -> String:
    return "Hello, " + name + "!"


def safe_divide_pure(a: Float64, b: Float64) -> Optional[Float64]:
    if b == 0.0:
        return None
    return a / b


def config_summary_pure(c: ServerConfigData) -> String:
    return c.host + ":" + String(Int(c.port))
