## examples/vectors-addon.mojo — SIMD + parallel vector similarity addon
##
## Demonstrates Mojo's SIMD vectorize() and parallelize() for high-performance
## numerical computation on Float64Arrays. Reads directly from JS TypedArray
## memory — zero copies. Automatically parallelizes across CPU cores for
## vectors > 4096 elements.
##
## Build:  cd /path/to/napi-mojo
##         mojo build --emit shared-lib -I src examples/vectors-addon.mojo -o build/vectors.dylib
##         mv build/vectors.dylib build/vectors.node   # macOS
## Run:    node examples/vectors.js

from algorithm.functional import vectorize, parallelize
from sys import simd_width_of
from math import sqrt
from memory import alloc

from napi.types import NapiEnv, NapiValue
from napi.error import throw_js_error
from napi.framework.js_number import JsNumber
from napi.framework.js_typedarray import JsTypedArray
from napi.framework.js_mojo_array import MojoFloat64Array
from napi.framework.args import CbArgs
from napi.framework.register import fn_ptr, ModuleBuilder
from napi.framework.runtime import init_async_runtime


# Note on API style: this example uses ModuleBuilder(env, exports) without a
# NapiBindings pointer, so callbacks use the no-bindings CbArgs overloads
# (get_one(env, info), get_two(env, info), etc.). This is intentional for a
# minimal example. Production addons should pass NapiBindings through
# ModuleBuilder to enable cached function pointers (zero per-call dlsym).
# See src/lib.mojo and the "Cached NapiBindings" section of CLAUDE.md.

# --- SIMD + parallel core ----------------------------------------------------
# Operates directly on raw Float64 pointers from TypedArray memory.
# No copies — reads the JS engine's buffer in place.
# ARM NEON: simd_width = 2 (128-bit), x86 AVX2: simd_width = 4 (256-bit)
# Parallelizes across cores for large vectors (> 4096 elements).

comptime PARALLEL_THRESHOLD = 4096
comptime NUM_WORKERS = 4


fn _vectorized_dot(
    a: UnsafePointer[Float64], b: UnsafePointer[Float64], start: Int, end: Int
) -> Float64:
    var result: Float64 = 0.0
    fn compute[width: Int](offset: Int) unified {mut}:
        result += (a.load[width=width](start + offset) * b.load[width=width](start + offset)).reduce_add()
    vectorize[simd_width_of[DType.float64]()](end - start, compute)
    return result


fn _vectorized_euclid(
    a: UnsafePointer[Float64], b: UnsafePointer[Float64], start: Int, end: Int
) -> Float64:
    var sum_sq: Float64 = 0.0
    fn compute[width: Int](offset: Int) unified {mut}:
        var diff = a.load[width=width](start + offset) - b.load[width=width](start + offset)
        sum_sq += (diff * diff).reduce_add()
    vectorize[simd_width_of[DType.float64]()](end - start, compute)
    return sum_sq


fn dot_product(
    a: UnsafePointer[Float64], b: UnsafePointer[Float64], size: Int
) -> Float64:
    if size < PARALLEL_THRESHOLD:
        return _vectorized_dot(a, b, 0, size)
    var chunk_size = size // NUM_WORKERS
    var partials = alloc[Float64](NUM_WORKERS)
    fn worker(wid: Int) capturing:
        var s = wid * chunk_size
        var e = s + chunk_size if wid < NUM_WORKERS - 1 else size
        partials[wid] = _vectorized_dot(a, b, s, e)
    parallelize[worker](NUM_WORKERS)
    var result: Float64 = 0.0
    for i in range(NUM_WORKERS):
        result += partials[i]
    partials.free()
    return result


fn cosine_similarity(
    a: UnsafePointer[Float64], b: UnsafePointer[Float64], size: Int
) -> Float64:
    if size < PARALLEL_THRESHOLD:
        var dot: Float64 = 0.0
        var norm_a: Float64 = 0.0
        var norm_b: Float64 = 0.0
        fn compute_st[width: Int](offset: Int) unified {mut}:
            var ca = a.load[width=width](offset)
            var cb = b.load[width=width](offset)
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
    var dots = alloc[Float64](NUM_WORKERS)
    var norms_a = alloc[Float64](NUM_WORKERS)
    var norms_b = alloc[Float64](NUM_WORKERS)
    fn worker(wid: Int) capturing:
        var s = wid * chunk_size
        var e = s + chunk_size if wid < NUM_WORKERS - 1 else size
        var local_dot: Float64 = 0.0
        var local_na: Float64 = 0.0
        var local_nb: Float64 = 0.0
        fn compute[width: Int](offset: Int) unified {mut}:
            var ca = a.load[width=width](s + offset)
            var cb = b.load[width=width](s + offset)
            local_dot += (ca * cb).reduce_add()
            local_na += (ca * ca).reduce_add()
            local_nb += (cb * cb).reduce_add()
        vectorize[simd_width_of[DType.float64]()](e - s, compute)
        dots[wid] = local_dot
        norms_a[wid] = local_na
        norms_b[wid] = local_nb
    parallelize[worker](NUM_WORKERS)

    var dot: Float64 = 0.0
    var na: Float64 = 0.0
    var nb: Float64 = 0.0
    for i in range(NUM_WORKERS):
        dot += dots[i]
        na += norms_a[i]
        nb += norms_b[i]
    dots.free()
    norms_a.free()
    norms_b.free()
    var denom = sqrt(na) * sqrt(nb)
    if denom > 0.0:
        return dot / denom
    return 0.0


