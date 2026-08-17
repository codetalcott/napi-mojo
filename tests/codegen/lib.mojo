## tests/codegen/lib.mojo — entry module for the kitchen-sink compile target
##
## Mirrors examples/codegen/lib.mojo. Never loaded by Node: compiling it is
## the test — register_generated takes a reference to every generated callback,
## which forces Mojo to elaborate (type-check) every generated body.

from std.memory.alloc import unsafe_alloc
from napi.types import NapiEnv, NapiValue
from napi.bindings import NapiBindings, init_bindings
from napi.error import throw_js_error
from napi.framework.register import ModuleBuilder
from generated.callbacks import register_generated


@export("napi_register_module_v1")
def register_module(env: NapiEnv, exports: NapiValue) abi("C") -> NapiValue:
    var bindings_ptr = unsafe_alloc[NapiBindings](1)
    try:
        var bindings = NapiBindings()
        init_bindings(bindings)
        bindings_ptr.unsafe_write(bindings^)
    except:
        bindings_ptr.unsafe_free()
        throw_js_error(
            env,
            "kitchen-sink: failed to resolve N-API symbols",
        )
        return exports
    var cb_data = bindings_ptr.unsafe_bitcast[NoneType]().as_unsafe_any_origin()

    try:
        var m = ModuleBuilder(env, exports, cb_data)
        register_generated(m)
        m.flush()
    except:
        pass
    return exports
