## src/napi/module.mojo — safe wrappers for module property registration
##
## Provides define_property() and register_method() for attaching properties
## to the addon's exports object. Both wrap raw N-API calls with check_status()
## so any failure is immediately surfaced as a raised error.

from napi.types import NapiEnv, NapiValue, NapiPropertyDescriptor
from napi.bindings import Bindings
from napi.raw import raw_define_properties
from napi.error import check_status


## define_property — register a single named property on the exports object
##
## This is the safe way to attach a method or value to the Node.js addon's
## exports. It registers one NapiPropertyDescriptor at a time for simpler
## pointer and lifetime management.
##
## NapiPropertyDescriptor is Copyable (all fields are pointer/UInt32), so
## `desc` is passed by value. `UnsafePointer(to=desc)` points to the local
## copy, which is alive for the duration of this call.
##
## Safety invariant: `desc.utf8name` must point to a string that remains alive
## for the duration of this call. Use a named `var` binding in the caller.
def define_property(
    env: NapiEnv,
    exports: NapiValue,
    desc: NapiPropertyDescriptor,
) raises:
    # Take the address of the local desc copy. The pointer is valid for the
    # duration of this function call (desc lives in this stack frame).
    var p: OpaquePointer[ImmutAnyOrigin] = UnsafePointer(to=desc).bitcast[
        NoneType
    ]()
    var status = raw_define_properties(env, exports, 1, p)
    check_status(status)


## register_method — register a named method on the exports object
##
## Convenience wrapper that constructs the NapiPropertyDescriptor, fills in
## utf8name and method, and calls define_property. Reduces per-property
## boilerplate from ~9 lines to a single call.
##
## `name`:       StringLiteral (static lifetime, ASAP-safe) for the JS property name.
## `method_ptr`: The function pointer as OpaquePointer[MutAnyOrigin]. Extract from
##               a Mojo function reference:
##                 var fn_ref = my_fn
##                 register_method(env, exports, "myFn",
##                     UnsafePointer(to=fn_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[])
def register_method(
    env: NapiEnv,
    exports: NapiValue,
    name: StringLiteral,
    method_ptr: OpaquePointer[MutAnyOrigin],
) raises:
    var desc = NapiPropertyDescriptor()
    desc.utf8name = name.unsafe_ptr().bitcast[NoneType]()
    desc.method = method_ptr
    desc.attributes = 0
    define_property(env, exports, desc)


# --- Bindings-aware overloads ---


def define_property(
    b: Bindings,
    env: NapiEnv,
    exports: NapiValue,
    desc: NapiPropertyDescriptor,
) raises:
    var p: OpaquePointer[ImmutAnyOrigin] = UnsafePointer(to=desc).bitcast[
        NoneType
    ]()
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
    desc.utf8name = name.unsafe_ptr().bitcast[NoneType]()
    desc.method = method_ptr
    desc.attributes = 0
    define_property(b, env, exports, desc)
