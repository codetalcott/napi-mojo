## src/lib.mojo — napi-mojo module entry point (thin orchestrator)
##
## Allocates NapiBindings, creates ModuleBuilder, then delegates all
## callback registration to per-feature addon modules.

from std.memory.alloc import unsafe_alloc
from napi.types import NapiEnv, NapiValue
from napi.bindings import NapiBindings, Bindings, init_bindings
from napi.error import throw_js_error
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
from addon.typed_helpers_ops import register_typed_helpers
from addon.runtime_ops import register_runtime_ops


@export("napi_register_module_v1")
def register_module(env: NapiEnv, exports: NapiValue) abi("C") -> NapiValue:
    # Allocate and initialize NapiBindings — resolves all N-API symbols
    # once via a single OwnedDLHandle. The pointer is passed as callback
    # data to every registered function so callbacks can retrieve it cheaply.
    var bindings_ptr = unsafe_alloc[NapiBindings](1)
    try:
        var bindings = NapiBindings()
        init_bindings(bindings)
        bindings_ptr.unsafe_write(bindings^)
    except:
        bindings_ptr.unsafe_free()
        # Symbol resolution is all-or-nothing, so a single missing symbol
        # (e.g. a Node.js older than the N-API v10 surface) lands here.
        # Leave a pending JS error so require() throws with a real message
        # instead of silently returning an empty exports object.
        # throw_js_error uses the env-only OwnedDLHandle path — safe even
        # with no bindings, and napi_throw_error is a base (v1) symbol.
        throw_js_error(
            env,
            "napi-mojo: failed to resolve N-API symbols (Node.js >= 22.12 required)",
        )
        return exports
    # as_unsafe_any_origin() spells out the widening that used to happen
    # implicitly: the heap pointer's concrete origin is discarded to reach the
    # MutAnyOrigin that C-FFI signatures fix. dev2026072306 removed the
    # implicit conversion, so this must now be explicit.
    var cb_data = bindings_ptr.unsafe_bitcast[NoneType]().as_unsafe_any_origin()

    try:
        var m = ModuleBuilder(env, exports, cb_data)
        register_generated(m)
        register_primitives(m)
        register_collections(m)
        register_async(m)
        register_binary(m)
        # register_counter writes the ClassRegistry into bindings.registry;
        # register_functions' newCounterFromRegistry reads it. The read side
        # null-checks (function_ops.mojo), so a reorder fails as a JS error
        # rather than a segfault — but keep counter before functions anyway.
        register_counter(m, bindings_ptr.as_unsafe_any_origin())
        register_animal(m)
        register_functions(m)
        register_refs(m)
        register_value_types(m)
        register_externals(m)
        register_env(m)
        register_misc(m)
        register_async_context(m)
        register_convert(m)
        register_typed_helpers(m)
        register_runtime_ops(m)
        m.flush()
    except:
        # Registration failed AFTER init_bindings succeeded, so cached
        # bindings are available for the error report.
        try:
            var b = bindings_ptr.unsafe_origin_cast[MutUntrackedOrigin]()
            var null_code = NapiValue(unsafe_from_address=Int(0))
            var err_msg = JsString.create_literal(
                b, env, "napi-mojo: register_module failed"
            )
            var err_val = NapiValue(unsafe_from_address=Int(0))
            var err_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
                to=err_val
            ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
            _ = raw_create_error(b, env, null_code, err_msg.value, err_ptr)
            _ = raw_fatal_exception(b, env, err_val)
        except:
            pass

    return exports
