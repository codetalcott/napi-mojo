## src/addon/user_fns.mojo — pure Mojo functions called via mojo_fn trampolines
##
## These are plain Mojo functions with no N-API dependencies.
## The code generator (scripts/generate-addon.mjs) wraps them with
## type-checked N-API trampolines based on exports.toml declarations.

from std.collections import Optional

def square_pure(x: Float64) -> Float64:
    return x * x

def clamp_pure(val: Float64, lo: Float64, hi: Float64) -> Float64:
    if val < lo:
        return lo
    if val > hi:
        return hi
    return val

## uppercase_pure — ASCII uppercase (a-z → A-Z, other bytes unchanged)
def uppercase_pure(s: String) raises -> String:
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
def sum_array_pure(items: List[Float64]) -> Float64:
    var total: Float64 = 0.0
    for i in range(len(items)):
        total += items[i]
    return total

## safe_divide_pure — returns None on division by zero
def safe_divide_pure(a: Float64, b: Float64) -> Optional[Float64]:
    if b == 0.0:
        return None
    return a / b

## find_name_pure — returns None if index out of bounds
def find_name_pure(items: List[String], idx: Float64) -> Optional[String]:
    var i = Int(idx)
    if i < 0 or i >= len(items):
        return None
    return items[i]

## negate_bool_pure — boolean negation
def negate_bool_pure(b: Bool) -> Bool:
    return not b

## add_int32_pure — Int32 addition
def add_int32_pure(a: Int32, b: Int32) -> Int32:
    return a + b

## describe_pure — mixed types: string + number → string
def describe_pure(name: String, age: Float64) -> String:
    return name + " is " + String(Int(age))

## reverse_strings_pure — reverse a list of strings
def reverse_strings_pure(items: List[String]) -> List[String]:
    var result = List[String]()
    var n = len(items)
    for i in range(n):
        result.append(items[n - 1 - i])
    return result^
