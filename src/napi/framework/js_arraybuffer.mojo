## src/napi/framework/js_arraybuffer.mojo — ergonomic wrapper for ArrayBuffer
##
##   var ab = JsArrayBuffer.create(env, 16)  # 16-byte ArrayBuffer
##   var ptr = ab.data_ptr(env)              # Pointer[Byte] to backing store
##   var len = ab.byte_length(env)           # 16
##   return ab.value

from napi.types import NapiEnv, NapiValue
from napi.bindings import Bindings
from napi.raw import (
    raw_create_arraybuffer,
    raw_get_arraybuffer_info,
    raw_is_arraybuffer,
    raw_detach_arraybuffer,
    raw_is_detached_arraybuffer,
)
from napi.error import check_status


struct JsArrayBuffer:
    @__allow_legacy_any_origin_fields
    var value: NapiValue

    def __init__(out self, value: NapiValue):
        self.value = value

    @staticmethod
    def create(
        b: Bindings, env: NapiEnv, byte_length: UInt
    ) raises -> JsArrayBuffer:
        var data = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        var result = NapiValue(unsafe_from_address=Int(0))
        check_status(
            raw_create_arraybuffer(
                b,
                env,
                byte_length,
                Pointer(to=data).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        return JsArrayBuffer(result)

    @staticmethod
    def create_and_fill(
        b: Bindings, env: NapiEnv, byte_length: UInt
    ) raises -> JsArrayBuffer:
        var data = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        var result = NapiValue(unsafe_from_address=Int(0))
        check_status(
            raw_create_arraybuffer(
                b,
                env,
                byte_length,
                Pointer(to=data).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        var ptr = data.unsafe_bitcast[Byte]()
        for i in range(Int(byte_length)):
            ptr[unsafe_offset=i] = Byte(i)
        return JsArrayBuffer(result)

    def byte_length(self, b: Bindings, env: NapiEnv) raises -> UInt:
        var length: UInt = 0
        check_status(
            raw_get_arraybuffer_info(
                b,
                env,
                self.value,
                OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0)),
                Pointer(to=length).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        return length

    def data_ptr(
        self, b: Bindings, env: NapiEnv
    ) raises -> Pointer[Byte, MutAnyOrigin]:
        var data = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        check_status(
            raw_get_arraybuffer_info(
                b,
                env,
                self.value,
                Pointer(to=data).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0)),
            )
        )
        return data.unsafe_bitcast[Byte]()

    @staticmethod
    def is_arraybuffer(
        b: Bindings, env: NapiEnv, val: NapiValue
    ) raises -> Bool:
        var result: Bool = False
        check_status(
            raw_is_arraybuffer(
                b, env, val, Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
            )
        )
        return result

    def detach(self, b: Bindings, env: NapiEnv) raises:
        check_status(raw_detach_arraybuffer(b, env, self.value))

    @staticmethod
    def is_detached(b: Bindings, env: NapiEnv, val: NapiValue) raises -> Bool:
        var result: Bool = False
        check_status(
            raw_is_detached_arraybuffer(
                b, env, val, Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
            )
        )
        return result
