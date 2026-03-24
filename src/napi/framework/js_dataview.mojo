## src/napi/framework/js_dataview.mojo — ergonomic wrapper for DataView
##
##   var dv = JsDataView.create(env, 16, arraybuffer, 0)
##   var len = dv.byte_length(env)
##   var off = dv.byte_offset(env)
##   return dv.value

from napi.types import NapiEnv, NapiValue
from napi.bindings import Bindings
from napi.raw import raw_create_dataview, raw_get_dataview_info, raw_is_dataview
from napi.error import check_status

struct JsDataView:
    var value: NapiValue

    def __init__(out self, value: NapiValue):
        self.value = value

    ## create — create a DataView over an existing ArrayBuffer
    @staticmethod
    def create(env: NapiEnv, byte_length: UInt, arraybuffer: NapiValue, byte_offset: UInt) raises -> JsDataView:
        var result = NapiValue()
        check_status(raw_create_dataview(env, byte_length, arraybuffer, byte_offset,
            UnsafePointer(to=result).bitcast[NoneType]()))
        return JsDataView(result)

    @staticmethod
    def create(b: Bindings, env: NapiEnv, byte_length: UInt, arraybuffer: NapiValue, byte_offset: UInt) raises -> JsDataView:
        var result = NapiValue()
        check_status(raw_create_dataview(b, env, byte_length, arraybuffer, byte_offset,
            UnsafePointer(to=result).bitcast[NoneType]()))
        return JsDataView(result)

    ## byte_length — get the DataView's byte length
    def byte_length(self, env: NapiEnv) raises -> UInt:
        var length: UInt = 0
        check_status(raw_get_dataview_info(env, self.value,
            UnsafePointer(to=length).bitcast[NoneType](),
            OpaquePointer[MutAnyOrigin](),
            OpaquePointer[MutAnyOrigin](),
            OpaquePointer[MutAnyOrigin]()))
        return length

    def byte_length(self, b: Bindings, env: NapiEnv) raises -> UInt:
        var length: UInt = 0
        check_status(raw_get_dataview_info(b, env, self.value,
            UnsafePointer(to=length).bitcast[NoneType](),
            OpaquePointer[MutAnyOrigin](),
            OpaquePointer[MutAnyOrigin](),
            OpaquePointer[MutAnyOrigin]()))
        return length

    ## byte_offset — get the DataView's byte offset into the ArrayBuffer
    def byte_offset(self, env: NapiEnv) raises -> UInt:
        var offset: UInt = 0
        check_status(raw_get_dataview_info(env, self.value,
            OpaquePointer[MutAnyOrigin](),
            OpaquePointer[MutAnyOrigin](),
            OpaquePointer[MutAnyOrigin](),
            UnsafePointer(to=offset).bitcast[NoneType]()))
        return offset

    def byte_offset(self, b: Bindings, env: NapiEnv) raises -> UInt:
        var offset: UInt = 0
        check_status(raw_get_dataview_info(b, env, self.value,
            OpaquePointer[MutAnyOrigin](),
            OpaquePointer[MutAnyOrigin](),
            OpaquePointer[MutAnyOrigin](),
            UnsafePointer(to=offset).bitcast[NoneType]()))
        return offset

    ## data_ptr — get a raw pointer to the DataView's data
    def data_ptr(self, env: NapiEnv) raises -> UnsafePointer[Byte, MutAnyOrigin]:
        var data = OpaquePointer[MutAnyOrigin]()
        check_status(raw_get_dataview_info(env, self.value,
            OpaquePointer[MutAnyOrigin](),
            UnsafePointer(to=data).bitcast[NoneType](),
            OpaquePointer[MutAnyOrigin](),
            OpaquePointer[MutAnyOrigin]()))
        return data.bitcast[Byte]()

    def data_ptr(self, b: Bindings, env: NapiEnv) raises -> UnsafePointer[Byte, MutAnyOrigin]:
        var data = OpaquePointer[MutAnyOrigin]()
        check_status(raw_get_dataview_info(b, env, self.value,
            OpaquePointer[MutAnyOrigin](),
            UnsafePointer(to=data).bitcast[NoneType](),
            OpaquePointer[MutAnyOrigin](),
            OpaquePointer[MutAnyOrigin]()))
        return data.bitcast[Byte]()

    ## arraybuffer — get the underlying ArrayBuffer
    def arraybuffer(self, env: NapiEnv) raises -> NapiValue:
        var ab = NapiValue()
        check_status(raw_get_dataview_info(env, self.value,
            OpaquePointer[MutAnyOrigin](),
            OpaquePointer[MutAnyOrigin](),
            UnsafePointer(to=ab).bitcast[NoneType](),
            OpaquePointer[MutAnyOrigin]()))
        return ab

    def arraybuffer(self, b: Bindings, env: NapiEnv) raises -> NapiValue:
        var ab = NapiValue()
        check_status(raw_get_dataview_info(b, env, self.value,
            OpaquePointer[MutAnyOrigin](),
            OpaquePointer[MutAnyOrigin](),
            UnsafePointer(to=ab).bitcast[NoneType](),
            OpaquePointer[MutAnyOrigin]()))
        return ab

    ## is_dataview — check if a napi_value is a DataView
    @staticmethod
    def is_dataview(env: NapiEnv, val: NapiValue) raises -> Bool:
        var result: Bool = False
        check_status(raw_is_dataview(env, val,
            UnsafePointer(to=result).bitcast[NoneType]()))
        return result

    @staticmethod
    def is_dataview(b: Bindings, env: NapiEnv, val: NapiValue) raises -> Bool:
        var result: Bool = False
        check_status(raw_is_dataview(b, env, val,
            UnsafePointer(to=result).bitcast[NoneType]()))
        return result
