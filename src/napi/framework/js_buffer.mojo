## src/napi/framework/js_buffer.mojo — ergonomic wrapper for Node.js Buffer
##
##   var buf = JsBuffer.create(env, 16)     # 16-byte Buffer
##   var ptr = buf.data_ptr(env)            # UnsafePointer[Byte]
##   var len = buf.length(env)              # 16

from napi.types import NapiEnv, NapiValue
from napi.bindings import Bindings
from napi.raw import raw_create_buffer, raw_create_buffer_copy, raw_get_buffer_info, raw_is_buffer
from napi.error import check_status

struct JsBuffer:
    var value: NapiValue

    fn __init__(out self, value: NapiValue):
        self.value = value

    ## create — allocate a new Buffer with `length` bytes (env-only)
    ##
    ## env-only: for async complete, TSFN, finalizer, and except-block callbacks
    ## where NapiBindings is unavailable. Use create(b, env, length) in hot paths.
    @staticmethod
    fn create(env: NapiEnv, length: UInt) raises -> JsBuffer:
        var data = OpaquePointer[MutAnyOrigin]()
        var result = NapiValue()
        check_status(raw_create_buffer(env, length,
            UnsafePointer(to=data).bitcast[NoneType](),
            UnsafePointer(to=result).bitcast[NoneType]()))
        return JsBuffer(result)

    @staticmethod
    fn create(b: Bindings, env: NapiEnv, length: UInt) raises -> JsBuffer:
        var data = OpaquePointer[MutAnyOrigin]()
        var result = NapiValue()
        check_status(raw_create_buffer(b, env, length,
            UnsafePointer(to=data).bitcast[NoneType](),
            UnsafePointer(to=result).bitcast[NoneType]()))
        return JsBuffer(result)

    ## create_and_fill — allocate and fill with incrementing byte values
    @staticmethod
    fn create_and_fill(env: NapiEnv, length: UInt) raises -> JsBuffer:
        var data = OpaquePointer[MutAnyOrigin]()
        var result = NapiValue()
        check_status(raw_create_buffer(env, length,
            UnsafePointer(to=data).bitcast[NoneType](),
            UnsafePointer(to=result).bitcast[NoneType]()))
        var ptr = data.bitcast[Byte]()
        for i in range(Int(length)):
            ptr[i] = Byte(i)
        return JsBuffer(result)

    @staticmethod
    fn create_and_fill(b: Bindings, env: NapiEnv, length: UInt) raises -> JsBuffer:
        var data = OpaquePointer[MutAnyOrigin]()
        var result = NapiValue()
        check_status(raw_create_buffer(b, env, length,
            UnsafePointer(to=data).bitcast[NoneType](),
            UnsafePointer(to=result).bitcast[NoneType]()))
        var ptr = data.bitcast[Byte]()
        for i in range(Int(length)):
            ptr[i] = Byte(i)
        return JsBuffer(result)

    ## data_ptr — get a raw pointer to the backing store
    ##
    ## Raises with a descriptive error if self.value is not a Buffer.
    fn data_ptr(self, env: NapiEnv) raises -> UnsafePointer[Byte, MutAnyOrigin]:
        if not JsBuffer.is_buffer(env, self.value):
            raise Error("expected a Buffer")
        var data = OpaquePointer[MutAnyOrigin]()
        check_status(raw_get_buffer_info(env, self.value,
            UnsafePointer(to=data).bitcast[NoneType](),
            OpaquePointer[MutAnyOrigin]()))
        return data.bitcast[Byte]()

    fn data_ptr(self, b: Bindings, env: NapiEnv) raises -> UnsafePointer[Byte, MutAnyOrigin]:
        if not JsBuffer.is_buffer(b, env, self.value):
            raise Error("expected a Buffer")
        var data = OpaquePointer[MutAnyOrigin]()
        check_status(raw_get_buffer_info(b, env, self.value,
            UnsafePointer(to=data).bitcast[NoneType](),
            OpaquePointer[MutAnyOrigin]()))
        return data.bitcast[Byte]()

    ## length — get the Buffer's byte length
    ##
    ## Raises with a descriptive error if self.value is not a Buffer.
    fn length(self, env: NapiEnv) raises -> UInt:
        if not JsBuffer.is_buffer(env, self.value):
            raise Error("expected a Buffer")
        var len: UInt = 0
        check_status(raw_get_buffer_info(env, self.value,
            OpaquePointer[MutAnyOrigin](),
            UnsafePointer(to=len).bitcast[NoneType]()))
        return len

    fn length(self, b: Bindings, env: NapiEnv) raises -> UInt:
        if not JsBuffer.is_buffer(b, env, self.value):
            raise Error("expected a Buffer")
        var len: UInt = 0
        check_status(raw_get_buffer_info(b, env, self.value,
            OpaquePointer[MutAnyOrigin](),
            UnsafePointer(to=len).bitcast[NoneType]()))
        return len

    ## create_copy — create a new Buffer with a copy of the bytes from source
    @staticmethod
    fn create_copy(b: Bindings, env: NapiEnv, source: JsBuffer) raises -> JsBuffer:
        var src_ptr = source.data_ptr(b, env)
        var src_len = source.length(b, env)
        var src_data: OpaquePointer[ImmutAnyOrigin] = src_ptr.bitcast[NoneType]()
        var copy_data = OpaquePointer[MutAnyOrigin]()
        var result = NapiValue()
        check_status(raw_create_buffer_copy(b, env, src_len, src_data,
            UnsafePointer(to=copy_data).bitcast[NoneType](),
            UnsafePointer(to=result).bitcast[NoneType]()))
        return JsBuffer(result)

    ## is_buffer — check if a napi_value is a Buffer
    @staticmethod
    fn is_buffer(env: NapiEnv, val: NapiValue) raises -> Bool:
        var result: Bool = False
        check_status(raw_is_buffer(env, val,
            UnsafePointer(to=result).bitcast[NoneType]()))
        return result

    @staticmethod
    fn is_buffer(b: Bindings, env: NapiEnv, val: NapiValue) raises -> Bool:
        var result: Bool = False
        check_status(raw_is_buffer(b, env, val,
            UnsafePointer(to=result).bitcast[NoneType]()))
        return result
