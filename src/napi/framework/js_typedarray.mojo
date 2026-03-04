## src/napi/framework/js_typedarray.mojo — ergonomic wrapper for TypedArray
##
##   var ta = JsTypedArray.create_float64(env, arraybuffer, 0, 10)
##   var ptr = ta.data_ptr(env)  # raw byte pointer to data
##   var len = ta.length(env)    # element count (not bytes)

from napi.types import NapiEnv, NapiValue, NAPI_FLOAT64_ARRAY, NAPI_UINT8_ARRAY, NAPI_INT32_ARRAY
from napi.raw import raw_create_typedarray, raw_get_typedarray_info, raw_is_typedarray
from napi.error import check_status

struct JsTypedArray:
    var value: NapiValue

    fn __init__(out self, value: NapiValue):
        self.value = value

    @staticmethod
    fn create_float64(env: NapiEnv, arraybuffer: NapiValue, offset: UInt, length: UInt) raises -> JsTypedArray:
        var result = NapiValue()
        check_status(raw_create_typedarray(env, NAPI_FLOAT64_ARRAY, length, arraybuffer, offset,
            UnsafePointer(to=result).bitcast[NoneType]()))
        return JsTypedArray(result)

    @staticmethod
    fn create_uint8(env: NapiEnv, arraybuffer: NapiValue, offset: UInt, length: UInt) raises -> JsTypedArray:
        var result = NapiValue()
        check_status(raw_create_typedarray(env, NAPI_UINT8_ARRAY, length, arraybuffer, offset,
            UnsafePointer(to=result).bitcast[NoneType]()))
        return JsTypedArray(result)

    @staticmethod
    fn create_int32(env: NapiEnv, arraybuffer: NapiValue, offset: UInt, length: UInt) raises -> JsTypedArray:
        var result = NapiValue()
        check_status(raw_create_typedarray(env, NAPI_INT32_ARRAY, length, arraybuffer, offset,
            UnsafePointer(to=result).bitcast[NoneType]()))
        return JsTypedArray(result)

    ## array_type — returns the NAPI_*_ARRAY constant
    fn array_type(self, env: NapiEnv) raises -> Int32:
        var t: Int32 = 0
        var null = OpaquePointer[MutAnyOrigin]()
        check_status(raw_get_typedarray_info(env, self.value,
            UnsafePointer(to=t).bitcast[NoneType](),
            null, null, null, null))
        return t

    ## length — element count (not bytes)
    fn length(self, env: NapiEnv) raises -> UInt:
        var len: UInt = 0
        var null = OpaquePointer[MutAnyOrigin]()
        check_status(raw_get_typedarray_info(env, self.value,
            null,
            UnsafePointer(to=len).bitcast[NoneType](),
            null, null, null))
        return len

    ## data_ptr — raw byte pointer to the TypedArray's data
    fn data_ptr(self, env: NapiEnv) raises -> UnsafePointer[Byte, MutAnyOrigin]:
        var data = OpaquePointer[MutAnyOrigin]()
        var null = OpaquePointer[MutAnyOrigin]()
        check_status(raw_get_typedarray_info(env, self.value,
            null, null,
            UnsafePointer(to=data).bitcast[NoneType](),
            null, null))
        return data.bitcast[Byte]()

    ## arraybuffer — get the underlying ArrayBuffer napi_value
    fn arraybuffer(self, env: NapiEnv) raises -> NapiValue:
        var ab = NapiValue()
        var null = OpaquePointer[MutAnyOrigin]()
        check_status(raw_get_typedarray_info(env, self.value,
            null, null, null,
            UnsafePointer(to=ab).bitcast[NoneType](),
            null))
        return ab

    ## is_typedarray — check if a napi_value is a TypedArray
    @staticmethod
    fn is_typedarray(env: NapiEnv, val: NapiValue) raises -> Bool:
        var result: Bool = False
        check_status(raw_is_typedarray(env, val,
            UnsafePointer(to=result).bitcast[NoneType]()))
        return result
