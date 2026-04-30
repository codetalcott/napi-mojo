## src/addon/typed_helpers_ops.mojo — tests for JsExternal.create_typed /
## get_typed and set_instance_data / get_instance_data[T].
##
## The finalizer-count test passes a JS ArrayBuffer(8) as the counter — its
## backing store is a non-owning Int64* stored inside TypedPayload and
## incremented by the struct's destructor. This avoids the need for any
## module-level mutable state (Mojo disallows global vars).

from napi.types import NapiEnv, NapiValue
from napi.bindings import Bindings
from napi.error import throw_js_error
from napi.framework.js_number import JsNumber
from napi.framework.js_external import JsExternal
from napi.framework.js_arraybuffer import JsArrayBuffer
from napi.framework.instance_data import (
    set_instance_data,
    get_instance_data,
)
from napi.framework.args import CbArgs
from napi.framework.register import fn_ptr, ModuleBuilder


struct TypedPayload(Movable):
    var value: Float64
    var counter: UnsafePointer[Int64, MutAnyOrigin]

    def __init__(
        out self, value: Float64, counter: UnsafePointer[Int64, MutAnyOrigin]
    ):
        self.value = value
        self.counter = counter

    def __moveinit__(out self, deinit take: Self):
        self.value = take.value
        self.counter = take.counter

    def __del__(deinit self):
        if Int(self.counter) != 0:
            self.counter[] = self.counter[] + 1


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
        var counter_ptr = ab.data_ptr(b, env).bitcast[Int64]()
        return JsExternal.create_typed(
            b, env, TypedPayload(v, counter_ptr)
        ).value
    except:
        throw_js_error(
            env, "createTypedPayload requires (number, ArrayBuffer(8))"
        )
        return NapiValue()


def read_typed_payload_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var ptr = JsExternal.get_typed[TypedPayload](
            b, env, arg0, "readTypedPayload"
        )
        return JsNumber.create(b, env, ptr[].value).value
    except:
        return NapiValue()


def set_typed_instance_data_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var v = JsNumber.from_napi_value(b, env, arg0)
        set_instance_data(b, env, InstancePayload(Int64(Int(v))))
        return NapiValue()
    except:
        throw_js_error(env, "setTypedInstanceData failed")
        return NapiValue()


def get_typed_instance_data_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var ptr = get_instance_data[InstancePayload](b, env)
        return JsNumber.create(b, env, Float64(ptr[].tag)).value
    except:
        throw_js_error(env, "getTypedInstanceData: no instance data set")
        return NapiValue()


def register_typed_helpers(mut m: ModuleBuilder) raises:
    var create_ref = create_typed_payload_fn
    var read_ref = read_typed_payload_fn
    var set_id_ref = set_typed_instance_data_fn
    var get_id_ref = get_typed_instance_data_fn
    m.method("createTypedPayload", fn_ptr(create_ref))
    m.method("readTypedPayload", fn_ptr(read_ref))
    m.method("setTypedInstanceData", fn_ptr(set_id_ref))
    m.method("getTypedInstanceData", fn_ptr(get_id_ref))
