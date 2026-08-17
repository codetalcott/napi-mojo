## tests/codegen/fns.mojo — pure Mojo functions for the kitchen-sink mojo_fn
## trampolines (see kitchen-sink.toml). Compile-only: none of these run.

from std.collections import Optional
from napi.types import NapiValue
from generated.structs import KsConfigData


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
        c.label, c.ratio, c.flag, c.enabled, c.small, c.index, c.big
    )
