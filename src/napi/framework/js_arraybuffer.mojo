## src/napi/framework/js_arraybuffer.mojo — ergonomic wrapper for ArrayBuffer
##
##   var ab = JsArrayBuffer.create(env, 16)  # 16-byte ArrayBuffer
##   var ptr = ab.data_ptr(env)              # UnsafePointer[Byte] to backing store
##   var len = ab.byte_length(env)           # 16
##   return ab.value

from napi.types import NapiEnv, NapiValue
from napi.raw import raw_create_arraybuffer, raw_get_arraybuffer_info, raw_is_arraybuffer
from napi.error import check_status

struct JsArrayBuffer:
    var value: NapiValue

    fn __init__(out self, value: NapiValue):
        self.value = value

    ## create — allocate a new ArrayBuffer with `byte_length` bytes.
    ## Also fills the buffer with incrementing byte values (0, 1, 2, ...).
    @staticmethod
    fn create(env: NapiEnv, byte_length: UInt) raises -> JsArrayBuffer:
        var data = OpaquePointer[MutAnyOrigin]()
        var result = NapiValue()
        check_status(raw_create_arraybuffer(env, byte_length,
            UnsafePointer(to=data).bitcast[NoneType](),
            UnsafePointer(to=result).bitcast[NoneType]()))
        return JsArrayBuffer(result)

    ## create_and_fill — allocate and fill with incrementing byte values
    @staticmethod
    fn create_and_fill(env: NapiEnv, byte_length: UInt) raises -> JsArrayBuffer:
        var data = OpaquePointer[MutAnyOrigin]()
        var result = NapiValue()
        check_status(raw_create_arraybuffer(env, byte_length,
            UnsafePointer(to=data).bitcast[NoneType](),
            UnsafePointer(to=result).bitcast[NoneType]()))
        var ptr = data.bitcast[Byte]()
        for i in range(Int(byte_length)):
            ptr[i] = Byte(i)
        return JsArrayBuffer(result)

    ## byte_length — get the ArrayBuffer's byte length
    fn byte_length(self, env: NapiEnv) raises -> UInt:
        var length: UInt = 0
        check_status(raw_get_arraybuffer_info(env, self.value,
            OpaquePointer[MutAnyOrigin](),
            UnsafePointer(to=length).bitcast[NoneType]()))
        return length

    ## data_ptr — get a raw pointer to the backing store
    fn data_ptr(self, env: NapiEnv) raises -> UnsafePointer[Byte, MutAnyOrigin]:
        var data = OpaquePointer[MutAnyOrigin]()
        check_status(raw_get_arraybuffer_info(env, self.value,
            UnsafePointer(to=data).bitcast[NoneType](),
            OpaquePointer[MutAnyOrigin]()))
        return data.bitcast[Byte]()

    ## is_arraybuffer — check if a napi_value is an ArrayBuffer
    @staticmethod
    fn is_arraybuffer(env: NapiEnv, val: NapiValue) raises -> Bool:
        var result: Bool = False
        check_status(raw_is_arraybuffer(env, val,
            UnsafePointer(to=result).bitcast[NoneType]()))
        return result
