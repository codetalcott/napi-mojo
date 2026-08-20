## src/napi/framework/js_buffer.mojo — ergonomic wrapper for Node.js Buffer
##
##   var buf = JsBuffer.create(env, 16)     # 16-byte Buffer
##   var ptr = buf.data_ptr(env)            # Pointer[Byte]
##   var len = buf.length(env)              # 16

from napi.types import NapiEnv, NapiValue
from napi.bindings import Bindings
from napi.raw import (
    raw_create_buffer,
    raw_create_buffer_copy,
    raw_get_buffer_info,
    raw_is_buffer,
    raw_create_buffer_from_arraybuffer,
)
from napi.framework.js_arraybuffer import JsArrayBuffer
from napi.error import check_status


struct JsBuffer:
    var value: NapiValue

    def __init__(out self, value: NapiValue):
        self.value = value

    @staticmethod
    def create(b: Bindings, env: NapiEnv, length: UInt) raises -> JsBuffer:
        var data = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        var result = NapiValue(unsafe_from_address=Int(0))
        check_status(
            raw_create_buffer(
                b,
                env,
                length,
                Pointer(to=data).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        return JsBuffer(result)

    @staticmethod
    def create_and_fill(
        b: Bindings, env: NapiEnv, length: UInt
    ) raises -> JsBuffer:
        var data = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        var result = NapiValue(unsafe_from_address=Int(0))
        check_status(
            raw_create_buffer(
                b,
                env,
                length,
                Pointer(to=data).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        var ptr = data.unsafe_bitcast[Byte]()
        for i in range(Int(length)):
            ptr[unsafe_offset=i] = Byte(i)
        return JsBuffer(result)

    def data_ptr(
        self, b: Bindings, env: NapiEnv
    ) raises -> Pointer[Byte, MutAnyOrigin]:
        if not JsBuffer.is_buffer(b, env, self.value):
            raise Error("expected a Buffer")
        var data = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        check_status(
            raw_get_buffer_info(
                b,
                env,
                self.value,
                Pointer(to=data).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0)),
            )
        )
        return data.unsafe_bitcast[Byte]()

    def length(self, b: Bindings, env: NapiEnv) raises -> UInt:
        if not JsBuffer.is_buffer(b, env, self.value):
            raise Error("expected a Buffer")
        var len: UInt = 0
        check_status(
            raw_get_buffer_info(
                b,
                env,
                self.value,
                OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0)),
                Pointer(to=len).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        return len

    ## create_copy — create a new Buffer with a copy of the bytes from source
    @staticmethod
    def create_copy(
        b: Bindings, env: NapiEnv, source: JsBuffer
    ) raises -> JsBuffer:
        var src_ptr = source.data_ptr(b, env)
        var src_len = source.length(b, env)
        var src_data: OpaquePointer[ImmutAnyOrigin] = src_ptr.unsafe_bitcast[
            NoneType
        ]()
        var copy_data = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        var result = NapiValue(unsafe_from_address=Int(0))
        check_status(
            raw_create_buffer_copy(
                b,
                env,
                src_len,
                src_data,
                Pointer(to=copy_data).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        return JsBuffer(result)

    ## from_arraybuffer — zero-copy Buffer view into an ArrayBuffer slice (N-API v10)
    ##
    ## Creates a Node.js Buffer that directly references a byte range of an existing
    ## ArrayBuffer — no copy of the data. The ArrayBuffer must remain alive (referenced)
    ## for the Buffer to be valid. Raises if byte_offset + byte_length exceeds the
    ## ArrayBuffer's size (Node.js surfaces this as a RangeError).
    @staticmethod
    def from_arraybuffer(
        b: Bindings,
        env: NapiEnv,
        ab: JsArrayBuffer,
        byte_offset: UInt,
        byte_length: UInt,
    ) raises -> JsBuffer:
        var result = NapiValue(unsafe_from_address=Int(0))
        check_status(
            raw_create_buffer_from_arraybuffer(
                b,
                env,
                ab.value,
                byte_offset,
                byte_length,
                Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        return JsBuffer(result)

    @staticmethod
    def is_buffer(b: Bindings, env: NapiEnv, val: NapiValue) raises -> Bool:
        var result: Bool = False
        check_status(
            raw_is_buffer(
                b, env, val, Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
            )
        )
        return result
