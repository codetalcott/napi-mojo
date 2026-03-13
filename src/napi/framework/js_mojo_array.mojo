## src/napi/framework/js_mojo_array.mojo — zero-copy Float64Array output helper
##
## MojoFloat64Array allocates a Mojo heap buffer, lets you fill it (scalar or
## SIMD/vectorize), then wraps it in a JavaScript Float64Array with no copy.
## Node.js GC owns the memory after to_js() and frees it via finalizer when
## the Float64Array is collected.
##
## Usage (with bindings — production addons):
##   var arr = MojoFloat64Array(n)
##   arr.ptr[i] = some_value   # scalar, or vectorize() over arr.ptr
##   return arr.to_js(b, env)  # returns Float64Array NapiValue
##
## Usage (no-bindings — simple/example addons):
##   return arr.to_js(env)
##
## After to_js() is called, do NOT call arr.ptr.free() — GC owns the memory.
## If to_js() is never reached (error path), __del__ automatically frees the buffer.

from std.memory import alloc
from napi.types import NapiEnv, NapiValue
from napi.bindings import Bindings
from napi.raw import raw_create_external_arraybuffer
from napi.error import check_status
from napi.framework.js_typedarray import JsTypedArray


fn _mojo_float64_finalizer(
    env: NapiEnv,
    data: OpaquePointer[MutAnyOrigin],
    hint: OpaquePointer[MutAnyOrigin],
):
    """GC finalizer: frees the Mojo-allocated Float64 heap buffer."""
    data.bitcast[Float64]().free()


struct MojoFloat64Array(Movable):
    """Zero-copy Float64 output array for N-API callbacks.

    Allocates a Mojo heap buffer that can be filled with scalar writes or
    SIMD vectorize(). Calling to_js() wraps it in a JS Float64Array without
    copying. The GC finalizer frees the buffer when JavaScript is done with it.

    Ownership safety: if to_js() is never called (e.g. exception before it),
    __del__ automatically frees the buffer to prevent leaks.
    """
    var ptr: UnsafePointer[Float64, MutAnyOrigin]
    var length: Int
    var _transferred: Bool

    fn __init__(out self, length: Int):
        self.ptr = alloc[Float64](length)
        self.length = length
        self._transferred = False

    fn __moveinit__(out self, deinit take: Self):
        self.ptr = take.ptr
        self.length = take.length
        self._transferred = take._transferred

    fn __del__(owned self):
        if not self._transferred:
            self.ptr.free()

    ## to_js — transfer ownership to JS as a Float64Array (with cached bindings)
    fn to_js(mut self, b: Bindings, env: NapiEnv) raises -> NapiValue:
        """Wrap buffer as Float64Array (zero-copy). GC finalizer owns memory after this."""
        var byte_len = UInt(self.length * 8)  # Float64 = 8 bytes
        var fin_ref = _mojo_float64_finalizer
        var fin_ptr = UnsafePointer(to=fin_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
        var ab = NapiValue()
        check_status(raw_create_external_arraybuffer(b, env,
            self.ptr.bitcast[NoneType](),
            byte_len,
            fin_ptr,
            OpaquePointer[MutAnyOrigin](),
            UnsafePointer(to=ab).bitcast[NoneType]()))
        self._transferred = True  # GC finalizer now owns memory
        return JsTypedArray.create_float64(b, env, ab, 0, UInt(self.length)).value

    ## to_js — transfer ownership to JS as a Float64Array (env-only overload)
    fn to_js(mut self, env: NapiEnv) raises -> NapiValue:
        """Wrap buffer as Float64Array (zero-copy). GC finalizer owns memory after this."""
        var byte_len = UInt(self.length * 8)
        var fin_ref = _mojo_float64_finalizer
        var fin_ptr = UnsafePointer(to=fin_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
        var ab = NapiValue()
        check_status(raw_create_external_arraybuffer(env,
            self.ptr.bitcast[NoneType](),
            byte_len,
            fin_ptr,
            OpaquePointer[MutAnyOrigin](),
            UnsafePointer(to=ab).bitcast[NoneType]()))
        self._transferred = True  # GC finalizer now owns memory
        return JsTypedArray.create_float64(env, ab, 0, UInt(self.length)).value
