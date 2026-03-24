## src/addon/externals.mojo — external data, external arraybuffer, finalizers

from std.memory import alloc
from napi.types import NapiEnv, NapiValue, NAPI_TYPE_EXTERNAL
from napi.bindings import Bindings
from napi.error import throw_js_error, throw_js_type_error_dynamic, check_status
from napi.raw import raw_add_finalizer, raw_create_external_arraybuffer
from napi.framework.js_number import JsNumber
from napi.framework.js_boolean import JsBoolean
from napi.framework.js_object import JsObject
from napi.framework.js_external import JsExternal
from napi.framework.args import CbArgs
from napi.framework.js_value import js_typeof, js_type_name
from napi.framework.register import fn_ptr, ModuleBuilder

struct ExternalData(Movable):
    var x: Float64
    var y: Float64

    def __init__(out self, x: Float64, y: Float64):
        self.x = x
        self.y = y

    def __moveinit__(out self, deinit take: Self):
        self.x = take.x
        self.y = take.y

def external_finalize(env: NapiEnv, data: OpaquePointer[MutAnyOrigin], hint: OpaquePointer[MutAnyOrigin]):
    var ptr = data.bitcast[ExternalData]()
    ptr.destroy_pointee()
    ptr.free()

def create_external_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_two(b, env, info)
        var x = JsNumber.from_napi_value(b, env, args[0])
        var y = JsNumber.from_napi_value(b, env, args[1])
        var data_ptr = alloc[ExternalData](1)
        data_ptr.init_pointee_move(ExternalData(x, y))
        var fin_ref = external_finalize
        var fin_ptr = UnsafePointer(to=fin_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
        return JsExternal.create(b, env, data_ptr.bitcast[NoneType](), fin_ptr).value
    except:
        throw_js_error(env, "createExternal requires two number arguments")
        return NapiValue()

def get_external_data_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var t = js_typeof(b, env, arg0)
        if t != NAPI_TYPE_EXTERNAL:
            throw_js_type_error_dynamic(b, env,
                "getExternalData: expected external, got " + js_type_name(t))
            return NapiValue()
        var data = JsExternal.get_data(b, env, arg0)
        var ptr = data.bitcast[ExternalData]()
        var obj = JsObject.create(b, env)
        obj.set_property(b, env, "x", JsNumber.create(b, env, ptr[].x).value)
        obj.set_property(b, env, "y", JsNumber.create(b, env, ptr[].y).value)
        return obj.value
    except:
        throw_js_error(env, "getExternalData failed")
        return NapiValue()

def is_external_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var t = js_typeof(b, env, arg0)
        return JsBoolean.create(b, env, t == NAPI_TYPE_EXTERNAL).value
    except:
        throw_js_error(env, "isExternal requires one argument")
        return NapiValue()

def external_ab_finalize(
    env: NapiEnv,
    data: OpaquePointer[MutAnyOrigin],
    hint: OpaquePointer[MutAnyOrigin],
):
    var ptr = data.bitcast[Byte]()
    ptr.free()

def create_external_arraybuffer_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var size = JsNumber.from_napi_value(b, env, arg0)
        var byte_len = UInt(Int(size))
        var data_ptr = alloc[Byte](Int(byte_len))
        for i in range(Int(byte_len)):
            data_ptr[i] = Byte(i)
        var fin_ref = external_ab_finalize
        var fin_ptr = UnsafePointer(to=fin_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
        var result = NapiValue()
        try:
            check_status(raw_create_external_arraybuffer(b, env,
                data_ptr.bitcast[NoneType](),
                byte_len,
                fin_ptr,
                OpaquePointer[MutAnyOrigin](),
                UnsafePointer(to=result).bitcast[NoneType]()))
        except e:
            data_ptr.free()
            raise e^
        return result
    except:
        throw_js_error(env, "createExternalArrayBuffer failed")
        return NapiValue()

def noop_finalize(
    env: NapiEnv,
    data: OpaquePointer[MutAnyOrigin],
    hint: OpaquePointer[MutAnyOrigin],
):
    var ptr = data.bitcast[Byte]()
    ptr.free()

def attach_finalizer_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var dummy = alloc[Byte](1)
        dummy[0] = Byte(0)
        var fin_ref = noop_finalize
        var fin_ptr = UnsafePointer(to=fin_ref).bitcast[OpaquePointer[MutAnyOrigin]]()[]
        check_status(raw_add_finalizer(b, env, arg0,
            dummy.bitcast[NoneType](),
            fin_ptr,
            OpaquePointer[MutAnyOrigin](),
            OpaquePointer[MutAnyOrigin]()))
        return arg0
    except:
        throw_js_error(env, "attachFinalizer failed")
        return NapiValue()

def register_externals(mut m: ModuleBuilder) raises:
    var create_external_ref = create_external_fn
    var get_external_data_ref = get_external_data_fn
    var is_external_ref = is_external_fn
    var create_external_arraybuffer_ref = create_external_arraybuffer_fn
    var attach_finalizer_ref = attach_finalizer_fn
    m.method("createExternal", fn_ptr(create_external_ref))
    m.method("getExternalData", fn_ptr(get_external_data_ref))
    m.method("isExternal", fn_ptr(is_external_ref))
    m.method("createExternalArrayBuffer", fn_ptr(create_external_arraybuffer_ref))
    m.method("attachFinalizer", fn_ptr(attach_finalizer_ref))
