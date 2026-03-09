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
