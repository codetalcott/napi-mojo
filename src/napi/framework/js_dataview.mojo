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
    @__allow_legacy_any_origin_fields
    var value: NapiValue

    def __init__(out self, value: NapiValue):
        self.value = value

    @staticmethod
    def create(
        b: Bindings,
        env: NapiEnv,
        byte_length: UInt,
        arraybuffer: NapiValue,
        byte_offset: UInt,
    ) raises -> JsDataView:
        var result = NapiValue(unsafe_from_address=Int(0))
        check_status(
            raw_create_dataview(
                b,
                env,
                byte_length,
                arraybuffer,
                byte_offset,
                Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        return JsDataView(result)

    def byte_length(self, b: Bindings, env: NapiEnv) raises -> UInt:
        var length: UInt = 0
        check_status(
            raw_get_dataview_info(
                b,
                env,
                self.value,
                Pointer(to=length).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0)),
                OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0)),
                OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0)),
            )
        )
        return length

    def byte_offset(self, b: Bindings, env: NapiEnv) raises -> UInt:
        var offset: UInt = 0
        check_status(
            raw_get_dataview_info(
                b,
                env,
                self.value,
                OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0)),
                OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0)),
                OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0)),
                Pointer(to=offset).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
            )
        )
        return offset

    def data_ptr(
        self, b: Bindings, env: NapiEnv
    ) raises -> Pointer[Byte, MutAnyOrigin]:
        var data = OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0))
        check_status(
            raw_get_dataview_info(
                b,
                env,
                self.value,
                OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0)),
                Pointer(to=data).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0)),
                OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0)),
            )
        )
        return data.unsafe_bitcast[Byte]()

    def arraybuffer(self, b: Bindings, env: NapiEnv) raises -> NapiValue:
        var ab = NapiValue(unsafe_from_address=Int(0))
        check_status(
            raw_get_dataview_info(
                b,
                env,
                self.value,
                OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0)),
                OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0)),
                Pointer(to=ab).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
                OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(0)),
            )
        )
        return ab

    @staticmethod
    def is_dataview(b: Bindings, env: NapiEnv, val: NapiValue) raises -> Bool:
        var result: Bool = False
        check_status(
            raw_is_dataview(
                b, env, val, Pointer(to=result).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
            )
        )
        return result
