## src/napi/framework/js_mojo_array.mojo — zero-copy Float64Array output helper
##
## MojoFloat64Array allocates a Mojo heap buffer, lets you fill it (scalar or
## SIMD/vectorize), then wraps it in a JavaScript Float64Array with no copy.
## Node.js GC owns the memory after to_js() and frees it via finalizer when
## the Float64Array is collected.
##
## Usage:
##   var arr = MojoFloat64Array(n)
##   arr.ptr[i] = some_value   # scalar, or vectorize() over arr.ptr
##   return arr.to_js(b, env)  # returns Float64Array NapiValue
##
## After to_js() is called, do NOT call arr.ptr.unsafe_free() — GC owns the memory.
## If to_js() is never reached (error path), __del__ automatically frees the buffer.

from std.memory.alloc import unsafe_alloc
from napi.types import NapiEnv, NapiValue
from napi.bindings import Bindings
from napi.raw import raw_create_external_arraybuffer
from napi.error import check_status
from napi.framework.js_typedarray import JsTypedArray


def _mojo_float64_finalizer(
    env: NapiEnv,
    data: OpaquePointer[MutAnyOrigin],
    hint: OpaquePointer[MutAnyOrigin],
):
    """GC finalizer: frees the Mojo-allocated Float64 heap buffer."""
    data.unsafe_bitcast[Float64]().unsafe_free()


struct MojoFloat64Array(Movable):
    """Zero-copy Float64 output array for N-API callbacks.

    Allocates a Mojo heap buffer that can be filled with scalar writes or
    SIMD vectorize(). Calling to_js() wraps it in a JS Float64Array without
    copying. The GC finalizer frees the buffer when JavaScript is done with it.

    Ownership safety: if to_js() is never called (e.g. exception before it),
    __del__ automatically frees the buffer to prevent leaks.
    """

    # Storage type is Untracked: an unsafe_alloc block whose ownership moves
    # to the GC finalizer on to_js(). Never a pointer to a Mojo local.
    var ptr: Pointer[Float64, MutUntrackedOrigin]
    var length: Int
    var _transferred: Bool

    def __init__(out self, length: Int):
        self.ptr = unsafe_alloc[Float64](length).unsafe_origin_cast[
            MutUntrackedOrigin
        ]()
        self.length = length
        self._transferred = False

    def __moveinit__(out self, deinit take: Self):
        self.ptr = take.ptr
        self.length = take.length
        self._transferred = take._transferred

    def __deinit__(deinit self):
        if not self._transferred:
            self.ptr.unsafe_free()

    ## to_js — transfer ownership to JS as a Float64Array (with cached bindings)
    def to_js(mut self, b: Bindings, env: NapiEnv) raises -> NapiValue:
        """Wrap buffer as Float64Array (zero-copy). GC finalizer owns memory after this.
        """
        var byte_len = UInt(self.length * 8)  # Float64 = 8 bytes
        var fin_ref = _mojo_float64_finalizer
        var fin_ptr = Pointer(to=fin_ref).unsafe_bitcast[
            OpaquePointer[MutAnyOrigin]
        ]()[]
        var ab = NapiValue(unsafe_from_address=Int(0))
        check_status(
            raw_create_external_arraybuffer(
                b,
                env,
                self.ptr.unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                byte_len,
                fin_ptr,
                OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0)),
                Pointer(to=ab).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        self._transferred = True  # GC finalizer now owns memory
        return JsTypedArray.create_float64(
            b, env, ab, 0, UInt(self.length)
        ).value
