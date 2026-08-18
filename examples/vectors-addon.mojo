## examples/vectors-addon.mojo — SIMD + parallel vector similarity addon
##
## Demonstrates Mojo's SIMD vectorize() and parallelize() for high-performance
## numerical computation on Float64Arrays. Reads directly from JS TypedArray
## memory — zero copies. Automatically parallelizes across CPU cores for
## vectors > 4096 elements.
##
## Build:  cd /path/to/napi-mojo
##         pixi run mojo build --emit shared-lib -I src examples/vectors-addon.mojo -o build/vectors.node
## Run:    node examples/vectors.js

from std.algorithm.functional import vectorize
from std.sys import simd_width_of
from std.math import sqrt
from std.memory.alloc import unsafe_alloc

from napi.types import NapiEnv, NapiValue
from napi.bindings import NapiBindings, init_bindings
from napi.error import throw_js_error
from napi.framework.js_number import JsNumber
from napi.framework.js_typedarray import JsTypedArray
from napi.framework.js_mojo_array import MojoFloat64Array
from napi.framework.args import CbArgs
from napi.framework.register import fn_ptr, ModuleBuilder
from napi.framework.runtime import init_async_runtime, parallelize_safe


# --- SIMD + parallel core ----------------------------------------------------
# Operates directly on raw Float64 pointers from TypedArray memory.
# No copies — reads the JS engine's buffer in place.
# ARM NEON: simd_width = 2 (128-bit), x86 AVX2: simd_width = 4 (256-bit)
# Parallelizes across cores for large vectors (> 4096 elements).

comptime PARALLEL_THRESHOLD = 4096
comptime NUM_WORKERS = 4


def _vectorized_dot(
    a: Pointer[Float64, MutAnyOrigin], b: Pointer[Float64, MutAnyOrigin], start: Int, end: Int
) -> Float64:
    var result: Float64 = 0.0

    def compute[width: Int](offset: Int) {mut result, imm a, imm b, imm start}:
        result += (
            a.unsafe_load[width=width](start + offset)
            * b.unsafe_load[width=width](start + offset)
        ).reduce_add()

    vectorize[simd_width_of[DType.float64]()](end - start, compute)
    return result


def _vectorized_euclid(
    a: Pointer[Float64, MutAnyOrigin], b: Pointer[Float64, MutAnyOrigin], start: Int, end: Int
) -> Float64:
    var sum_sq: Float64 = 0.0

    def compute[width: Int](offset: Int) {mut sum_sq, imm a, imm b, imm start}:
        var diff = a.unsafe_load[width=width](start + offset) - b.unsafe_load[width=width](
            start + offset
        )
        sum_sq += (diff * diff).reduce_add()

    vectorize[simd_width_of[DType.float64]()](end - start, compute)
    return sum_sq


def dot_product(
    a: Pointer[Float64, MutAnyOrigin], b: Pointer[Float64, MutAnyOrigin], size: Int
) -> Float64:
    if size < PARALLEL_THRESHOLD:
        return _vectorized_dot(a, b, 0, size)
    var chunk_size = size // NUM_WORKERS
    var partials = unsafe_alloc[Float64](NUM_WORKERS)

    def worker(wid: Int) capturing:
        var s = wid * chunk_size
        var e = s + chunk_size if wid < NUM_WORKERS - 1 else size
        partials[unsafe_offset=wid] = _vectorized_dot(a, b, s, e)

    parallelize_safe[worker](NUM_WORKERS)
    var result: Float64 = 0.0
    for i in range(NUM_WORKERS):
        result += partials[unsafe_offset=i]
    partials.unsafe_free()
    return result


