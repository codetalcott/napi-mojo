## src/addon/binary_ops.mojo — ArrayBuffer, Buffer, TypedArray, DataView callbacks

from std.memory import alloc
from napi.types import NapiEnv, NapiValue, NAPI_TYPE_NUMBER, NAPI_INT8_ARRAY, NAPI_UINT8_ARRAY, NAPI_UINT8_CLAMPED_ARRAY, NAPI_INT16_ARRAY, NAPI_UINT16_ARRAY, NAPI_INT32_ARRAY, NAPI_UINT32_ARRAY, NAPI_FLOAT32_ARRAY, NAPI_FLOAT64_ARRAY
from napi.bindings import Bindings
from napi.error import throw_js_error, throw_js_type_error, throw_js_error_dynamic, check_status
from napi.framework.js_boolean import JsBoolean
from napi.framework.js_number import JsNumber
from napi.framework.js_string import JsString
from napi.framework.js_object import JsObject
from napi.framework.js_arraybuffer import JsArrayBuffer
from napi.framework.js_buffer import JsBuffer
from napi.framework.js_typedarray import JsTypedArray
from napi.framework.js_dataview import JsDataView
from napi.framework.args import CbArgs
from napi.framework.js_value import js_typeof
from napi.framework.register import fn_ptr, ModuleBuilder

fn create_arraybuffer_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var ta = js_typeof(b, env, arg0)
        if ta != NAPI_TYPE_NUMBER:
            throw_js_error(b, env, "createArrayBuffer requires a number argument")
            return NapiValue()
        var size = JsNumber.from_napi_value(b, env, arg0)
        return JsArrayBuffer.create_and_fill(b, env, UInt(Int(size))).value
    except:
        throw_js_error(env, "createArrayBuffer requires a number argument")
        return NapiValue()

fn arraybuffer_length_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        if not JsArrayBuffer.is_arraybuffer(b, env, arg0):
            throw_js_error(b, env, "arrayBufferLength requires an ArrayBuffer argument")
            return NapiValue()
        var ab = JsArrayBuffer(arg0)
        var length = ab.byte_length(b, env)
        return JsNumber.create(b, env, Float64(length)).value
    except:
        throw_js_error(env, "arrayBufferLength requires an ArrayBuffer argument")
        return NapiValue()

fn sum_buffer_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        if not JsBuffer.is_buffer(b, env, arg0):
            throw_js_error(b, env, "sumBuffer requires a Buffer argument")
            return NapiValue()
        var buf = JsBuffer(arg0)
        var ptr = buf.data_ptr(b, env)
        var len = buf.length(b, env)
        var total: Float64 = 0.0
        for i in range(Int(len)):
            total += Float64(Int(ptr[i]))
        return JsNumber.create(b, env, total).value
    except:
        throw_js_error(env, "sumBuffer requires a Buffer argument")
        return NapiValue()

fn create_buffer_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var ta = js_typeof(b, env, arg0)
        if ta != NAPI_TYPE_NUMBER:
            throw_js_error(b, env, "createBuffer requires a number argument")
            return NapiValue()
        var size = JsNumber.from_napi_value(b, env, arg0)
        return JsBuffer.create_and_fill(b, env, UInt(Int(size))).value
    except:
        throw_js_error(env, "createBuffer requires a number argument")
        return NapiValue()

fn create_buffer_copy_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        if not JsBuffer.is_buffer(b, env, arg0):
            throw_js_type_error(b, env, "createBufferCopy requires a Buffer argument")
            return NapiValue()
        var src = JsBuffer(arg0)
        return JsBuffer.create_copy(b, env, src).value
    except:
        throw_js_error(env, "createBufferCopy failed")
        return NapiValue()

fn double_float64_array_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        if not JsTypedArray.is_typedarray(b, env, arg0):
            throw_js_error(b, env, "doubleFloat64Array requires a TypedArray argument")
            return NapiValue()
        var ta = JsTypedArray(arg0)
        var len = ta.length(b, env)
        var byte_ptr = ta.data_ptr(b, env)
        var float_ptr = byte_ptr.bitcast[Float64]()
        for i in range(Int(len)):
            float_ptr[i] = float_ptr[i] * 2.0
        return arg0
    except:
        throw_js_error(env, "doubleFloat64Array requires a TypedArray argument")
        return NapiValue()

