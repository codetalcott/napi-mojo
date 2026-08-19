## tests/codegen/fns.mojo — pure Mojo functions for the kitchen-sink mojo_fn
## trampolines (see kitchen-sink.toml). Compile-only: none of these run.

from std.collections import Optional
from napi.types import NapiValue
from generated.structs import KsConfigData
from napi.framework.js_mojo_array import MojoFloat64Array


def ks_zero() -> Float64:
    return 42.0


def ks_echo_string(s: String) -> String:
    return s


def ks_not(b: Bool) -> Bool:
    return not b


def ks_neg_i32(v: Int32) -> Int32:
    return -v


def ks_inc_u32(v: UInt32) -> UInt32:
    return v + 1


def ks_neg_i64(v: Int64) -> Int64:
    return -v


def ks_object_passthrough(v: NapiValue) -> NapiValue:
    return v


def ks_sum_f64_list(xs: List[Float64]) -> Float64:
    var total: Float64 = 0.0
    for i in range(len(xs)):
        total += xs[i]
    return total


def ks_double_f64_list(xs: List[Float64]) -> List[Float64]:
    var out = List[Float64]()
    for i in range(len(xs)):
        out.append(xs[i] * 2.0)
    return out^


def ks_join_str_list(xs: List[String]) -> String:
    var out = String("")
    for i in range(len(xs)):
        out += xs[i]
    return out


def ks_wrap_str_list(s: String) -> List[String]:
    var out = List[String]()
    out.append(s)
    return out^


def ks_maybe_number(v: Float64) -> Optional[Float64]:
    if v < 0.0:
        return None
    return v


def ks_maybe_string(v: Float64) -> Optional[String]:
    if v < 0.0:
        return None
    return String("ok")


def ks_sum2(a: Float64, b: Float64) -> Float64:
    return a + b


def ks_sum3(a: Float64, b: Float64, c: Float64) -> Float64:
    return a + b + c


def ks_sum4(a: Float64, b: Float64, c: Float64, d: Float64) -> Float64:
    return a + b + c + d


def ks_sum5(a: Float64, b: Float64, c: Float64, d: Float64, e: Float64) -> Float64:
    return a + b + c + d + e


def ks_sum6(
    a: Float64, b: Float64, c: Float64, d: Float64, e: Float64, f: Float64
) -> Float64:
    return a + b + c + d + e + f


def ks_config_roundtrip(c: KsConfigData) -> KsConfigData:
    # Construct fresh (field order = TOML declaration order) rather than
    # relying on implicit struct copy of a borrowed param.
    return KsConfigData(
        c.label, c.ratio, c.flag, c.enabled, c.small, c.index, c.big,
        c.obj, c.val, c.b, c.env,
    )


## --- Binary tokens: zero-copy views over JS memory ---
## float64array hands the Mojo fn a Span aliasing the JS backing store, and
## takes a MojoFloat64Array back (JS adopts that buffer). buffer is a
## Span[Byte] view and is argument-only.
def ks_scale_vec(v: Span[Float64, MutAnyOrigin], k: Float64) -> MojoFloat64Array:
    var out = MojoFloat64Array(len(v))
    for i in range(len(v)):
        out.ptr[unsafe_offset=i] = v[i] * k
    return out^


def ks_byte_sum(bytes: Span[Byte, MutAnyOrigin]) -> Float64:
    var total: Float64 = 0.0
    for i in range(len(bytes)):
        total += Float64(Int(bytes[i]))
    return total


## --- Struct arrays, via the parametric converters ---
## Works because the generated struct implements ToJsValue/FromJsValue;
## from_js_array/to_js_array are generic over those traits.
def ks_config_list_roundtrip(cs: List[KsConfigData]) -> List[KsConfigData]:
    var out = List[KsConfigData]()
    for i in range(len(cs)):
        out.append(KsConfigData(copy=cs[i]))
    return out^
