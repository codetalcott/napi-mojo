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

from std.memory import alloc
from napi.types import NapiEnv, NapiValue, NAPI_TYPE_STRING
from napi.raw import (
    raw_create_string_utf8,
    raw_get_value_string_utf8,
    raw_get_value_string_latin1,
    raw_create_property_key_utf8,
    raw_create_external_string_latin1,
)
from napi.error import check_status
from napi.bindings import Bindings
from napi.framework.args import CbArgs
from napi.framework.js_value import js_typeof
from napi.framework.js_coerce import js_coerce_to_string


## Latin1Buf — heap-allocated Latin-1 byte buffer returned by JsString.read_latin1
##
## Holds a pointer and length. The caller owns the pointer and must free it.
struct Latin1Buf(Movable):
    var ptr: UnsafePointer[UInt8, MutAnyOrigin]
    var length: UInt

    def __init__(
        out self, ptr: UnsafePointer[UInt8, MutAnyOrigin], length: UInt
    ):
        self.ptr = ptr
        self.length = length

    def __moveinit__(out self, deinit take: Self):
        self.ptr = take.ptr
        self.length = take.length


## JsString — typed wrapper for a JavaScript string napi_value
struct JsString:
    ## The underlying napi_value handle. Valid within the current handle scope.
    var value: NapiValue

    def __init__(out self, value: NapiValue):
        self.value = value

    ## create — construct a JsString from a Mojo String (env-only)
    ##
    ## env-only: for async complete, TSFN, finalizer, and except-block callbacks
    ## where NapiBindings is unavailable. Use create(b, env, s) in hot paths.
    ##
    ## Calls napi_create_string_utf8 and checks the status. The input string `s`
    ## must remain alive for the duration of this call (it is borrowed, not copied).
    @staticmethod
    def create(env: NapiEnv, s: String) raises -> JsString:
        var result: NapiValue = NapiValue()
        var str_ptr: OpaquePointer[ImmutAnyOrigin] = s.unsafe_ptr().bitcast[
            NoneType
        ]()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
            to=result
        ).bitcast[NoneType]()
        var status = raw_create_string_utf8(
            env, str_ptr, UInt(len(s)), result_ptr
        )
        check_status(status)
        return JsString(result)

    @staticmethod
    def create(b: Bindings, env: NapiEnv, s: String) raises -> JsString:
        var result: NapiValue = NapiValue()
        var str_ptr: OpaquePointer[ImmutAnyOrigin] = s.unsafe_ptr().bitcast[
            NoneType
        ]()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
            to=result
        ).bitcast[NoneType]()
        var status = raw_create_string_utf8(
            b, env, str_ptr, UInt(len(s)), result_ptr
        )
        check_status(status)
        return JsString(result)

    ## create_literal — construct a JsString from a StringLiteral
    ##
    ## Uses the literal's static (.rodata) pointer directly — no heap allocation.
    ## Preferred over create() when the string content is known at compile time.
    @staticmethod
    def create_literal(env: NapiEnv, s: StringLiteral) raises -> JsString:
        var result: NapiValue = NapiValue()
        var str_ptr: OpaquePointer[ImmutAnyOrigin] = s.unsafe_ptr().bitcast[
            NoneType
        ]()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
            to=result
        ).bitcast[NoneType]()
        var status = raw_create_string_utf8(
            env, str_ptr, UInt(s.byte_length()), result_ptr
        )
        check_status(status)
        return JsString(result)

    @staticmethod
    def create_literal(
        b: Bindings, env: NapiEnv, s: StringLiteral
    ) raises -> JsString:
        var result: NapiValue = NapiValue()
        var str_ptr: OpaquePointer[ImmutAnyOrigin] = s.unsafe_ptr().bitcast[
            NoneType
        ]()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
            to=result
        ).bitcast[NoneType]()
        var status = raw_create_string_utf8(
            b, env, str_ptr, UInt(s.byte_length()), result_ptr
        )
        check_status(status)
        return JsString(result)

    ## from_napi_value — read a NapiValue as a Mojo String
    ##
    ## Optimistic single-pass: tries reading into a 256-byte stack buffer first.
    ## If the string fits (actual < 255), returns immediately — 1 N-API call.
    ## If truncated (actual == 255), falls back to the two-pass heap approach.
    ## Uses String(from_utf8=Span[Byte]) for correct UTF-8 validation.
    ##
    ## The NapiValue must hold a JS string; raises otherwise.
    @staticmethod
    def from_napi_value(env: NapiEnv, val: NapiValue) raises -> String:
        # Optimistic single-pass: read into a 256-byte stack buffer.
        # If actual < 255, the full string fit — return immediately.
        var buf = InlineArray[UInt8, 256](fill=0)
        var actual: UInt = 0
        var buf_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
            to=buf[0]
        ).bitcast[NoneType]()
        var actual_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
            to=actual
        ).bitcast[NoneType]()
        check_status(
            raw_get_value_string_utf8(env, val, buf_ptr, 256, actual_ptr)
        )
        if actual < 255:
            var span = Span[Byte](
                ptr=UnsafePointer(to=buf[0]), length=Int(actual)
            )
            return String(from_utf8=span)

        # Fallback: string >= 255 bytes. Two-pass with size query + read.
        var null = OpaquePointer[MutAnyOrigin]()
        var needed: UInt = 0
        var needed_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
            to=needed
        ).bitcast[NoneType]()
        check_status(raw_get_value_string_utf8(env, val, null, 0, needed_ptr))

        if needed < 4096:
            var buf2 = InlineArray[UInt8, 4096](fill=0)
            var actual2: UInt = 0
            var buf2_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
                to=buf2[0]
            ).bitcast[NoneType]()
            var actual2_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
                to=actual2
            ).bitcast[NoneType]()
            check_status(
                raw_get_value_string_utf8(
                    env, val, buf2_ptr, needed + 1, actual2_ptr
                )
            )
            var span = Span[Byte](
                ptr=UnsafePointer(to=buf2[0]), length=Int(actual2)
            )
            return String(from_utf8=span)
        else:
            var heap_buf = alloc[UInt8](Int(needed + 1))
            try:
                var actual2: UInt = 0
                var heap_ptr: OpaquePointer[MutAnyOrigin] = heap_buf.bitcast[
                    NoneType
                ]()
                var actual2_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
                    to=actual2
                ).bitcast[NoneType]()
                check_status(
                    raw_get_value_string_utf8(
                        env, val, heap_ptr, needed + 1, actual2_ptr
                    )
                )
                var span = Span[Byte](ptr=heap_buf, length=Int(actual2))
                var result = String(from_utf8=span)
                heap_buf.free()
                return result
            except e:
                heap_buf.free()
                raise e^

    @staticmethod
    def from_napi_value(
        b: Bindings, env: NapiEnv, val: NapiValue
    ) raises -> String:
        # Optimistic single-pass: read into a 256-byte stack buffer.
        var buf = InlineArray[UInt8, 256](fill=0)
        var actual: UInt = 0
        var buf_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
            to=buf[0]
        ).bitcast[NoneType]()
        var actual_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
            to=actual
        ).bitcast[NoneType]()
        check_status(
            raw_get_value_string_utf8(b, env, val, buf_ptr, 256, actual_ptr)
        )
        if actual < 255:
            var span = Span[Byte](
                ptr=UnsafePointer(to=buf[0]), length=Int(actual)
            )
            return String(from_utf8=span)

        # Fallback: string >= 255 bytes. Two-pass with size query + read.
        var null = OpaquePointer[MutAnyOrigin]()
        var needed: UInt = 0
        var needed_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
            to=needed
        ).bitcast[NoneType]()
        check_status(
            raw_get_value_string_utf8(b, env, val, null, 0, needed_ptr)
        )

        if needed < 4096:
            var buf2 = InlineArray[UInt8, 4096](fill=0)
            var actual2: UInt = 0
            var buf2_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
                to=buf2[0]
            ).bitcast[NoneType]()
            var actual2_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
                to=actual2
            ).bitcast[NoneType]()
            check_status(
                raw_get_value_string_utf8(
                    b, env, val, buf2_ptr, needed + 1, actual2_ptr
                )
            )
            var span = Span[Byte](
                ptr=UnsafePointer(to=buf2[0]), length=Int(actual2)
            )
            return String(from_utf8=span)
        else:
            var heap_buf = alloc[UInt8](Int(needed + 1))
            try:
                var actual2: UInt = 0
                var heap_ptr: OpaquePointer[MutAnyOrigin] = heap_buf.bitcast[
                    NoneType
                ]()
                var actual2_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
                    to=actual2
                ).bitcast[NoneType]()
                check_status(
                    raw_get_value_string_utf8(
                        b, env, val, heap_ptr, needed + 1, actual2_ptr
                    )
                )
                var span = Span[Byte](ptr=heap_buf, length=Int(actual2))
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
    def read_arg_0(env: NapiEnv, info: NapiValue) raises -> String:
        var arg0 = CbArgs.get_one(env, info)
        return JsString.from_napi_value(env, arg0)

    @staticmethod
    def read_arg_0(b: Bindings, env: NapiEnv, info: NapiValue) raises -> String:
        var arg0 = CbArgs.get_one(b, env, info)
        return JsString.from_napi_value(b, env, arg0)

    ## read_latin1 — read a JS string as Latin-1 bytes into a heap buffer
    ##
    ## Returns the Latin-1 data as a Latin1Buf (pointer + length). The caller OWNS
    ## the pointer and must call ptr.free() when done. Each JS character that fits
    ## in Latin-1 (U+0000–U+00FF) maps to one byte; characters outside that range
    ## are replaced by the engine.
    ##
    ## This is the correct way to obtain data for node_api_create_external_string_latin1,
    ## which expects Latin-1 bytes — NOT UTF-8 bytes.
    @staticmethod
    def read_latin1(
        b: Bindings, env: NapiEnv, val: NapiValue
    ) raises -> Latin1Buf:
        # Size query: null buf + 0 bufsize → writes required byte count
        var needed: UInt = 0
        var needed_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
            to=needed
        ).bitcast[NoneType]()
        check_status(
            raw_get_value_string_latin1(
                b, env, val, OpaquePointer[MutAnyOrigin](), 0, needed_ptr
            )
        )
        # Allocate buffer (+ 1 for null terminator that napi writes)
        var buf = alloc[UInt8](Int(needed + 1))
        var actual: UInt = 0
        var actual_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
            to=actual
        ).bitcast[NoneType]()
        check_status(
            raw_get_value_string_latin1(
                b, env, val, buf.bitcast[NoneType](), needed + 1, actual_ptr
            )
        )
        return Latin1Buf(buf, actual)

    ## create_property_key — create an engine-internalized string for property access (N-API v10)
    ##
    ## Returns a JS string that V8 interns, making repeated napi_get/set_property
    ## calls with the same key faster than using regular strings. The returned value
    ## behaves exactly like a regular JS string (typeof === 'string').
    @staticmethod
    def create_property_key(
        b: Bindings, env: NapiEnv, s: String
    ) raises -> JsString:
        var result: NapiValue = NapiValue()
        var str_ptr: OpaquePointer[ImmutAnyOrigin] = s.unsafe_ptr().bitcast[
            NoneType
        ]()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
            to=result
        ).bitcast[NoneType]()
        check_status(
            raw_create_property_key_utf8(
                b, env, str_ptr, UInt(len(s)), result_ptr
            )
        )
        return JsString(result)

    ## create_property_key_literal — create an internalized property key from a StringLiteral (N-API v10)
    ##
    ## Uses the literal's static pointer — no heap allocation. Preferred when the key
    ## is a compile-time constant (e.g., object field names in hot loops).
    @staticmethod
    def create_property_key_literal(
        b: Bindings, env: NapiEnv, s: StringLiteral
    ) raises -> JsString:
        var result: NapiValue = NapiValue()
        var str_ptr: OpaquePointer[ImmutAnyOrigin] = s.unsafe_ptr().bitcast[
            NoneType
        ]()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
            to=result
        ).bitcast[NoneType]()
        check_status(
            raw_create_property_key_utf8(
                b, env, str_ptr, UInt(s.byte_length()), result_ptr
            )
        )
        return JsString(result)

    ## create_external_latin1 — zero-copy JS string from a native Latin-1 buffer (N-API v10)
    ##
    ## The returned JS string directly references the caller's buffer — no copy occurs
    ## unless the engine cannot accommodate the external reference (in which case
    ## finalize_cb is called immediately). The buffer must remain valid until
    ## finalize_cb fires.
    ##
    ## finalize_cb:   fn(env, data, hint) — called when the string is GC'd or copied
    ## finalize_hint: opaque pointer passed unchanged to finalize_cb (may be null)
    @staticmethod
    def create_external_latin1(
        b: Bindings,
        env: NapiEnv,
        data: OpaquePointer[ImmutAnyOrigin],
        length: UInt,
        finalize_cb: OpaquePointer[MutAnyOrigin],
        finalize_hint: OpaquePointer[MutAnyOrigin],
    ) raises -> JsString:
        var result: NapiValue = NapiValue()
        var result_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
            to=result
        ).bitcast[NoneType]()
        var copied: Bool = False
        var copied_ptr: OpaquePointer[MutAnyOrigin] = UnsafePointer(
            to=copied
        ).bitcast[NoneType]()
        check_status(
            raw_create_external_string_latin1(
                b,
                env,
                data,
                length,
                finalize_cb,
                finalize_hint,
                result_ptr,
                copied_ptr,
            )
        )
        return JsString(result)


## js_to_string — convert any JavaScript value to a Mojo String
##
## If val is already a JS string, reads it directly via from_napi_value.
## Otherwise coerces via napi_coerce_to_string (equivalent to String(val)
## in JavaScript) then reads the result. Throws TypeError on Symbol values.
def js_to_string(env: NapiEnv, val: NapiValue) raises -> String:
    if js_typeof(env, val) == NAPI_TYPE_STRING:
        return JsString.from_napi_value(env, val)
    var coerced = js_coerce_to_string(env, val)
    return JsString.from_napi_value(env, coerced)


def js_to_string(b: Bindings, env: NapiEnv, val: NapiValue) raises -> String:
    if js_typeof(b, env, val) == NAPI_TYPE_STRING:
        return JsString.from_napi_value(b, env, val)
    var coerced = js_coerce_to_string(b, env, val)
    return JsString.from_napi_value(b, env, coerced)
