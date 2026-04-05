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
