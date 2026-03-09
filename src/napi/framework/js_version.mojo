## src/napi/framework/js_version.mojo — N-API and Node.js version detection
##
## Provides runtime version queries:
##   - get_napi_version(): highest N-API version supported
##   - get_node_version_fields(): Node.js major/minor/patch read directly
##
## Usage:
##   var napi_ver = get_napi_version(env)  # e.g., 9

from napi.types import NapiEnv, NapiNodeVersion
from napi.bindings import Bindings
from napi.raw import raw_get_version, raw_get_node_version
from napi.error import check_status

## get_napi_version — return the highest N-API version supported by this runtime
fn get_napi_version(env: NapiEnv) raises -> UInt32:
    var result: UInt32 = 0
    var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
    check_status(raw_get_version(env, result_ptr))
    return result

## get_node_version_ptr — return a pointer to the static NapiNodeVersion struct
##
## napi_get_node_version writes a const napi_node_version* into our out-param.
## Returns the raw pointer; caller reads fields via UnsafePointer offsets.
fn get_node_version_ptr(env: NapiEnv) raises -> UnsafePointer[UInt32, MutAnyOrigin]:
    # The API writes a pointer-to-struct into our out variable
    var ptr_val = OpaquePointer[MutAnyOrigin]()
    var out_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=ptr_val).bitcast[NoneType]()
    check_status(raw_get_node_version(env, out_ptr))
    # The struct starts with three UInt32 fields (major, minor, patch)
    # Cast to UInt32* for direct field access
    return ptr_val.bitcast[UInt32]()

# --- Bindings-aware overloads ---

fn get_napi_version(b: Bindings, env: NapiEnv) raises -> UInt32:
    var result: UInt32 = 0
    var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
    check_status(raw_get_version(b, env, result_ptr))
    return result

fn get_node_version_ptr(b: Bindings, env: NapiEnv) raises -> UnsafePointer[UInt32, MutAnyOrigin]:
    var ptr_val = OpaquePointer[MutAnyOrigin]()
    var out_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=ptr_val).bitcast[NoneType]()
    check_status(raw_get_node_version(b, env, out_ptr))
    return ptr_val.bitcast[UInt32]()