fn euclidean_distance(
    a: UnsafePointer[Float64], b: UnsafePointer[Float64], size: Int
) -> Float64:
    if size < PARALLEL_THRESHOLD:
        return sqrt(_vectorized_euclid(a, b, 0, size))
    var chunk_size = size // NUM_WORKERS
    var partials = alloc[Float64](NUM_WORKERS)
    fn worker(wid: Int) capturing:
        var s = wid * chunk_size
        var e = s + chunk_size if wid < NUM_WORKERS - 1 else size
        partials[wid] = _vectorized_euclid(a, b, s, e)
    parallelize[worker](NUM_WORKERS)
    var sum_sq: Float64 = 0.0
    for i in range(NUM_WORKERS):
        sum_sq += partials[i]
    partials.free()
    return sqrt(sum_sq)


# --- N-API callbacks ----------------------------------------------------------

fn dot_product_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var args = CbArgs.get_two(env, info)
        if not JsTypedArray.is_typedarray(env, args[0]) or not JsTypedArray.is_typedarray(env, args[1]):
            throw_js_error(env, "dotProduct requires two TypedArray arguments")
            return NapiValue()
        var ta_a = JsTypedArray(args[0])
        var ta_b = JsTypedArray(args[1])
        var len_a = Int(ta_a.length(env))
        var len_b = Int(ta_b.length(env))
        if len_a != len_b:
            throw_js_error(env, "vectors must have equal length")
            return NapiValue()
        var ptr_a = ta_a.data_ptr_float64(env)
        var ptr_b = ta_b.data_ptr_float64(env)
        return JsNumber.create(env, dot_product(ptr_a, ptr_b, len_a)).value
    except:
        throw_js_error(env, "dotProduct failed")
        return NapiValue()


fn cosine_similarity_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var args = CbArgs.get_two(env, info)
        if not JsTypedArray.is_typedarray(env, args[0]) or not JsTypedArray.is_typedarray(env, args[1]):
            throw_js_error(env, "cosineSimilarity requires two TypedArray arguments")
            return NapiValue()
        var ta_a = JsTypedArray(args[0])
        var ta_b = JsTypedArray(args[1])
        var len_a = Int(ta_a.length(env))
        var len_b = Int(ta_b.length(env))
        if len_a != len_b:
            throw_js_error(env, "vectors must have equal length")
            return NapiValue()
        var ptr_a = ta_a.data_ptr_float64(env)
        var ptr_b = ta_b.data_ptr_float64(env)
        return JsNumber.create(env, cosine_similarity(ptr_a, ptr_b, len_a)).value
    except:
        throw_js_error(env, "cosineSimilarity failed")
        return NapiValue()


fn euclidean_distance_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var args = CbArgs.get_two(env, info)
        if not JsTypedArray.is_typedarray(env, args[0]) or not JsTypedArray.is_typedarray(env, args[1]):
            throw_js_error(env, "euclideanDistance requires two TypedArray arguments")
            return NapiValue()
        var ta_a = JsTypedArray(args[0])
        var ta_b = JsTypedArray(args[1])
        var len_a = Int(ta_a.length(env))
        var len_b = Int(ta_b.length(env))
        if len_a != len_b:
            throw_js_error(env, "vectors must have equal length")
            return NapiValue()
        var ptr_a = ta_a.data_ptr_float64(env)
        var ptr_b = ta_b.data_ptr_float64(env)
        return JsNumber.create(env, euclidean_distance(ptr_a, ptr_b, len_a)).value
    except:
        throw_js_error(env, "euclideanDistance failed")
        return NapiValue()


fn normalize_vector_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    # Compute L2-normalized copy of a Float64Array (zero-copy output via MojoFloat64Array).
    # Raises if input is not a Float64Array. Output is owned by JS GC.
    try:
        var arg0 = CbArgs.get_one(env, info)
        if not JsTypedArray.is_typedarray(env, arg0):
            throw_js_error(env, "normalizeVector requires a Float64Array argument")
            return NapiValue()
        var ta = JsTypedArray(arg0)
        var n = Int(ta.length(env))
        var v_ptr = ta.data_ptr_float64(env)  # validates Float64Array + gets ptr in one call
        # Compute L2 norm via SIMD vectorize
        var norm_sq: Float64 = 0.0
        fn compute_norm[width: Int](offset: Int) unified {mut}:
            var x = v_ptr.load[width=width](offset)
            norm_sq += (x * x).reduce_add()
        vectorize[simd_width_of[DType.float64]()](n, compute_norm)
        var norm = sqrt(norm_sq)
        if norm == 0.0:
            norm = 1.0
        # Allocate Mojo output buffer, fill, and hand to JS with no copy
        var out = MojoFloat64Array(n)
        var inv_norm = 1.0 / norm
        for i in range(n):
            out.ptr[i] = v_ptr[i] * inv_norm
        try:
            return out.to_js(env)
        except e:
            out.ptr.free()  # to_js failed — free before re-raise
            raise e^
    except:
        throw_js_error(env, "normalizeVector failed")
        return NapiValue()


# --- Module entry point -------------------------------------------------------

@export("napi_register_module_v1", ABI="C")
fn register_module(env: NapiEnv, exports: NapiValue) -> NapiValue:
    # Initialize Mojo async runtime for parallelize() support
    try:
        init_async_runtime()
    except:
        pass

    var dot_ref = dot_product_fn
    var cos_ref = cosine_similarity_fn
    var euc_ref = euclidean_distance_fn
    var norm_ref = normalize_vector_fn

    try:
        var m = ModuleBuilder(env, exports)
        m.method("dotProduct", fn_ptr(dot_ref))
        m.method("cosineSimilarity", fn_ptr(cos_ref))
        m.method("euclideanDistance", fn_ptr(euc_ref))
        m.method("normalizeVector", fn_ptr(norm_ref))
    except:
        pass

    return exports