def cosine_similarity(
    a: Pointer[Float64, MutAnyOrigin], b: Pointer[Float64, MutAnyOrigin], size: Int
) -> Float64:
    if size < PARALLEL_THRESHOLD:
        var dot: Float64 = 0.0
        var norm_a: Float64 = 0.0
        var norm_b: Float64 = 0.0

        def compute_st[width: Int](offset: Int) {mut dot, mut norm_a, mut norm_b, imm a, imm b}:
            var ca = a.unsafe_load[width=width](offset)
            var cb = b.unsafe_load[width=width](offset)
            dot += (ca * cb).reduce_add()
            norm_a += (ca * ca).reduce_add()
            norm_b += (cb * cb).reduce_add()

        vectorize[simd_width_of[DType.float64]()](size, compute_st)
        var denom = sqrt(norm_a) * sqrt(norm_b)
        if denom > 0.0:
            return dot / denom
        return 0.0

    # Parallel path
    var chunk_size = size // NUM_WORKERS
    var dots = unsafe_alloc[Float64](NUM_WORKERS)
    var norms_a = unsafe_alloc[Float64](NUM_WORKERS)
    var norms_b = unsafe_alloc[Float64](NUM_WORKERS)

    def worker(wid: Int) capturing:
        var s = wid * chunk_size
        var e = s + chunk_size if wid < NUM_WORKERS - 1 else size
        var local_dot: Float64 = 0.0
        var local_na: Float64 = 0.0
        var local_nb: Float64 = 0.0

        def compute[width: Int](offset: Int) {mut local_dot, mut local_na, mut local_nb, imm a, imm b, imm s}:
            var ca = a.unsafe_load[width=width](s + offset)
            var cb = b.unsafe_load[width=width](s + offset)
            local_dot += (ca * cb).reduce_add()
            local_na += (ca * ca).reduce_add()
            local_nb += (cb * cb).reduce_add()

        vectorize[simd_width_of[DType.float64]()](e - s, compute)
        dots[unsafe_offset=wid] = local_dot
        norms_a[unsafe_offset=wid] = local_na
        norms_b[unsafe_offset=wid] = local_nb

    parallelize_safe[worker](NUM_WORKERS)

    var dot: Float64 = 0.0
    var na: Float64 = 0.0
    var nb: Float64 = 0.0
    for i in range(NUM_WORKERS):
        dot += dots[unsafe_offset=i]
        na += norms_a[unsafe_offset=i]
        nb += norms_b[unsafe_offset=i]
    dots.unsafe_free()
    norms_a.unsafe_free()
    norms_b.unsafe_free()
    var denom = sqrt(na) * sqrt(nb)
    if denom > 0.0:
        return dot / denom
    return 0.0


def euclidean_distance(
    a: Pointer[Float64, MutAnyOrigin], b: Pointer[Float64, MutAnyOrigin], size: Int
) -> Float64:
    if size < PARALLEL_THRESHOLD:
        return sqrt(_vectorized_euclid(a, b, 0, size))
    var chunk_size = size // NUM_WORKERS
    var partials = unsafe_alloc[Float64](NUM_WORKERS)

    def worker(wid: Int) capturing:
        var s = wid * chunk_size
        var e = s + chunk_size if wid < NUM_WORKERS - 1 else size
        partials[unsafe_offset=wid] = _vectorized_euclid(a, b, s, e)

    parallelize_safe[worker](NUM_WORKERS)
    var sum_sq: Float64 = 0.0
    for i in range(NUM_WORKERS):
        sum_sq += partials[unsafe_offset=i]
    partials.unsafe_free()
    return sqrt(sum_sq)


# --- N-API callbacks ----------------------------------------------------------


def dot_product_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        if not JsTypedArray.is_typedarray(
            b, env, args[0]
        ) or not JsTypedArray.is_typedarray(b, env, args[1]):
            throw_js_error(env, "dotProduct requires two TypedArray arguments")
            return NapiValue(unsafe_from_address=Int(0))
        var ta_a = JsTypedArray(args[0])
        var ta_b = JsTypedArray(args[1])
        var len_a = Int(ta_a.length(b, env))
        var len_b = Int(ta_b.length(b, env))
        if len_a != len_b:
            throw_js_error(env, "vectors must have equal length")
            return NapiValue(unsafe_from_address=Int(0))
        var ptr_a = ta_a.data_ptr_float64(b, env)
        var ptr_b = ta_b.data_ptr_float64(b, env)
        return JsNumber.create(b, env, dot_product(ptr_a, ptr_b, len_a)).value
    except:
        throw_js_error(env, "dotProduct failed")
        return NapiValue(unsafe_from_address=Int(0))


def cosine_similarity_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        if not JsTypedArray.is_typedarray(
            b, env, args[0]
        ) or not JsTypedArray.is_typedarray(b, env, args[1]):
            throw_js_error(
                env, "cosineSimilarity requires two TypedArray arguments"
            )
            return NapiValue(unsafe_from_address=Int(0))
        var ta_a = JsTypedArray(args[0])
        var ta_b = JsTypedArray(args[1])
        var len_a = Int(ta_a.length(b, env))
        var len_b = Int(ta_b.length(b, env))
        if len_a != len_b:
            throw_js_error(env, "vectors must have equal length")
            return NapiValue(unsafe_from_address=Int(0))
        var ptr_a = ta_a.data_ptr_float64(b, env)
        var ptr_b = ta_b.data_ptr_float64(b, env)
        return JsNumber.create(
            b, env, cosine_similarity(ptr_a, ptr_b, len_a)
        ).value
    except:
        throw_js_error(env, "cosineSimilarity failed")
        return NapiValue(unsafe_from_address=Int(0))


