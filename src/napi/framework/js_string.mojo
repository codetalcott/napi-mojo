## src/napi/framework/js_string.mojo — ergonomic wrapper for JavaScript string values
##
## JsString hides the raw pointer operations needed to create and read JS strings:
##
##   # Create a JS string from Mojo:
##   var s = JsString.create(env, "Hello!")
##   return s.value
##
##   # Read the first callback argument as a Mojo String:
##   var name = JsString.read_arg_0(env, info)
##
## String lifetime: JsString.create() borrows the input Mojo String for the
## duration of the N-API call. The underlying napi_value is owned by the
## Node.js GC and valid until the current handle scope is collected.

from napi.types import NapiEnv, NapiValue
from napi.raw import raw_create_string_utf8, raw_get_cb_info, raw_get_value_string_utf8
from napi.error import check_status

## JsString — typed wrapper for a JavaScript string napi_value
struct JsString:
    ## The underlying napi_value handle. Valid within the current handle scope.
    var value: NapiValue

    fn __init__(out self, value: NapiValue):
        self.value = value

    ## create — construct a JsString from a Mojo String
    ##
    ## Calls napi_create_string_utf8 and checks the status. The input string `s`
    ## must remain alive for the duration of this call (it is borrowed, not copied).
    @staticmethod
    fn create(env: NapiEnv, s: String) raises -> JsString:
        var result: NapiValue = NapiValue()
        var str_ptr: OpaquePointer[ImmutAnyOrigin] = s.unsafe_ptr().bitcast[NoneType]()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
        var status = raw_create_string_utf8(env, str_ptr, UInt(len(s)), result_ptr)
        check_status(status)
        return JsString(result)

    ## read_arg_0 — read the first callback argument as a Mojo String
    ##
    ## Calls napi_get_cb_info to extract the first argument, then reads its
    ## UTF-8 content via napi_get_value_string_utf8 (two-call pattern:
    ## size query first, then actual read into a fixed 1024-byte stack buffer).
    ##
    ## Raises on any N-API failure or if no argument is provided.
    @staticmethod
    fn read_arg_0(env: NapiEnv, info: NapiValue) raises -> String:
        # Step 1: extract the first argument NapiValue from callback info.
        # argv_ptr points to arg0 — napi_get_cb_info writes the napi_value there.
        var argc: UInt = 1
        var arg0: NapiValue = NapiValue()
        var argc_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=argc).bitcast[NoneType]()
        var argv_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=arg0).bitcast[NoneType]()
        var null = OpaquePointer[MutAnyOrigin]()
        check_status(raw_get_cb_info(env, info, argc_ptr, argv_ptr, null, null))

        # Step 2: size query — call with NULL buf to get the byte length needed.
        var needed: UInt = 0
        var needed_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=needed).bitcast[NoneType]()
        check_status(raw_get_value_string_utf8(env, arg0, null, 0, needed_ptr))

        # Step 3: read into a fixed 1024-byte stack buffer.
        # needed+1 to include space for the null terminator.
        var buf = InlineArray[UInt8, 1024](fill=0)
        var actual: UInt = 0
        var buf_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=buf[0]).bitcast[NoneType]()
        var actual_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=actual).bitcast[NoneType]()
        check_status(raw_get_value_string_utf8(env, arg0, buf_ptr, needed + 1, actual_ptr))

        # Step 4: build a Mojo String from the buffer bytes.
        # Build byte-by-byte — safe in v26.2, sufficient for Phase 5a.
        var s = String()
        for i in range(Int(actual)):
            s += chr(Int(buf[i]))
        return s
