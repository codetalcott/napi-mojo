## src/addon/user_fns.mojo — pure Mojo functions called via mojo_fn trampolines
##
## These are plain Mojo functions with no N-API dependencies.
## The code generator (scripts/generate-addon.mjs) wraps them with
## type-checked N-API trampolines based on exports.toml declarations.

fn square_pure(x: Float64) -> Float64:
    return x * x

fn clamp_pure(val: Float64, lo: Float64, hi: Float64) -> Float64:
    if val < lo:
        return lo
    if val > hi:
        return hi
    return val

## uppercase_pure — ASCII uppercase (a-z → A-Z, other bytes unchanged)
fn uppercase_pure(s: String) raises -> String:
    var bytes = s.as_bytes()
    var result = List[UInt8](capacity=len(bytes))
    for i in range(len(bytes)):
        var b = bytes[i]
        if b >= 97 and b <= 122:
            result.append(b - 32)
        else:
            result.append(b)
    var span = Span[Byte](ptr=result.unsafe_ptr(), length=len(result))
    return String(from_utf8=span)

## sum_array_pure — sum all elements of a Float64 list
fn sum_array_pure(items: List[Float64]) -> Float64:
    var total: Float64 = 0.0
    for i in range(len(items)):
        total += items[i]
    return total