def euclidean_distance_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        if not JsTypedArray.is_typedarray(
            b, env, args[0]
        ) or not JsTypedArray.is_typedarray(b, env, args[1]):
            throw_js_error(
                env, "euclideanDistance requires two TypedArray arguments"
            )
            return NapiValue(unsafe_from_address=Int(0))
        var ta_a = JsTypedArray(args[0])
        var ta_b = JsTypedArray(args[1])
        var len_a = Int(ta_a.length(b, env))
        var len_b = Int(ta_b.length(b, env))
        if len_a != len_b:
            throw_js_error(env, "vectors must have equal length")
            return NapiValue(unsafe_from_address=Int(0))
        var ptr_a = ta_a.data_ptr_float64(b, env)
        var ptr_b = ta_b.data_ptr_float64(b, env)
        return JsNumber.create(
            b, env, euclidean_distance(ptr_a, ptr_b, len_a)
        ).value
    except:
        throw_js_error(env, "euclideanDistance failed")
        return NapiValue(unsafe_from_address=Int(0))


def normalize_vector_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    # Compute L2-normalized copy of a Float64Array (zero-copy output via MojoFloat64Array).
    # Raises if input is not a Float64Array. Output is owned by JS GC.
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        if not JsTypedArray.is_typedarray(b, env, arg0):
            throw_js_error(
                env, "normalizeVector requires a Float64Array argument"
            )
            return NapiValue(unsafe_from_address=Int(0))
        var ta = JsTypedArray(arg0)
        var n = Int(ta.length(b, env))
        var v_ptr = ta.data_ptr_float64(
            b, env
        )  # validates Float64Array + gets ptr in one call
        # Compute L2 norm via SIMD vectorize
        var norm_sq: Float64 = 0.0

        def compute_norm[width: Int](offset: Int) {mut norm_sq, imm v_ptr}:
            var x = v_ptr.unsafe_load[width=width](offset)
            norm_sq += (x * x).reduce_add()

        vectorize[simd_width_of[DType.float64]()](n, compute_norm)
        var norm = sqrt(norm_sq)
        if norm == 0.0:
            norm = 1.0
        # Allocate Mojo output buffer, fill, and hand to JS with no copy
        var out = MojoFloat64Array(n)
        var inv_norm = 1.0 / norm
        for i in range(n):
            out.ptr[unsafe_offset=i] = v_ptr[unsafe_offset=i] * inv_norm
        return out.to_js(b, env)  # __del__ frees buffer if to_js() raises
    except:
        throw_js_error(env, "normalizeVector failed")
        return NapiValue(unsafe_from_address=Int(0))


# --- Module entry point -------------------------------------------------------


@export("napi_register_module_v1")
def register_module(env: NapiEnv, exports: NapiValue) abi("C") -> NapiValue:
    # Initialize Mojo async runtime for parallelize() support
    try:
        init_async_runtime()
    except:
        pass

    var bindings_ptr = unsafe_alloc[NapiBindings](1)
    try:
        var bindings = NapiBindings()
        init_bindings(bindings)
        bindings_ptr.unsafe_write(bindings^)
    except:
        bindings_ptr.unsafe_free()
        throw_js_error(env, "vectors-addon: failed to resolve N-API symbols")
        return exports
    var cb_data = bindings_ptr.unsafe_bitcast[NoneType]().as_unsafe_any_origin()

    var dot_ref = dot_product_fn
    var cos_ref = cosine_similarity_fn
    var euc_ref = euclidean_distance_fn
    var norm_ref = normalize_vector_fn

    try:
        var m = ModuleBuilder(env, exports, cb_data)
        m.method("dotProduct", fn_ptr(dot_ref))
        m.method("cosineSimilarity", fn_ptr(cos_ref))
        m.method("euclideanDistance", fn_ptr(euc_ref))
        m.method("normalizeVector", fn_ptr(norm_ref))
        m.flush()
    except:
        pass

    return exports
