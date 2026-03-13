## src/lib.mojo — napi-mojo module entry point (thin orchestrator)
##
## Allocates NapiBindings, creates ModuleBuilder, then delegates all
## callback registration to per-feature addon modules.

from std.memory import alloc
from napi.types import NapiEnv, NapiValue
from napi.bindings import NapiBindings, Bindings, init_bindings
from napi.raw import raw_create_error, raw_fatal_exception
from napi.framework.js_string import JsString
from napi.framework.register import ModuleBuilder
from generated.callbacks import register_generated
from addon.primitives import register_primitives
from addon.collections import register_collections
from addon.async_ops import register_async
from addon.binary_ops import register_binary
from addon.class_counter import register_counter
from addon.class_animal import register_animal
from addon.function_ops import register_functions
from addon.ref_ops import register_refs
from addon.value_types import register_value_types
from addon.externals import register_externals
from addon.env_ops import register_env
from addon.misc_ops import register_misc
from addon.async_context_ops import register_async_context
from addon.convert_ops import register_convert

@export("napi_register_module_v1", ABI="C")
fn register_module(env: NapiEnv, exports: NapiValue) -> NapiValue:
    # Allocate and initialize NapiBindings — resolves all N-API symbols
    # once via a single OwnedDLHandle. The pointer is passed as callback
    # data to every registered function so callbacks can retrieve it cheaply.
    var bindings_ptr = alloc[NapiBindings](1)
    try:
        var bindings = NapiBindings()
        init_bindings(bindings)
        bindings_ptr.init_pointee_move(bindings^)
    except:
        bindings_ptr.free()
        return exports
    var cb_data = bindings_ptr.bitcast[NoneType]()

    try:
        var m = ModuleBuilder(env, exports, cb_data)
        register_generated(m)
        register_primitives(m)
        register_collections(m)
        register_async(m)
        register_binary(m)
        register_counter(m, bindings_ptr)
        register_animal(m)
        register_functions(m)
        register_refs(m)
        register_value_types(m)
        register_externals(m)
        register_env(m)
        register_misc(m)
        register_async_context(m)
        register_convert(m)
        m.flush()
    except:
        try:
            var null_code = NapiValue()
            var err_msg = JsString.create_literal(env, "napi-mojo: register_module failed")
            var err_val = NapiValue()
            var err_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=err_val).bitcast[NoneType]()
            _ = raw_create_error(env, null_code, err_msg.value, err_ptr)
            _ = raw_fatal_exception(env, err_val)
        except:
            pass

    return exports
