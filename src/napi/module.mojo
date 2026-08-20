## src/napi/module.mojo — safe wrappers for module property registration
##
## Provides define_property() and register_method() for attaching properties
## to the addon's exports object. Both wrap raw N-API calls with check_status()
## so any failure is immediately surfaced as a raised error.

from napi.types import NapiEnv, NapiValue, NapiPropertyDescriptor
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
    method_ptr: NapiStore,
) raises:
    var desc = NapiPropertyDescriptor()
    desc.utf8name = name.unsafe_ptr().unsafe_bitcast[
        NoneType
    ]().unsafe_origin_cast[ImmutUntrackedOrigin]()
    desc.method = method_ptr
    desc.attributes = 0
    define_property(b, env, exports, desc)