fn create_typed_array_view_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var argc = CbArgs.argc(b, env, info)
        var argv = alloc[NapiValue](Int(argc))
        CbArgs.get_argv(b, env, info, argc, argv)
        if argc < 4:
            throw_js_error(b, env, "createTypedArrayView requires 4 arguments")
            argv.free()
            return NapiValue()
        var type_str = JsString.from_napi_value(b, env, argv[0])
        var ab = argv[1]
        var offset = Int(JsNumber.from_napi_value(b, env, argv[2]))
        var length = Int(JsNumber.from_napi_value(b, env, argv[3]))
        argv.free()
        var ta: JsTypedArray
        if type_str == "int8":
            ta = JsTypedArray.create_int8(b, env, ab, UInt(offset), UInt(length))
        elif type_str == "uint8":
            ta = JsTypedArray.create_uint8(b, env, ab, UInt(offset), UInt(length))
        elif type_str == "uint8clamped":
            ta = JsTypedArray.create_uint8_clamped(b, env, ab, UInt(offset), UInt(length))
        elif type_str == "int16":
            ta = JsTypedArray.create_int16(b, env, ab, UInt(offset), UInt(length))
        elif type_str == "uint16":
            ta = JsTypedArray.create_uint16(b, env, ab, UInt(offset), UInt(length))
        elif type_str == "int32":
            ta = JsTypedArray.create_int32(b, env, ab, UInt(offset), UInt(length))
        elif type_str == "uint32":
            ta = JsTypedArray.create_uint32(b, env, ab, UInt(offset), UInt(length))
        elif type_str == "float32":
            ta = JsTypedArray.create_float32(b, env, ab, UInt(offset), UInt(length))
        elif type_str == "float64":
            ta = JsTypedArray.create_float64(b, env, ab, UInt(offset), UInt(length))
        else:
            throw_js_error_dynamic(b, env, "createTypedArrayView: unknown type '" + type_str + "'")
            return NapiValue()
        return ta.value
    except:
        throw_js_error(env, "createTypedArrayView failed")
        return NapiValue()

fn get_typed_array_type_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        if not JsTypedArray.is_typedarray(b, env, arg0):
            throw_js_type_error(b, env, "getTypedArrayType: expected TypedArray")
            return NapiValue()
        var ta = JsTypedArray(arg0)
        var t = ta.array_type(b, env)
        return JsNumber.create_int(b, env, Int(t)).value
    except:
        throw_js_error(env, "getTypedArrayType failed")
        return NapiValue()

fn get_typed_array_length_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        if not JsTypedArray.is_typedarray(b, env, arg0):
            throw_js_type_error(b, env, "getTypedArrayLength: expected TypedArray")
            return NapiValue()
        var ta = JsTypedArray(arg0)
        var len = ta.length(b, env)
        return JsNumber.create_int(b, env, Int(len)).value
    except:
        throw_js_error(env, "getTypedArrayLength failed")
        return NapiValue()

fn create_dataview_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var argc = CbArgs.argc(b, env, info)
        if argc < 3:
            throw_js_type_error(b, env, "createDataView requires 3 arguments")
            return NapiValue()
        var argv_ptr = alloc[NapiValue](Int(argc))
        CbArgs.get_argv(b, env, info, argc, argv_ptr)
        var ab = argv_ptr[0]
        var byte_offset = JsNumber.from_napi_value(b, env, argv_ptr[1])
        var byte_length = JsNumber.from_napi_value(b, env, argv_ptr[2])
        argv_ptr.free()
        var dv = JsDataView.create(b, env, UInt(Int(byte_length)), ab, UInt(Int(byte_offset)))
        return dv.value
    except:
        throw_js_error(env, "createDataView failed")
        return NapiValue()

fn get_dataview_info_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var dv = JsDataView(arg0)
        var bl = dv.byte_length(b, env)
        var bo = dv.byte_offset(b, env)
        var obj = JsObject.create(b, env)
        obj.set_property(b, env, "byteLength", JsNumber.create_int(b, env, Int(bl)).value)
        obj.set_property(b, env, "byteOffset", JsNumber.create_int(b, env, Int(bo)).value)
        return obj.value
    except:
        throw_js_error(env, "getDataViewInfo failed")
        return NapiValue()

fn is_dataview_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var result = JsDataView.is_dataview(b, env, arg0)
        return JsBoolean.create(b, env, result).value
    except:
        throw_js_error(env, "isDataView failed")
        return NapiValue()

fn register_binary(mut m: ModuleBuilder) raises:
    var create_arraybuffer_ref = create_arraybuffer_fn
    var arraybuffer_length_ref = arraybuffer_length_fn
    var sum_buffer_ref = sum_buffer_fn
    var create_buffer_ref = create_buffer_fn
    var create_buffer_copy_ref = create_buffer_copy_fn
    var double_float64_array_ref = double_float64_array_fn
    var create_typed_array_view_ref = create_typed_array_view_fn
    var get_typed_array_type_ref = get_typed_array_type_fn
    var get_typed_array_length_ref = get_typed_array_length_fn
    var create_dataview_ref = create_dataview_fn
    var get_dataview_info_ref = get_dataview_info_fn
    var is_dataview_ref = is_dataview_fn
    m.method("createArrayBuffer", fn_ptr(create_arraybuffer_ref))
    m.method("arrayBufferLength", fn_ptr(arraybuffer_length_ref))
    m.method("sumBuffer", fn_ptr(sum_buffer_ref))
    m.method("createBuffer", fn_ptr(create_buffer_ref))
    m.method("createBufferCopy", fn_ptr(create_buffer_copy_ref))
    m.method("doubleFloat64Array", fn_ptr(double_float64_array_ref))
    m.method("createTypedArrayView", fn_ptr(create_typed_array_view_ref))
    m.method("getTypedArrayType", fn_ptr(get_typed_array_type_ref))
    m.method("getTypedArrayLength", fn_ptr(get_typed_array_length_ref))
    m.method("createDataView", fn_ptr(create_dataview_ref))
    m.method("getDataViewInfo", fn_ptr(get_dataview_info_ref))
    m.method("isDataView", fn_ptr(is_dataview_ref))
