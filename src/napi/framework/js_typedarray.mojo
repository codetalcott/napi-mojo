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
    var value: NapiValue

    def __init__(out self, value: NapiValue):
        self.value = value

    @staticmethod
    def create_float64(
        env: NapiEnv, arraybuffer: NapiValue, offset: UInt, length: UInt
    ) raises -> JsTypedArray:
        var result = NapiValue(unsafe_from_address=0)
        check_status(
            raw_create_typedarray(
                env,
                NAPI_FLOAT64_ARRAY,
                length,
                arraybuffer,
                offset,
                UnsafePointer(to=result).bitcast[NoneType](),
            )
        )
        return JsTypedArray(result)

    @staticmethod
    def create_float64(
        b: Bindings,
        env: NapiEnv,
        arraybuffer: NapiValue,
        offset: UInt,
        length: UInt,
    ) raises -> JsTypedArray:
        var result = NapiValue(unsafe_from_address=0)
        check_status(
            raw_create_typedarray(
                b,
                env,
                NAPI_FLOAT64_ARRAY,
                length,
                arraybuffer,
                offset,
                UnsafePointer(to=result).bitcast[NoneType](),
            )
        )
        return JsTypedArray(result)

    @staticmethod
    def create_uint8(
        env: NapiEnv, arraybuffer: NapiValue, offset: UInt, length: UInt
    ) raises -> JsTypedArray:
        var result = NapiValue(unsafe_from_address=0)
        check_status(
            raw_create_typedarray(
                env,
                NAPI_UINT8_ARRAY,
                length,
                arraybuffer,
                offset,
                UnsafePointer(to=result).bitcast[NoneType](),
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
        var result = NapiValue(unsafe_from_address=0)
        check_status(
            raw_create_typedarray(
                b,
                env,
                NAPI_UINT8_ARRAY,
                length,
                arraybuffer,
                offset,
                UnsafePointer(to=result).bitcast[NoneType](),
            )
        )
        return JsTypedArray(result)

    @staticmethod
    def create_int32(
        env: NapiEnv, arraybuffer: NapiValue, offset: UInt, length: UInt
    ) raises -> JsTypedArray:
        var result = NapiValue(unsafe_from_address=0)
        check_status(
            raw_create_typedarray(
                env,
                NAPI_INT32_ARRAY,
                length,
                arraybuffer,
                offset,
                UnsafePointer(to=result).bitcast[NoneType](),
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
        var result = NapiValue(unsafe_from_address=0)
        check_status(
            raw_create_typedarray(
                b,
                env,
                NAPI_INT32_ARRAY,
                length,
                arraybuffer,
                offset,
                UnsafePointer(to=result).bitcast[NoneType](),
            )
        )
        return JsTypedArray(result)

    @staticmethod
    def create_int8(
        env: NapiEnv, arraybuffer: NapiValue, offset: UInt, length: UInt
    ) raises -> JsTypedArray:
        var result = NapiValue(unsafe_from_address=0)
        check_status(
            raw_create_typedarray(
                env,
                NAPI_INT8_ARRAY,
                length,
                arraybuffer,
                offset,
                UnsafePointer(to=result).bitcast[NoneType](),
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
        var result = NapiValue(unsafe_from_address=0)
        check_status(
            raw_create_typedarray(
                b,
                env,
                NAPI_INT8_ARRAY,
                length,
                arraybuffer,
                offset,
                UnsafePointer(to=result).bitcast[NoneType](),
            )
        )
        return JsTypedArray(result)

    @staticmethod
    def create_uint8_clamped(
        env: NapiEnv, arraybuffer: NapiValue, offset: UInt, length: UInt
    ) raises -> JsTypedArray:
        var result = NapiValue(unsafe_from_address=0)
        check_status(
            raw_create_typedarray(
                env,
                NAPI_UINT8_CLAMPED_ARRAY,
                length,
                arraybuffer,
                offset,
                UnsafePointer(to=result).bitcast[NoneType](),
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
        var result = NapiValue(unsafe_from_address=0)
        check_status(
            raw_create_typedarray(
                b,
                env,
                NAPI_UINT8_CLAMPED_ARRAY,
                length,
                arraybuffer,
                offset,
                UnsafePointer(to=result).bitcast[NoneType](),
            )
        )
        return JsTypedArray(result)

    @staticmethod
    def create_int16(
        env: NapiEnv, arraybuffer: NapiValue, offset: UInt, length: UInt
    ) raises -> JsTypedArray:
        var result = NapiValue(unsafe_from_address=0)
        check_status(
            raw_create_typedarray(
                env,
                NAPI_INT16_ARRAY,
                length,
                arraybuffer,
                offset,
                UnsafePointer(to=result).bitcast[NoneType](),
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
        var result = NapiValue(unsafe_from_address=0)
        check_status(
            raw_create_typedarray(
                b,
                env,
                NAPI_INT16_ARRAY,
                length,
                arraybuffer,
                offset,
                UnsafePointer(to=result).bitcast[NoneType](),
            )
        )
        return JsTypedArray(result)

    @staticmethod
    def create_uint16(
        env: NapiEnv, arraybuffer: NapiValue, offset: UInt, length: UInt
    ) raises -> JsTypedArray:
        var result = NapiValue(unsafe_from_address=0)
        check_status(
            raw_create_typedarray(
                env,
                NAPI_UINT16_ARRAY,
                length,
                arraybuffer,
                offset,
                UnsafePointer(to=result).bitcast[NoneType](),
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
        var result = NapiValue(unsafe_from_address=0)
        check_status(
            raw_create_typedarray(
                b,
                env,
                NAPI_UINT16_ARRAY,
                length,
                arraybuffer,
                offset,
                UnsafePointer(to=result).bitcast[NoneType](),
            )
        )
        return JsTypedArray(result)

    @staticmethod
    def create_uint32(
        env: NapiEnv, arraybuffer: NapiValue, offset: UInt, length: UInt
    ) raises -> JsTypedArray:
        var result = NapiValue(unsafe_from_address=0)
        check_status(
            raw_create_typedarray(
                env,
                NAPI_UINT32_ARRAY,
                length,
                arraybuffer,
                offset,
                UnsafePointer(to=result).bitcast[NoneType](),
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
        var result = NapiValue(unsafe_from_address=0)
        check_status(
            raw_create_typedarray(
                b,
                env,
                NAPI_UINT32_ARRAY,
                length,
                arraybuffer,
                offset,
                UnsafePointer(to=result).bitcast[NoneType](),
            )
        )
        return JsTypedArray(result)

    @staticmethod
    def create_float32(
        env: NapiEnv, arraybuffer: NapiValue, offset: UInt, length: UInt
    ) raises -> JsTypedArray:
        var result = NapiValue(unsafe_from_address=0)
        check_status(
            raw_create_typedarray(
                env,
                NAPI_FLOAT32_ARRAY,
                length,
                arraybuffer,
                offset,
                UnsafePointer(to=result).bitcast[NoneType](),
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
        var result = NapiValue(unsafe_from_address=0)
        check_status(
            raw_create_typedarray(
                b,
                env,
                NAPI_FLOAT32_ARRAY,
                length,
                arraybuffer,
                offset,
                UnsafePointer(to=result).bitcast[NoneType](),
            )
        )
        return JsTypedArray(result)

    @staticmethod
    def create_bigint64(
        env: NapiEnv, arraybuffer: NapiValue, offset: UInt, length: UInt
    ) raises -> JsTypedArray:
        var result = NapiValue(unsafe_from_address=0)
        check_status(
            raw_create_typedarray(
                env,
                NAPI_BIGINT64_ARRAY,
                length,
                arraybuffer,
                offset,
                UnsafePointer(to=result).bitcast[NoneType](),
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
        var result = NapiValue(unsafe_from_address=0)
        check_status(
            raw_create_typedarray(
                b,
                env,
                NAPI_BIGINT64_ARRAY,
                length,
                arraybuffer,
                offset,
                UnsafePointer(to=result).bitcast[NoneType](),
            )
        )
        return JsTypedArray(result)

    @staticmethod
    def create_biguint64(
        env: NapiEnv, arraybuffer: NapiValue, offset: UInt, length: UInt
    ) raises -> JsTypedArray:
        var result = NapiValue(unsafe_from_address=0)
        check_status(
            raw_create_typedarray(
                env,
                NAPI_BIGUINT64_ARRAY,
                length,
                arraybuffer,
                offset,
                UnsafePointer(to=result).bitcast[NoneType](),
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
        var result = NapiValue(unsafe_from_address=0)
        check_status(
            raw_create_typedarray(
                b,
                env,
                NAPI_BIGUINT64_ARRAY,
                length,
                arraybuffer,
                offset,
                UnsafePointer(to=result).bitcast[NoneType](),
            )
        )
        return JsTypedArray(result)

    ## array_type — returns the NAPI_*_ARRAY constant
    def array_type(self, env: NapiEnv) raises -> Int32:
        var t: Int32 = 0
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=0)
        check_status(
            raw_get_typedarray_info(
                env,
                self.value,
                UnsafePointer(to=t).bitcast[NoneType](),
                null,
                null,
                null,
                null,
            )
        )
        return t

    def array_type(self, b: Bindings, env: NapiEnv) raises -> Int32:
        var t: Int32 = 0
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=0)
        check_status(
            raw_get_typedarray_info(
                b,
                env,
                self.value,
                UnsafePointer(to=t).bitcast[NoneType](),
                null,
                null,
                null,
                null,
            )
        )
        return t

    ## length — element count (not bytes)
    def length(self, env: NapiEnv) raises -> UInt:
        var len: UInt = 0
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=0)
        check_status(
            raw_get_typedarray_info(
                env,
                self.value,
                null,
                UnsafePointer(to=len).bitcast[NoneType](),
                null,
                null,
                null,
            )
        )
        return len

    def length(self, b: Bindings, env: NapiEnv) raises -> UInt:
        var len: UInt = 0
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=0)
        check_status(
            raw_get_typedarray_info(
                b,
                env,
                self.value,
                null,
                UnsafePointer(to=len).bitcast[NoneType](),
                null,
                null,
                null,
            )
        )
        return len

    ## data_ptr — raw byte pointer to the TypedArray's data
    def data_ptr(
        self, env: NapiEnv
    ) raises -> UnsafePointer[Byte, MutAnyOrigin]:
        var data = OpaquePointer[MutAnyOrigin](unsafe_from_address=0)
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=0)
        check_status(
            raw_get_typedarray_info(
                env,
                self.value,
                null,
                null,
                UnsafePointer(to=data).bitcast[NoneType](),
                null,
                null,
            )
        )
        return data.bitcast[Byte]()

    def data_ptr(
        self, b: Bindings, env: NapiEnv
    ) raises -> UnsafePointer[Byte, MutAnyOrigin]:
        var data = OpaquePointer[MutAnyOrigin](unsafe_from_address=0)
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=0)
        check_status(
            raw_get_typedarray_info(
                b,
                env,
                self.value,
                null,
                null,
                UnsafePointer(to=data).bitcast[NoneType](),
                null,
                null,
            )
        )
        return data.bitcast[Byte]()

    ## arraybuffer — get the underlying ArrayBuffer napi_value
    def arraybuffer(self, env: NapiEnv) raises -> NapiValue:
        var ab = NapiValue(unsafe_from_address=0)
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=0)
        check_status(
            raw_get_typedarray_info(
                env,
                self.value,
                null,
                null,
                null,
                UnsafePointer(to=ab).bitcast[NoneType](),
                null,
            )
        )
        return ab

    def arraybuffer(self, b: Bindings, env: NapiEnv) raises -> NapiValue:
        var ab = NapiValue(unsafe_from_address=0)
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=0)
        check_status(
            raw_get_typedarray_info(
                b,
                env,
                self.value,
                null,
                null,
                null,
                UnsafePointer(to=ab).bitcast[NoneType](),
                null,
            )
        )
        return ab

    ## data_ptr_float64 — raw Float64 pointer; validates type in the same
    ## napi_get_typedarray_info call — one N-API round-trip, not two.
    def data_ptr_float64(
        self, env: NapiEnv
    ) raises -> UnsafePointer[Float64, MutAnyOrigin]:
        var t: Int32 = 0
        var data = OpaquePointer[MutAnyOrigin](unsafe_from_address=0)
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=0)
        check_status(
            raw_get_typedarray_info(
                env,
                self.value,
                UnsafePointer(to=t).bitcast[NoneType](),
                null,
                UnsafePointer(to=data).bitcast[NoneType](),
                null,
                null,
            )
        )
        if t != NAPI_FLOAT64_ARRAY:
            raise Error("expected Float64Array (type 8), got type " + String(t))
        return data.bitcast[Float64]()

    def data_ptr_float64(
        self, b: Bindings, env: NapiEnv
    ) raises -> UnsafePointer[Float64, MutAnyOrigin]:
        var t: Int32 = 0
        var data = OpaquePointer[MutAnyOrigin](unsafe_from_address=0)
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=0)
        check_status(
            raw_get_typedarray_info(
                b,
                env,
                self.value,
                UnsafePointer(to=t).bitcast[NoneType](),
                null,
                UnsafePointer(to=data).bitcast[NoneType](),
                null,
                null,
            )
        )
        if t != NAPI_FLOAT64_ARRAY:
            raise Error("expected Float64Array (type 8), got type " + String(t))
        return data.bitcast[Float64]()

    ## data_ptr_float32 — raw Float32 pointer, raises if not a Float32Array
    def data_ptr_float32(
        self, env: NapiEnv
    ) raises -> UnsafePointer[Float32, MutAnyOrigin]:
        var t: Int32 = 0
        var data = OpaquePointer[MutAnyOrigin](unsafe_from_address=0)
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=0)
        check_status(
            raw_get_typedarray_info(
                env,
                self.value,
                UnsafePointer(to=t).bitcast[NoneType](),
                null,
                UnsafePointer(to=data).bitcast[NoneType](),
                null,
                null,
            )
        )
        if t != NAPI_FLOAT32_ARRAY:
            raise Error("expected Float32Array (type 7), got type " + String(t))
        return data.bitcast[Float32]()

    def data_ptr_float32(
        self, b: Bindings, env: NapiEnv
    ) raises -> UnsafePointer[Float32, MutAnyOrigin]:
        var t: Int32 = 0
        var data = OpaquePointer[MutAnyOrigin](unsafe_from_address=0)
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=0)
        check_status(
            raw_get_typedarray_info(
                b,
                env,
                self.value,
                UnsafePointer(to=t).bitcast[NoneType](),
                null,
                UnsafePointer(to=data).bitcast[NoneType](),
                null,
                null,
            )
        )
        if t != NAPI_FLOAT32_ARRAY:
            raise Error("expected Float32Array (type 7), got type " + String(t))
        return data.bitcast[Float32]()

    ## data_ptr_int32 — raw Int32 pointer, raises if not an Int32Array
    def data_ptr_int32(
        self, env: NapiEnv
    ) raises -> UnsafePointer[Int32, MutAnyOrigin]:
        var t: Int32 = 0
        var data = OpaquePointer[MutAnyOrigin](unsafe_from_address=0)
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=0)
        check_status(
            raw_get_typedarray_info(
                env,
                self.value,
                UnsafePointer(to=t).bitcast[NoneType](),
                null,
                UnsafePointer(to=data).bitcast[NoneType](),
                null,
                null,
            )
        )
        if t != NAPI_INT32_ARRAY:
            raise Error("expected Int32Array (type 5), got type " + String(t))
        return data.bitcast[Int32]()

    def data_ptr_int32(
        self, b: Bindings, env: NapiEnv
    ) raises -> UnsafePointer[Int32, MutAnyOrigin]:
        var t: Int32 = 0
        var data = OpaquePointer[MutAnyOrigin](unsafe_from_address=0)
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=0)
        check_status(
            raw_get_typedarray_info(
                b,
                env,
                self.value,
                UnsafePointer(to=t).bitcast[NoneType](),
                null,
                UnsafePointer(to=data).bitcast[NoneType](),
                null,
                null,
            )
        )
        if t != NAPI_INT32_ARRAY:
            raise Error("expected Int32Array (type 5), got type " + String(t))
        return data.bitcast[Int32]()

    ## data_ptr_uint8 — raw UInt8 pointer, raises if not a Uint8Array
    def data_ptr_uint8(
        self, env: NapiEnv
    ) raises -> UnsafePointer[UInt8, MutAnyOrigin]:
        var t: Int32 = 0
        var data = OpaquePointer[MutAnyOrigin](unsafe_from_address=0)
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=0)
        check_status(
            raw_get_typedarray_info(
                env,
                self.value,
                UnsafePointer(to=t).bitcast[NoneType](),
                null,
                UnsafePointer(to=data).bitcast[NoneType](),
                null,
                null,
            )
        )
        if t != NAPI_UINT8_ARRAY:
            raise Error("expected Uint8Array (type 1), got type " + String(t))
        return data.bitcast[UInt8]()

    def data_ptr_uint8(
        self, b: Bindings, env: NapiEnv
    ) raises -> UnsafePointer[UInt8, MutAnyOrigin]:
        var t: Int32 = 0
        var data = OpaquePointer[MutAnyOrigin](unsafe_from_address=0)
        var null = OpaquePointer[MutAnyOrigin](unsafe_from_address=0)
        check_status(
            raw_get_typedarray_info(
                b,
                env,
                self.value,
                UnsafePointer(to=t).bitcast[NoneType](),
                null,
                UnsafePointer(to=data).bitcast[NoneType](),
                null,
                null,
            )
        )
        if t != NAPI_UINT8_ARRAY:
            raise Error("expected Uint8Array (type 1), got type " + String(t))
        return data.bitcast[UInt8]()

    ## is_typedarray — check if a napi_value is a TypedArray
    @staticmethod
    def is_typedarray(env: NapiEnv, val: NapiValue) raises -> Bool:
        var result: Bool = False
        check_status(
            raw_is_typedarray(
                env, val, UnsafePointer(to=result).bitcast[NoneType]()
            )
        )
        return result

    @staticmethod
    def is_typedarray(b: Bindings, env: NapiEnv, val: NapiValue) raises -> Bool:
        var result: Bool = False
        check_status(
            raw_is_typedarray(
                b, env, val, UnsafePointer(to=result).bitcast[NoneType]()
            )
        )
        return result
