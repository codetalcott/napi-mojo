## examples/m0-session/lib.mojo — m0's session and grant code, compiled into a
## Node addon through `napi-mojo build -I`.
##
## m0 (mojo-http's application framework, published to PyPI as the `m0`
## wheel) issues signed session cookies and verifies stream grants in Mojo. A
## Node service beside an m0 application (a BFF, an admin panel, a WebSocket
## service) can check the same cookies with this addon, running m0's own code
## rather than a JavaScript copy of the format kept in step by hand. Nothing
## here was written for napi-mojo: the wheel ships its Mojo source under
## m0/_mojo, and -I puts that directory after the framework's.
##
##   pip download m0==0.2.0 --no-deps -d /tmp/m0
##   python3 -m zipfile -e /tmp/m0/m0-0.2.0-py3-none-any.whl /tmp/m0
##   napi-mojo build examples/m0-session/lib.mojo -I /tmp/m0/m0/_mojo \
##       -o examples/m0-session/build/index.node
##   node --test examples/m0-session/parity.mjs
##
## The clock is always an argument, as it is in m0: `now` and `exp` are Unix
## seconds, so every verification is a pure function of what it is given.

from std.collections import Optional
from std.memory.alloc import unsafe_alloc

from m0_core import fnv1a, xxhash32
from m0_http.grant import GrantKeys, grant_key_id, session_binding, verify_grant
from m0_http.session import SessionKeys, issue_session, verify_session

from napi.types import (
    NapiEnv,
    NapiValue,
    NAPI_TYPE_NULL,
    NAPI_TYPE_NUMBER,
    NAPI_TYPE_STRING,
    NAPI_TYPE_UNDEFINED,
)
from napi.bindings import Bindings, NapiBindings, init_bindings
from napi.error import throw_js_error, throw_js_error_dynamic
from napi.framework.args import CbArgs
from napi.framework.js_array import JsArray
from napi.framework.js_boolean import JsBoolean
from napi.framework.js_number import JsNumber
from napi.framework.js_object import JsObject
from napi.framework.js_string import JsString
from napi.framework.js_value import js_is_array, js_typeof
from napi.framework.register import fn_ptr, ModuleBuilder


# --- Arguments ----------------------------------------------------------------
# Each check raises a message naming the function and the argument, which the
# callback throws to JavaScript as it stands.

comptime MAX_SAFE_INTEGER: Float64 = 9007199254740991.0


def _string(b: Bindings, env: NapiEnv, val: NapiValue, what: String) raises -> String:
    if js_typeof(b, env, val) != NAPI_TYPE_STRING:
        raise Error(what, " must be a string")
    return JsString.from_napi_value(b, env, val)


def _whole(b: Bindings, env: NapiEnv, val: NapiValue, what: String) raises -> Int64:
    if js_typeof(b, env, val) != NAPI_TYPE_NUMBER:
        raise Error(what, " must be a whole number")
    var n = JsNumber.from_napi_value(b, env, val)
    # The comparison is false for NaN, so NaN is refused here too.
    if not (n >= -MAX_SAFE_INTEGER and n <= MAX_SAFE_INTEGER):
        raise Error(what, " must be a whole number")
    var whole = n.cast[DType.int64]()
    if whole.cast[DType.float64]() != n:
        raise Error(what, " must be a whole number")
    return whole


def _keys(b: Bindings, env: NapiEnv, val: NapiValue, what: String) raises -> List[String]:
    if not js_is_array(b, env, val):
        raise Error(what, " must be an array of key strings")
    var arr = JsArray(val)
    var out = List[String]()
    for i in range(Int(arr.length(b, env))):
        out.append(_string(b, env, arr.get(b, env, UInt32(i)), String(what, "[", i, "]")))
    return out^


def _grant_keys(b: Bindings, env: NapiEnv, val: NapiValue, what: String) raises -> GrantKeys:
    var keys = GrantKeys()
    for key in _keys(b, env, val, what):
        keys.add(Span(key.as_bytes()))
    return keys^


