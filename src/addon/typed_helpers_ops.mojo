## src/addon/typed_helpers_ops.mojo — tests for JsExternal.create_typed /
## get_typed and set_instance_data / get_instance_data[T].
##
## The finalizer-count test passes a JS ArrayBuffer(8) as the counter — its
## backing store is incremented by the external's finalizer so JavaScript can
## observe (via the ArrayBuffer) that finalizers ran. This avoids the need for
## any module-level mutable state (Mojo disallows global vars).
##
## LIFETIME SAFETY: the counter is a raw pointer INTO a GC-owned ArrayBuffer's
## backing store. The external holds no implicit link to that ArrayBuffer, so
## V8 is free to collect the ArrayBuffer (freeing its backing store) BEFORE it
## runs the external's finalizer. Touching the counter then would be a
## use-after-free that corrupts the heap (observed as a non-deterministic
## SIGABRT/SIGTRAP in libmalloc during a later GC). To prevent this,
## createTypedPayload takes a STRONG napi_ref on the ArrayBuffer and the
## finalizer releases it only AFTER the increment — guaranteeing the backing
## store outlives every access to the counter. (This is why a bespoke finalizer
## is used instead of JsExternal.create_typed's generic destroy+free finalizer:
## the generic one cannot release the reference.)

from std.memory.alloc import unsafe_alloc
from napi.types import NapiEnv, NapiValue, NapiRef
from napi.bindings import Bindings
from napi.error import throw_js_error
from napi.framework.js_number import JsNumber
from napi.framework.js_external import JsExternal
from napi.framework.js_arraybuffer import JsArrayBuffer
from napi.framework.js_ref import JsRef
from napi.framework.instance_data import (
    set_instance_data,
    get_instance_data,
)
from napi.framework.args import CbArgs
from napi.framework.register import fn_ptr, ModuleBuilder


struct TypedPayload(Movable):
    var value: Float64
    var counter: Pointer[Int64, MutUntrackedOrigin]
    var ab_ref: NapiRef
    # Cached NapiBindings address so the finalizer can release ab_ref on
    # cached pointers (the bindings allocation is never freed, so this
    # cannot dangle at GC time).
    var bindings_addr: Int

    def __init__(
        out self,
        value: Float64,
        counter: Pointer[Int64, MutAnyOrigin],
        ab_ref: NapiRef,
        bindings_addr: Int,
    ):
        self.value = value
        self.counter = counter.unsafe_origin_cast[MutUntrackedOrigin]()
        self.ab_ref = ab_ref
        self.bindings_addr = bindings_addr

    def __moveinit__(out self, deinit take: Self):
        self.value = take.value
        self.counter = take.counter
        self.ab_ref = take.ab_ref
        self.bindings_addr = take.bindings_addr

    def __deinit__(deinit self):
        # Safe: typed_payload_finalize keeps ab_ref alive across this increment
        # and only releases the ArrayBuffer afterwards, so `counter` always
        # points at live backing-store memory here.
        if Int(self.counter) != 0:
            self.counter[] = self.counter[] + 1


## typed_payload_finalize — GC finalizer for createTypedPayload externals.
##
## Runs on the main thread during the finalizer drain (outside GC), where N-API
## calls are permitted. Order is load-bearing: unsafe_deinit_pointee() increments the
## counter while the ArrayBuffer is still pinned by ab_ref, THEN we release the
## reference so the ArrayBuffer becomes collectable. Reversing the order would
## reintroduce the use-after-free this finalizer exists to prevent.
def typed_payload_finalize(
    env: NapiEnv,
    data: OpaquePointer[MutAnyOrigin],
    hint: OpaquePointer[MutAnyOrigin],
):
    var ptr = data.unsafe_bitcast[TypedPayload]()
    # Copy handle + bindings out before the struct is destroyed
    var ab_ref = ptr[].ab_ref
    var b_addr = ptr[].bindings_addr
    ptr.unsafe_deinit_pointee()  # __del__: counter[] += 1 (ArrayBuffer still pinned)
    ptr.unsafe_free()
    try:
        var b = Bindings(unsafe_from_address=b_addr)
        JsRef(ab_ref).delete(b, env)  # release the ArrayBuffer
    except:
        pass


struct InstancePayload(Movable):
    var tag: Int64

    def __init__(out self, tag: Int64):
        self.tag = tag

    def __moveinit__(out self, deinit take: Self):
        self.tag = take.tag


def create_typed_payload_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var v = JsNumber.from_napi_value(b, env, args[0])
        var ab = JsArrayBuffer(args[1])
        var counter_ptr = ab.data_ptr(b, env).unsafe_bitcast[Int64]()
        # Pin the ArrayBuffer for the external's whole lifetime so `counter_ptr`
        # stays valid until the finalizer is done with it (released there).
        var ab_ref = JsRef.create(b, env, args[1], 1)
        var data_ptr = unsafe_alloc[TypedPayload](1)
        data_ptr.unsafe_write(
            TypedPayload(v, counter_ptr, ab_ref.handle, Int(b))
        )
        var fin_ref = typed_payload_finalize
        var fin_ptr = Pointer(to=fin_ref).unsafe_bitcast[
            OpaquePointer[MutAnyOrigin]
        ]()[]
        try:
            return JsExternal.create(
                b, env, data_ptr.unsafe_bitcast[NoneType]().as_unsafe_any_origin(), fin_ptr
            ).value
        except e:
            # External never created → its finalizer will not run; clean up here.
            data_ptr.unsafe_deinit_pointee()
            data_ptr.unsafe_free()
            try:
                ab_ref.delete(b, env)
            except:
                pass
            raise e^
    except:
        throw_js_error(
            env, "createTypedPayload requires (number, ArrayBuffer(8))"
        )
        return NapiValue(unsafe_from_address=Int(0))


def read_typed_payload_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var ptr = JsExternal.get_typed[TypedPayload](
            b, env, arg0, "readTypedPayload"
        )
        return JsNumber.create(b, env, ptr[].value).value
    except:
        return NapiValue(unsafe_from_address=Int(0))


def set_typed_instance_data_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var v = JsNumber.from_napi_value(b, env, arg0)
        set_instance_data(b, env, InstancePayload(Int64(Int(v))))
        return NapiValue(unsafe_from_address=Int(0))
    except:
        throw_js_error(env, "setTypedInstanceData failed")
        return NapiValue(unsafe_from_address=Int(0))


def get_typed_instance_data_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var ptr = get_instance_data[InstancePayload](b, env)
        return JsNumber.create(b, env, Float64(ptr[].tag)).value
    except:
        throw_js_error(env, "getTypedInstanceData: no instance data set")
        return NapiValue(unsafe_from_address=Int(0))


def register_typed_helpers(mut m: ModuleBuilder) raises:
    var create_ref = create_typed_payload_fn
    var read_ref = read_typed_payload_fn
    var set_id_ref = set_typed_instance_data_fn
    var get_id_ref = get_typed_instance_data_fn
    m.method("createTypedPayload", fn_ptr(create_ref))
    m.method("readTypedPayload", fn_ptr(read_ref))
    m.method("setTypedInstanceData", fn_ptr(set_id_ref))
    m.method("getTypedInstanceData", fn_ptr(get_id_ref))
