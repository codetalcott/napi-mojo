## src/napi/framework/js_string.mojo — ergonomic wrapper for JavaScript string values
##
## JsString hides the raw pointer operations needed to create and read JS strings:
##
##   # Create a JS string from Mojo:
##   var s = JsString.create(env, "Hello!")
##   return s.value
##
##   # Create a JS string from a StringLiteral (no heap allocation):
##   var s = JsString.create_literal(env, "Hello!")
##   return s.value
##
##   # Read a NapiValue as a Mojo String:
##   var name = JsString.from_napi_value(env, napi_val)
##
##   # Read the first callback argument as a Mojo String:
##   var name = JsString.read_arg_0(env, info)
##
## String lifetime: JsString.create() borrows the input Mojo String for the
## duration of the N-API call. The underlying napi_value is owned by the
## Node.js GC and valid until the current handle scope is collected.
##
## Buffer limit: from_napi_value reads into a fixed 4096-byte stack buffer.
## Strings longer than 4095 UTF-8 bytes (not characters) raise an error.

from napi.types import NapiEnv, NapiValue
from napi.raw import raw_create_string_utf8, raw_get_value_string_utf8
from napi.error import check_status
from napi.framework.args import CbArgs

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

    ## create_literal — construct a JsString from a StringLiteral
    ##
    ## Uses the literal's static (.rodata) pointer directly — no heap allocation.
    ## Preferred over create() when the string content is known at compile time.
    @staticmethod
    fn create_literal(env: NapiEnv, s: StringLiteral) raises -> JsString:
        var result: NapiValue = NapiValue()
        var str_ptr: OpaquePointer[ImmutAnyOrigin] = s.unsafe_ptr().bitcast[NoneType]()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
        var status = raw_create_string_utf8(env, str_ptr, UInt(s.byte_length()), result_ptr)
        check_status(status)
        return JsString(result)

    ## from_napi_value — read a NapiValue as a Mojo String
    ##
    ## Calls napi_get_value_string_utf8 (two-call pattern: size query first,
    ## then actual read into a fixed 4096-byte stack buffer). Constructs the
    ## result using String(from_utf8=Span[Byte]), which validates UTF-8 and
    ## correctly handles all Unicode characters including multi-byte sequences.
    ##
    ## The NapiValue must hold a JS string; raises otherwise.
    ## Raises if the string exceeds 4095 UTF-8 bytes.
    @staticmethod
    fn from_napi_value(env: NapiEnv, val: NapiValue) raises -> String:
        # Size query — call with NULL buf to get the byte length needed.
        var null = OpaquePointer[MutAnyOrigin]()
        var needed: UInt = 0
        var needed_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=needed).bitcast[NoneType]()
        check_status(raw_get_value_string_utf8(env, val, null, 0, needed_ptr))

        # Guard: reject strings that exceed the fixed stack buffer.
        if needed >= 4096:
            raise Error("string argument too long (max 4095 bytes)")

        # Read into a fixed 4096-byte stack buffer.
        # needed+1 to include space for the null terminator.
        var buf = InlineArray[UInt8, 4096](fill=0)
        var actual: UInt = 0
        var buf_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=buf[0]).bitcast[NoneType]()
        var actual_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=actual).bitcast[NoneType]()
        check_status(raw_get_value_string_utf8(env, val, buf_ptr, needed + 1, actual_ptr))

        # Construct a UTF-8 String directly from the byte span.
        # String(from_utf8=...) validates the encoding and handles all Unicode
        # characters correctly. N-API guarantees UTF-8 output.
        var span = Span[Byte](ptr=UnsafePointer(to=buf[0]), length=Int(actual))
        return String(from_utf8=span)

    ## read_arg_0 — read the first callback argument as a Mojo String
    ##
    ## Extracts the first argument via CbArgs.get_one, then delegates to
    ## from_napi_value to read it. Raises on any N-API failure.
    @staticmethod
    fn read_arg_0(env: NapiEnv, info: NapiValue) raises -> String:
        var arg0 = CbArgs.get_one(env, info)
        return JsString.from_napi_value(env, arg0)