def _session_keys(b: Bindings, env: NapiEnv, val: NapiValue, what: String) raises -> SessionKeys:
    var keys = SessionKeys()
    for key in _keys(b, env, val, what):
        keys.add(Span(key.as_bytes()))
    return keys^


def _null_like(b: Bindings, env: NapiEnv, val: NapiValue) raises -> Bool:
    var t = js_typeof(b, env, val)
    return t == NAPI_TYPE_NULL or t == NAPI_TYPE_UNDEFINED


# --- Grants and sessions ------------------------------------------------------


def grant_key_id_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    """`grantKeyId(key)`: the first eight hex characters of the key's SHA-256."""
    try:
        var b = CbArgs.get_bindings(env, info)
        var key = _string(b, env, CbArgs.get_one(b, env, info), "grantKeyId: key")
        return JsString.create(b, env, grant_key_id(Span(key.as_bytes()))).value
    except e:
        throw_js_error_dynamic(env, String(e))
        return NapiValue(unsafe_from_address=Int(0))


def session_binding_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    """`sessionBinding(cookie)`: what a grant's `sb` field binds that cookie value to."""
    try:
        var b = CbArgs.get_bindings(env, info)
        var cookie = _string(b, env, CbArgs.get_one(b, env, info), "sessionBinding: cookie")
        return JsString.create(b, env, session_binding(Span(cookie.as_bytes()))).value
    except e:
        throw_js_error_dynamic(env, String(e))
        return NapiValue(unsafe_from_address=Int(0))


def verify_grant_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    """`verifyGrant(grant, keys, now, cookie?)` -> `{ok, channel, reason}`.

    `cookie` is the session cookie's value, or null (or absent) when the
    request carries none; m0 tells the two apart, so "" is a cookie.
    """
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_three(b, env, info)
        var grant = _string(b, env, args[0], "verifyGrant: grant")
        var keys = _grant_keys(b, env, args[1], "verifyGrant: keys")
        var now = _whole(b, env, args[2], "verifyGrant: now")
        var cookie = Optional[String]()
        if CbArgs.argc(b, env, info) >= 4:
            var fourth = CbArgs.get_four(b, env, info)[3]
            if not _null_like(b, env, fourth):
                cookie = Optional[String](_string(b, env, fourth, "verifyGrant: cookie"))
        var verdict = verify_grant(Span(grant.as_bytes()), keys, now, cookie)
        var out = JsObject.create(b, env)
        out.set_property(b, env, "ok", JsBoolean.create(b, env, verdict.ok).value)
        out.set_property(b, env, "channel", JsString.create(b, env, verdict.channel).value)
        out.set_property(b, env, "reason", JsString.create(b, env, verdict.reason).value)
        return out.value
    except e:
        throw_js_error_dynamic(env, String(e))
        return NapiValue(unsafe_from_address=Int(0))


def issue_session_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    """`issueSession(keys, subject, exp)`: a cookie value signed by the first key.

    Throws m0's own message when it refuses: no key, a negative expiry, or a
    subject that is empty, too long, or holds a byte a cookie cannot carry.
    """
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_three(b, env, info)
        var keys = _session_keys(b, env, args[0], "issueSession: keys")
        var subject = _string(b, env, args[1], "issueSession: subject")
        var exp = _whole(b, env, args[2], "issueSession: exp")
        return JsString.create(b, env, issue_session(keys, subject, exp)).value
    except e:
        throw_js_error_dynamic(env, String(e))
        return NapiValue(unsafe_from_address=Int(0))


