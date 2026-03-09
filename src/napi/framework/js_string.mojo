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
## from_napi_value uses a fast stack buffer for strings up to 4095 bytes
## and falls back to heap allocation for larger strings.

from memory import alloc
from napi.types import NapiEnv, NapiValue, NAPI_TYPE_STRING
from napi.raw import raw_create_string_utf8, raw_get_value_string_utf8
from napi.error import check_status
from napi.bindings import Bindings
from napi.framework.args import CbArgs
from napi.framework.js_value import js_typeof
from napi.framework.js_coerce import js_coerce_to_string

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

    @staticmethod
    fn create(b: Bindings, env: NapiEnv, s: String) raises -> JsString:
        var result: NapiValue = NapiValue()
        var str_ptr: OpaquePointer[ImmutAnyOrigin] = s.unsafe_ptr().bitcast[NoneType]()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
        var status = raw_create_string_utf8(b, env, str_ptr, UInt(len(s)), result_ptr)
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

    @staticmethod
    fn create_literal(b: Bindings, env: NapiEnv, s: StringLiteral) raises -> JsString:
        var result: NapiValue = NapiValue()
        var str_ptr: OpaquePointer[ImmutAnyOrigin] = s.unsafe_ptr().bitcast[NoneType]()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=result).bitcast[NoneType]()
        var status = raw_create_string_utf8(b, env, str_ptr, UInt(s.byte_length()), result_ptr)
        check_status(status)
        return JsString(result)

    ## from_napi_value — read a NapiValue as a Mojo String
    ##
    ## Calls napi_get_value_string_utf8 (two-call pattern: size query first,
    ## then read). Uses a fast 4096-byte stack buffer for short strings and
    ## falls back to heap allocation for strings >= 4096 bytes. Constructs
    ## the result using String(from_utf8=Span[Byte]), which validates UTF-8
    ## and correctly handles all Unicode characters including multi-byte sequences.
    ##
    ## The NapiValue must hold a JS string; raises otherwise.
    @staticmethod
    fn from_napi_value(env: NapiEnv, val: NapiValue) raises -> String:
        # Size query — call with NULL buf to get the byte length needed.
        var null = OpaquePointer[MutAnyOrigin]()
        var needed: UInt = 0
        var needed_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=needed).bitcast[NoneType]()
        check_status(raw_get_value_string_utf8(env, val, null, 0, needed_ptr))

        if needed < 4096:
            # Fast path: stack-allocated buffer for common short strings.
            var buf = InlineArray[UInt8, 4096](fill=0)
            var actual: UInt = 0
            var buf_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=buf[0]).bitcast[NoneType]()
            var actual_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=actual).bitcast[NoneType]()
            check_status(raw_get_value_string_utf8(env, val, buf_ptr, needed + 1, actual_ptr))
            var span = Span[Byte](ptr=UnsafePointer(to=buf[0]), length=Int(actual))
            return String(from_utf8=span)
        else:
            # Slow path: heap-allocated buffer for large strings.
            var heap_buf = alloc[UInt8](Int(needed + 1))
            try:
                var actual: UInt = 0
                var heap_ptr: OpaquePointer[MutAnyOrigin] = heap_buf.bitcast[NoneType]()
                var actual_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=actual).bitcast[NoneType]()
                check_status(raw_get_value_string_utf8(env, val, heap_ptr, needed + 1, actual_ptr))
                var span = Span[Byte](ptr=heap_buf, length=Int(actual))
                var result = String(from_utf8=span)
                heap_buf.free()
                return result
            except e:
                heap_buf.free()
                raise e^

    @staticmethod
    fn from_napi_value(b: Bindings, env: NapiEnv, val: NapiValue) raises -> String:
        var null = OpaquePointer[MutAnyOrigin]()
        var needed: UInt = 0
        var needed_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=needed).bitcast[NoneType]()
        check_status(raw_get_value_string_utf8(b, env, val, null, 0, needed_ptr))

        if needed < 4096:
            var buf = InlineArray[UInt8, 4096](fill=0)
            var actual: UInt = 0
            var buf_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=buf[0]).bitcast[NoneType]()
            var actual_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=actual).bitcast[NoneType]()
            check_status(raw_get_value_string_utf8(b, env, val, buf_ptr, needed + 1, actual_ptr))
            var span = Span[Byte](ptr=UnsafePointer(to=buf[0]), length=Int(actual))
            return String(from_utf8=span)
        else:
            var heap_buf = alloc[UInt8](Int(needed + 1))
            try:
                var actual: UInt = 0
                var heap_ptr: OpaquePointer[MutAnyOrigin] = heap_buf.bitcast[NoneType]()
                var actual_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(to=actual).bitcast[NoneType]()
                check_status(raw_get_value_string_utf8(b, env, val, heap_ptr, needed + 1, actual_ptr))
                var span = Span[Byte](ptr=heap_buf, length=Int(actual))
                var result = String(from_utf8=span)
                heap_buf.free()
                return result
            except e:
                heap_buf.free()
                raise e^

    ## read_arg_0 — read the first callback argument as a Mojo String
    ##
    ## Extracts the first argument via CbArgs.get_one, then delegates to
    ## from_napi_value to read it. Raises on any N-API failure.
    @staticmethod
    fn read_arg_0(env: NapiEnv, info: NapiValue) raises -> String:
        var arg0 = CbArgs.get_one(env, info)
        return JsString.from_napi_value(env, arg0)

    @staticmethod
    fn read_arg_0(b: Bindings, env: NapiEnv, info: NapiValue) raises -> String:
        var arg0 = CbArgs.get_one(b, env, info)
        return JsString.from_napi_value(b, env, arg0)

## js_to_string — convert any JavaScript value to a Mojo String
##
## If val is already a JS string, reads it directly via from_napi_value.
## Otherwise coerces via napi_coerce_to_string (equivalent to String(val)
## in JavaScript) then reads the result. Throws TypeError on Symbol values.
fn js_to_string(env: NapiEnv, val: NapiValue) raises -> String:
    if js_typeof(env, val) == NAPI_TYPE_STRING:
        return JsString.from_napi_value(env, val)
    var coerced = js_coerce_to_string(env, val)
    return JsString.from_napi_value(env, coerced)

fn js_to_string(b: Bindings, env: NapiEnv, val: NapiValue) raises -> String:
    if js_typeof(b, env, val) == NAPI_TYPE_STRING:
        return JsString.from_napi_value(b, env, val)
    var coerced = js_coerce_to_string(b, env, val)
    return JsString.from_napi_value(b, env, coerced)
