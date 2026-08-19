## lib.mojo — the only file that touches N-API directly: allocate
## NapiBindings once, register the generated callbacks, done. fns.mojo stays
## pure Mojo. `napi-mojo init` scaffolds this file; the tutorial does not
## change a line of it.

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
        # Leave a pending JS error so require() throws with a real message
        # instead of silently returning an empty exports object.
        throw_js_error(
            env,
            "addon: failed to resolve N-API symbols (Node.js >= 22.12 required)",
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
