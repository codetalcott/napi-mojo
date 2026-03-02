## src/napi/module.mojo — safe wrappers for module property registration
##
## Provides define_property(), a safe alternative to calling raw_define_properties
## directly. Wraps the raw call with check_status() so any N-API failure is
## immediately surfaced as a raised error rather than silently ignored.

from napi.types import NapiEnv, NapiValue, NapiPropertyDescriptor
from napi.raw import raw_define_properties
from napi.error import check_status

## define_property — register a single named property on the exports object
##
## This is the safe way to attach a method or value to the Node.js addon's
## exports. It registers exactly one NapiPropertyDescriptor at a time (avoids
## the InlineArray Copyable requirement for arrays of non-Copyable structs).
##
## Safety invariant: `desc.utf8name` must point to a string that remains alive
## for the duration of this call. Use a named `var` binding in the caller.
fn define_property(
    env: NapiEnv,
    exports: NapiValue,
    desc: NapiPropertyDescriptor,
) raises:
    # Take the address of the borrowed desc. The pointer is valid for the
    # duration of this function call (desc is alive in the caller's frame).
    var p: OpaquePointer[ImmutAnyOrigin] = UnsafePointer(to=desc).bitcast[NoneType]()
    var status = raw_define_properties(env, exports, 1, p)
    check_status(status)
