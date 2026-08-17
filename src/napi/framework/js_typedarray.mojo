## src/napi/framework/js_typedarray.mojo — ergonomic wrapper for TypedArray
##
##   var ta = JsTypedArray.create_float64(env, arraybuffer, 0, 10)
##   var ptr = ta.data_ptr(env)  # raw byte pointer to data
##   var len = ta.length(env)    # element count (not bytes)

from napi.types import (
    NapiEnv,
    NapiValue,
    NAPI_INT8_ARRAY,
    NAPI_UINT8_ARRAY,
    NAPI_UINT8_CLAMPED_ARRAY,
    NAPI_INT16_ARRAY,
    NAPI_UINT16_ARRAY,
    NAPI_INT32_ARRAY,
    NAPI_UINT32_ARRAY,
    NAPI_FLOAT32_ARRAY,
    NAPI_FLOAT64_ARRAY,
    NAPI_BIGINT64_ARRAY,
    NAPI_BIGUINT64_ARRAY,
)
from napi.bindings import Bindings
from napi.raw import (
    raw_create_typedarray,
    raw_get_typedarray_info,
    raw_is_typedarray,
)
from napi.error import check_status


struct JsTypedArray:
    @__allow_legacy_any_origin_fields
    var value: NapiValue

    def __init__(out self, value: NapiValue):
        self.value = value

    @staticmethod
    def create_float64(
        b: Bindings,
        env: NapiEnv,
        arraybuffer: NapiValue,
        offset: UInt,
        length: UInt,
    ) raises -> JsTypedArray:
        var result = NapiValue(unsafe_from_address=Int(0))
        check_status(
            raw_create_typedarray(
                b,
                env,
                NAPI_FLOAT64_ARRAY,
                length,
                arraybuffer,
                offset,
                Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        return JsTypedArray(result)

    @staticmethod
    def create_uint8(
        b: Bindings,
        env: NapiEnv,
        arraybuffer: NapiValue,
        offset: UInt,
        length: UInt,
    ) raises -> JsTypedArray:
        var result = NapiValue(unsafe_from_address=Int(0))
        check_status(
            raw_create_typedarray(
                b,
                env,
                NAPI_UINT8_ARRAY,
                length,
                arraybuffer,
                offset,
                Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        return JsTypedArray(result)

    @staticmethod
    def create_int32(
        b: Bindings,
        env: NapiEnv,
        arraybuffer: NapiValue,
        offset: UInt,
        length: UInt,
    ) raises -> JsTypedArray:
        var result = NapiValue(unsafe_from_address=Int(0))
        check_status(
            raw_create_typedarray(
                b,
                env,
                NAPI_INT32_ARRAY,
                length,
                arraybuffer,
                offset,
                Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        return JsTypedArray(result)

    @staticmethod
    def create_int8(
        b: Bindings,
        env: NapiEnv,
        arraybuffer: NapiValue,
        offset: UInt,
        length: UInt,
    ) raises -> JsTypedArray:
        var result = NapiValue(unsafe_from_address=Int(0))
        check_status(
            raw_create_typedarray(
                b,
                env,
                NAPI_INT8_ARRAY,
                length,
                arraybuffer,
                offset,
                Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        return JsTypedArray(result)

    @staticmethod
    def create_uint8_clamped(
        b: Bindings,
        env: NapiEnv,
        arraybuffer: NapiValue,
        offset: UInt,
        length: UInt,
    ) raises -> JsTypedArray:
        var result = NapiValue(unsafe_from_address=Int(0))
        check_status(
            raw_create_typedarray(
                b,
                env,
                NAPI_UINT8_CLAMPED_ARRAY,
                length,
                arraybuffer,
                offset,
                Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        return JsTypedArray(result)

    @staticmethod
    def create_int16(
        b: Bindings,
        env: NapiEnv,
        arraybuffer: NapiValue,
        offset: UInt,
        length: UInt,
    ) raises -> JsTypedArray:
        var result = NapiValue(unsafe_from_address=Int(0))
        check_status(
            raw_create_typedarray(
                b,
                env,
                NAPI_INT16_ARRAY,
                length,
                arraybuffer,
                offset,
                Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        return JsTypedArray(result)

    @staticmethod
    def create_uint16(
        b: Bindings,
        env: NapiEnv,
        arraybuffer: NapiValue,
        offset: UInt,
        length: UInt,
    ) raises -> JsTypedArray:
        var result = NapiValue(unsafe_from_address=Int(0))
        check_status(
            raw_create_typedarray(
                b,
                env,
                NAPI_UINT16_ARRAY,
                length,
                arraybuffer,
                offset,
                Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        return JsTypedArray(result)

    @staticmethod
    def create_uint32(
        b: Bindings,
        env: NapiEnv,
        arraybuffer: NapiValue,
        offset: UInt,
        length: UInt,
    ) raises -> JsTypedArray:
        var result = NapiValue(unsafe_from_address=Int(0))
        check_status(
            raw_create_typedarray(
                b,
                env,
                NAPI_UINT32_ARRAY,
                length,
                arraybuffer,
                offset,
                Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        return JsTypedArray(result)

    @staticmethod
    def create_float32(
        b: Bindings,
        env: NapiEnv,
        arraybuffer: NapiValue,
        offset: UInt,
        length: UInt,
    ) raises -> JsTypedArray:
        var result = NapiValue(unsafe_from_address=Int(0))
        check_status(
            raw_create_typedarray(
                b,
                env,
                NAPI_FLOAT32_ARRAY,
                length,
                arraybuffer,
                offset,
                Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        return JsTypedArray(result)

    @staticmethod
    def create_bigint64(
        b: Bindings,
        env: NapiEnv,
        arraybuffer: NapiValue,
        offset: UInt,
        length: UInt,
    ) raises -> JsTypedArray:
        var result = NapiValue(unsafe_from_address=Int(0))
        check_status(
            raw_create_typedarray(
                b,
                env,
                NAPI_BIGINT64_ARRAY,
                length,
                arraybuffer,
                offset,
                Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        return JsTypedArray(result)

    @staticmethod
    def create_biguint64(
        b: Bindings,
        env: NapiEnv,
        arraybuffer: NapiValue,
        offset: UInt,
        length: UInt,
    ) raises -> JsTypedArray:
        var result = NapiValue(unsafe_from_address=Int(0))
        check_status(
            raw_create_typedarray(
                b,
                env,
                NAPI_BIGUINT64_ARRAY,
                length,
                arraybuffer,
                offset,
                Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        return JsTypedArray(result)

    def array_type(self, b: Bindings, env: NapiEnv) raises -> Int32:
        var t: Int32 = 0
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        check_status(
            raw_get_typedarray_info(
                b,
                env,
                self.value,
                Pointer(to=t).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                null,
                null,
                null,
                null,
            )
        )
        return t

    def length(self, b: Bindings, env: NapiEnv) raises -> UInt:
        var len: UInt = 0
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        check_status(
            raw_get_typedarray_info(
                b,
                env,
                self.value,
                null,
                Pointer(to=len).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                null,
                null,
                null,
            )
        )
        return len

    def data_ptr(
        self, b: Bindings, env: NapiEnv
    ) raises -> Pointer[Byte, MutAnyOrigin]:
        var data = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        check_status(
            raw_get_typedarray_info(
                b,
                env,
                self.value,
                null,
                null,
                Pointer(to=data).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                null,
                null,
            )
        )
        return data.unsafe_bitcast[Byte]()

    def arraybuffer(self, b: Bindings, env: NapiEnv) raises -> NapiValue:
        var ab = NapiValue(unsafe_from_address=Int(0))
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        check_status(
            raw_get_typedarray_info(
                b,
                env,
                self.value,
                null,
                null,
                null,
                Pointer(to=ab).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                null,
            )
        )
        return ab

    def data_ptr_float64(
        self, b: Bindings, env: NapiEnv
    ) raises -> Pointer[Float64, MutAnyOrigin]:
        var t: Int32 = 0
        var data = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        check_status(
            raw_get_typedarray_info(
                b,
                env,
                self.value,
                Pointer(to=t).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                null,
                Pointer(to=data).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                null,
                null,
            )
        )
        if t != NAPI_FLOAT64_ARRAY:
            raise Error("expected Float64Array (type 8), got type " + String(t))
        return data.unsafe_bitcast[Float64]()

    def data_ptr_float32(
        self, b: Bindings, env: NapiEnv
    ) raises -> Pointer[Float32, MutAnyOrigin]:
        var t: Int32 = 0
        var data = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        check_status(
            raw_get_typedarray_info(
                b,
                env,
                self.value,
                Pointer(to=t).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                null,
                Pointer(to=data).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                null,
                null,
            )
        )
        if t != NAPI_FLOAT32_ARRAY:
            raise Error("expected Float32Array (type 7), got type " + String(t))
        return data.unsafe_bitcast[Float32]()

    def data_ptr_int32(
        self, b: Bindings, env: NapiEnv
    ) raises -> Pointer[Int32, MutAnyOrigin]:
        var t: Int32 = 0
        var data = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        check_status(
            raw_get_typedarray_info(
                b,
                env,
                self.value,
                Pointer(to=t).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                null,
                Pointer(to=data).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                null,
                null,
            )
        )
        if t != NAPI_INT32_ARRAY:
            raise Error("expected Int32Array (type 5), got type " + String(t))
        return data.unsafe_bitcast[Int32]()

    def data_ptr_uint8(
        self, b: Bindings, env: NapiEnv
    ) raises -> Pointer[UInt8, MutAnyOrigin]:
        var t: Int32 = 0
        var data = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        check_status(
            raw_get_typedarray_info(
                b,
                env,
                self.value,
                Pointer(to=t).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                null,
                Pointer(to=data).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                null,
                null,
            )
        )
        if t != NAPI_UINT8_ARRAY:
            raise Error("expected Uint8Array (type 1), got type " + String(t))
        return data.unsafe_bitcast[UInt8]()

    @staticmethod
    def is_typedarray(b: Bindings, env: NapiEnv, val: NapiValue) raises -> Bool:
        var result: Bool = False
        check_status(
            raw_is_typedarray(
                b, env, val, Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
            )
        )
        return result
