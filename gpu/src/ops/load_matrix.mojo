## gpu/src/ops/load_matrix.mojo — loadMatrixGpu, freeMatrix, freeAll, liveHandles
##
## ## Async model — currently sync-with-Promise
##
## `loadMatrixGpu` returns a `Promise<MatrixHandle>` for API stability:
## consumers should `await` it from day one so we can move the actual H2D
## copy to a libuv worker thread without an API change. For now the copy
## is synchronous on the JS main thread — the work the function does
## (alloc device buffer, memcpy, synchronize) runs in-line and the
## promise resolves immediately. This trades latency for correctness
## simplicity: cross-thread DeviceContext access has its own thread-safety
## questions to validate, and pinning the answer should not block this
## initial scaffold.
##
## ## Why not napi_create_external + finalizer
##
## See gpu/src/registry.mojo. Short version: Mojo 1.0.0b1 doesn't expose
## a way to take a function's address as a thin C-ABI pointer, and our
## existing N-API finalizer plumbing has been intermittently crashing on
## Linux. The registry lives entirely outside the N-API GC system.

from std.memory import alloc, memcpy
from std.gpu.host import DeviceBuffer

from napi.types import NapiEnv, NapiValue
from napi.bindings import Bindings
from napi.error import throw_js_error, check_status
from napi.raw import raw_resolve_deferred, raw_reject_deferred, raw_create_error
from napi.framework.args import CbArgs
from napi.framework.js_bigint import JsBigInt
from napi.framework.js_int32 import JsInt32
from napi.framework.js_promise import JsPromise
from napi.framework.js_string import JsString
from napi.framework.js_typedarray import JsTypedArray
from napi.framework.js_undefined import JsUndefined
from napi.framework.register import fn_ptr, ModuleBuilder

from module_data import GpuModuleData


comptime DTYPE = DType.float32


def _module_data(b: Bindings) -> UnsafePointer[GpuModuleData, MutAnyOrigin]:
    """Recover the GpuModuleData pointer from the bindings pointer.

    GpuModuleData puts NapiBindings as its first field, so &bindings ==
    &module_data and a bitcast recovers the wider pointer.
    """
    return b.bitcast[GpuModuleData]()


def _reject_promise_with(
    env: NapiEnv, deferred: NapiValue, message: StringLiteral
) raises:
    """Build a JS Error and reject the promise with it."""
    var msg = JsString.create_literal(env, message)
    var null_code = NapiValue()
    var error_val = NapiValue()
    var error_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
        to=error_val
    ).bitcast[NoneType]()
    _ = raw_create_error(env, null_code, msg.value, error_ptr)
    _ = raw_reject_deferred(env, deferred, error_val)


# ─── loadMatrixGpu(data: Float32Array, rows: number, cols: number) ────────

def load_matrix_gpu_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    """Upload host data to GPU and resolve a Promise with the handle id."""
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_three(b, env, info)

        # Read args before we touch the GPU — surfaces type errors as
        # synchronous throws (caller's `.catch` won't see them, but the
        # try-catch around `await loadMatrixGpu(...)` will).
        var ta = JsTypedArray(args[0])
        var rows = Int(JsInt32.from_napi_value(b, env, args[1]))
        var cols = Int(JsInt32.from_napi_value(b, env, args[2]))
        var ta_len = Int(ta.length(b, env))
        var expected_len = rows * cols
        if ta_len != expected_len:
            throw_js_error(
                env, "loadMatrixGpu: data.length must equal rows * cols"
            )
            return NapiValue()
        var src_bytes = ta.data_ptr(b, env)

        # From here on, errors go through the Promise rather than throwing.
        var p = JsPromise.create(b, env)
        var module_data = _module_data(b)

        if module_data[].ctx is None:
            try:
                _reject_promise_with(
                    env, p.deferred, "loadMatrixGpu: no GPU available"
                )
            except:
                pass
            return p.value

        try:
            # H2D copy: allocate device + pinned host staging, memcpy, enqueue
            # device copy, synchronize.
            var num_elems = rows * cols
            var num_bytes = num_elems * 4
            var ctx = module_data[].ctx.value()
            var dev_data = ctx.enqueue_create_buffer[DTYPE](num_elems)
            var staging = ctx.enqueue_create_host_buffer[DTYPE](num_elems)
            var staging_ptr = staging.unsafe_ptr().bitcast[Byte]()
            memcpy(dest=staging_ptr, src=src_bytes, count=num_bytes)
            ctx.enqueue_copy(dev_data, staging)
            ctx.synchronize()

            # Insert into the registry; the id is what JS sees as the handle.
            var id = module_data[].registry[].insert(dev_data^, rows, cols)
            var handle_val = JsBigInt.from_uint64(b, env, UInt64(id))
            _ = raw_resolve_deferred(env, p.deferred, handle_val.value)
        except:
            try:
                _reject_promise_with(
                    env, p.deferred, "loadMatrixGpu: device upload failed"
                )
            except:
                pass

        return p.value
    except:
        throw_js_error(env, "loadMatrixGpu requires (Float32Array, rows, cols)")
        return NapiValue()


# ─── freeMatrix(h: MatrixHandle): void ────────────────────────────────────

def free_matrix_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    """Synchronously free the device buffer and remove the registry entry.

    Idempotent: unknown ids and already-freed ids return without throwing
    so cleanup paths stay simple. Returns undefined.
    """
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var id = JsBigInt.to_uint64(b, env, arg0)
        var module_data = _module_data(b)
        _ = module_data[].registry[].remove(id)
        return JsUndefined.create(b, env).value
    except:
        throw_js_error(env, "freeMatrix requires a BigInt handle")
        return NapiValue()


# ─── freeAll(): void ──────────────────────────────────────────────────────

def free_all_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    """Free every live handle. For tests and process-exit cleanup."""
    try:
        var b = CbArgs.get_bindings(env, info)
        var module_data = _module_data(b)
        module_data[].registry[].remove_all()
        return JsUndefined.create(b, env).value
    except:
        throw_js_error(env, "freeAll failed")
        return NapiValue()


# ─── liveHandles(): { matrices: number } ──────────────────────────────────

def live_handles_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    """Returns a small status object. For leak-detection in tests."""
    try:
        var b = CbArgs.get_bindings(env, info)
        var module_data = _module_data(b)
        var n = module_data[].registry[].live_count()
        # We avoid creating an Object here to keep the code dependency-free
        # at this scaffold stage — return n as a Number and reshape on the
        # JS side.  TODO: return an object once we have more counters.
        return JsInt32.create(b, env, Int32(n)).value
    except:
        throw_js_error(env, "liveHandles failed")
        return NapiValue()


# ─── Registration ─────────────────────────────────────────────────────────

def register_load_matrix(mut m: ModuleBuilder) raises:
    var load_ref = load_matrix_gpu_fn
    var free_ref = free_matrix_fn
    var free_all_ref = free_all_fn
    var live_ref = live_handles_fn
    m.method("loadMatrixGpu", fn_ptr(load_ref))
    m.method("freeMatrix", fn_ptr(free_ref))
    m.method("freeAll", fn_ptr(free_all_ref))
    m.method("_liveHandlesCount", fn_ptr(live_ref))