def verify_session_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    """`verifySession(cookie, keys, now)` -> `{ok, subject, csrf, reason}`."""
    try:
        var b = CbArgs.get_bindings(env, info)
        var args = CbArgs.get_three(b, env, info)
        var cookie = _string(b, env, args[0], "verifySession: cookie")
        var keys = _session_keys(b, env, args[1], "verifySession: keys")
        var now = _whole(b, env, args[2], "verifySession: now")
        var verdict = verify_session(Span(cookie.as_bytes()), keys, now)
        var out = JsObject.create(b, env)
        out.set_property(b, env, "ok", JsBoolean.create(b, env, verdict.ok).value)
        out.set_property(b, env, "subject", JsString.create(b, env, verdict.subject).value)
        out.set_property(b, env, "csrf", JsString.create(b, env, verdict.csrf).value)
        out.set_property(b, env, "reason", JsString.create(b, env, verdict.reason).value)
        return out.value
    except e:
        throw_js_error_dynamic(env, String(e))
        return NapiValue(unsafe_from_address=Int(0))


# --- Hashes -------------------------------------------------------------------
# m0_core's public hashes take a String and hash its UTF-8 bytes, so a JS
# string crosses as exactly the bytes Buffer.from(text, 'utf8') holds.


def fnv1a_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    """`fnv1a(text)`: 32-bit FNV-1a of the text's UTF-8 bytes."""
    try:
        var b = CbArgs.get_bindings(env, info)
        var text = _string(b, env, CbArgs.get_one(b, env, info), "fnv1a: text")
        return JsNumber.create(b, env, Float64(fnv1a(text))).value
    except e:
        throw_js_error_dynamic(env, String(e))
        return NapiValue(unsafe_from_address=Int(0))


def xxhash32_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    """`xxhash32(text, seed = 0)`: xxHash32 of the text's UTF-8 bytes."""
    try:
        var b = CbArgs.get_bindings(env, info)
        var text = _string(b, env, CbArgs.get_one(b, env, info), "xxhash32: text")
        var seed: UInt32 = 0
        if CbArgs.argc(b, env, info) >= 2:
            var second = CbArgs.get_two(b, env, info)[1]
            if not _null_like(b, env, second):
                var n = _whole(b, env, second, "xxhash32: seed")
                if n < 0 or n > 4294967295:
                    raise Error("xxhash32: seed must be a whole number from 0 to 4294967295")
                seed = UInt32(n)
        return JsNumber.create(b, env, Float64(xxhash32(text, seed))).value
    except e:
        throw_js_error_dynamic(env, String(e))
        return NapiValue(unsafe_from_address=Int(0))


# --- Module entry point -------------------------------------------------------


@export("napi_register_module_v1")
def register_module(env: NapiEnv, exports: NapiValue) abi("C") -> NapiValue:
    var bindings_ptr = unsafe_alloc[NapiBindings](1)
    try:
        var bindings = NapiBindings()
        init_bindings(bindings)
        bindings_ptr.unsafe_write(bindings^)
    except:
        bindings_ptr.unsafe_free()
        throw_js_error(env, "m0-session: failed to resolve N-API symbols")
        return exports
    var cb_data = bindings_ptr.unsafe_bitcast[NoneType]().as_unsafe_any_origin()

    var grant_key_id_ref = grant_key_id_fn
    var session_binding_ref = session_binding_fn
    var verify_grant_ref = verify_grant_fn
    var issue_session_ref = issue_session_fn
    var verify_session_ref = verify_session_fn
    var fnv1a_ref = fnv1a_fn
    var xxhash32_ref = xxhash32_fn

    try:
        var m = ModuleBuilder(env, exports, cb_data)
        m.method("grantKeyId", fn_ptr(grant_key_id_ref))
        m.method("sessionBinding", fn_ptr(session_binding_ref))
        m.method("verifyGrant", fn_ptr(verify_grant_ref))
        m.method("issueSession", fn_ptr(issue_session_ref))
        m.method("verifySession", fn_ptr(verify_session_ref))
        m.method("fnv1a", fn_ptr(fnv1a_ref))
        m.method("xxhash32", fn_ptr(xxhash32_ref))
        m.flush()
    except:
        pass

    return exports
