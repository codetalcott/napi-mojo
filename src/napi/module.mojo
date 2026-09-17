## src/napi/module.mojo — safe wrappers for module property registration
##
## Provides define_property() and register_method() for attaching properties
## to the addon's exports object. Both wrap raw N-API calls with check_status()
## so any failure is immediately surfaced as a raised error.

from napi.types import (
    NapiEnv,
    NapiValue,
    NapiPropertyDescriptor,
    NapiStore,
    NAPI_PROPERTY_WRITABLE,
    NAPI_PROPERTY_ENUMERABLE,
    NAPI_PROPERTY_CONFIGURABLE,
)
from napi.bindings import Bindings
from napi.raw import raw_define_properties
from napi.error import check_status


# --- Bindings-aware overloads ---


def define_property(
    b: Bindings,
    env: NapiEnv,
    exports: NapiValue,
    desc: NapiPropertyDescriptor,
) raises:
    var p: OpaquePointer[ImmutAnyOrigin] = Pointer(to=desc).unsafe_bitcast[
        NoneType
    ]().as_unsafe_any_origin()
    var status = raw_define_properties(b, env, exports, 1, p)
    check_status(status)


def register_method(
    b: Bindings,
    env: NapiEnv,
    exports: NapiValue,
    name: StringLiteral,
    method_ptr: OpaquePointer[MutAnyOrigin],
) raises:
    var desc = NapiPropertyDescriptor()
    desc.utf8name = name.ptr().unsafe_bitcast[
        NoneType
    ]().unsafe_origin_cast[ImmUntrackedOrigin]()
    desc.method = method_ptr.unsafe_origin_cast[MutUntrackedOrigin]()
    # Module exports get ordinary JS object semantics — the same as
    # `exports.foo = fn` — not napi_default. With attributes 0 an export
    # is non-enumerable, non-writable AND non-configurable, so
    # Object.keys(addon) returned only the classes (registered elsewhere,
    # and enumerable), console.log(addon) showed
    # almost nothing, {...addon} lost every function, and assigning over
    # one silently did nothing. Two behaviours in one module, for no
    # reason. Class PROTOTYPE members deliberately keep 0: a JS class
    # method is non-enumerable, and matching that is correct.
    desc.attributes = (
        NAPI_PROPERTY_WRITABLE
        | NAPI_PROPERTY_ENUMERABLE
        | NAPI_PROPERTY_CONFIGURABLE
    )
    define_property(b, env, exports, desc)
