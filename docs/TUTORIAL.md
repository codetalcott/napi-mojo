# Build your first addon

A napi-mojo addon is three files: a **declaration file** listing what
JavaScript should see, a **pure Mojo file** with your actual logic, and an
**entry point** that registers the two. You never write an N-API callback by
hand — the generator does that, including argument type checking and error
propagation.

Sections 1–3 walk through exactly what `napi-mojo init` scaffolds; from
section 4 on, the addon grows into [`examples/tutorial/`](../examples/tutorial).
Every Mojo and TOML snippet below is quoted verbatim from one of those two, and
CI generates, compiles and calls both on macOS and Linux on every pull request
— so a snippet that stops working fails the build instead of quietly misleading
you.

**Prerequisites:** Node.js 22.12 or newer (N-API v10), and the Mojo toolchain —
either [pixi](https://pixi.sh) with a `pixi.toml` in scope, or `mojo` on your
`PATH`. Installing napi-mojo's own prebuilt demo needs no Mojo; building *your*
addon does.

## 1. Scaffold

```bash
npx napi-mojo init hello-addon
cd hello-addon
```

You get:

```
exports.toml    what JavaScript sees — functions, structs, classes
fns.mojo        your logic, in pure Mojo. No N-API here.
lib.mojo        the entry point. You will not need to edit it.
```

`lib.mojo` is the only file that touches N-API directly: it resolves all 142
N-API symbols once into a `NapiBindings` struct, hands that to the generated
callbacks, and registers them. If symbol resolution fails — an old Node, say —
it throws from `require()` instead of returning an empty object.

## 2. Generate, build, run

```bash
npx napi-mojo generate --dts index.d.ts   # exports.toml -> generated/ + types
npx napi-mojo build                       # lib.mojo    -> build/index.node
node -e "console.log(require('./build/index.node').greet('world'))"
# Hello, world!
```

`generate` writes `generated/callbacks.mojo` (the N-API trampolines) and
`generated/structs.mojo`. Both are derived — regenerate them, don't edit them,
and keep `generated/` out of version control.

Rerun `generate` whenever you change `exports.toml`, then `build`.

## 3. A function

Declaring a function has two halves. In `exports.toml`:

```toml
extra_imports = ["from fns import greet_pure, add_pure"]

[functions.greet]
js_name = "greet"
args = ["string"]
returns = "string"
mojo_fn = "greet_pure"
```

and in `fns.mojo`:

```mojo
def greet_pure(name: String) -> String:
    return "Hello, " + name + "!"
```

`mojo_fn` is the name of the pure function to call; `extra_imports` is how the
generated file reaches it. The generated callback checks the argument type
before conversion, so `greet(42)` throws a descriptive `TypeError` —
`greet: expected string for arg 1, got number` — and never reaches your Mojo.

Supported argument and return tokens: `number`, `string`, `boolean`/`bool`,
`int32`, `uint32`, `int64`, `object`, `array`, `number[]`, `string[]`, `any`,
any struct you declare (and its array form, `<struct>[]`), and the zero-copy
binary tokens `float64array` and `buffer` (section 8). The full reference lives in the
[README's Code Generator section](../README.md#code-generator).

## 4. Returning null

A `?` suffix on the **return** type maps Mojo's `Optional[T]` to `T | null`:

```toml
[functions.safe_divide]
js_name = "safeDivide"
args = ["number", "number"]
returns = "number?"
mojo_fn = "safe_divide_pure"
```

```mojo
def safe_divide_pure(a: Float64, b: Float64) -> Optional[Float64]:
    if b == 0.0:
        return None
    return a / b
```

`safeDivide(9, 3)` returns `3`; `safeDivide(1, 0)` returns `null`, and the
generated `.d.ts` says `number | null`.

`?` works on an **argument** too, and means what it says:

```toml
[functions.greet_maybe]
js_name = "greetMaybe"
args = ["string?"]
returns = "string"
mojo_fn = "greet_maybe"
```

```mojo
def greet_maybe(name: Optional[String]) -> String:
    if name:
        return "Hello, " + name.value() + "!"
    return "Hello, whoever you are!"
```

JS `null` and `undefined` both arrive as `None`; anything else is converted,
and a wrong type still gets the descriptive `TypeError` — the check sits
inside the null test rather than replacing it. Works for `number`, `string`,
`boolean`, the integer tokens and declared structs. `number[]`,
`float64array` and `buffer` are refused, because an absent array is just an
empty one and an absent zero-copy view has no buffer. `any?`, `object?` and
`array?` keep passing the raw value straight through.

## 5. Objects, both directions

A `[structs.*]` table declares a JS object shape. You get a Mojo struct, both
converters, and a TypeScript `interface`:

```toml
[structs.config]
js_name = "Config"
[structs.config.fields]
host = "string"
port = "number"
verbose = "boolean"

[functions.describe_config]
js_name = "describeConfig"
args = ["config"]
returns = "string"
mojo_fn = "describe_config_pure"
```

The struct name (`config`) is now a valid type token anywhere a type is
expected. In `fns.mojo`, import the generated type:

```mojo
from generated.structs import ConfigData


def describe_config_pure(c: ConfigData) -> String:
    var summary = c.host + ":" + String(Int(c.port))
    if c.verbose:
        return summary + " (verbose)"
    return summary
```

```js
describeConfig({ host: 'localhost', port: 8080, verbose: true })
// 'localhost:8080 (verbose)'
```

Declaring the struct also gives you `config[]` — an array of them — in either
position, with no further declaration:

```toml
[functions.verbose_only]
js_name = "verboseOnly"
args = ["config[]"]
returns = "config[]"
mojo_fn = "verbose_only"
```

```mojo
def verbose_only(cs: List[ConfigData]) -> List[ConfigData]:
    var out = List[ConfigData]()
    for i in range(len(cs)):
        if cs[i].verbose:
            out.append(ConfigData(copy=cs[i]))
    return out^
```

The generated struct implements the framework's `ToJsValue`/`FromJsValue`
traits, and the array converters are generic over those — so the array form
costs nothing extra. TypeScript sees `Config[]`.

## 6. Work off the main thread

`async = true` runs your work on a worker thread and returns a `Promise`.
Instead of `mojo_fn`, you write an `execute_body` that operates on a generated
data struct:

```toml
[functions.async_product]
js_name = "asyncProduct"
args = ["number", "number"]
returns = "number"
async = true
execute_body = """
ptr[].result = ptr[].input0 * ptr[].input1
"""
```

```js
await asyncProduct(6, 7)   // 42
```

**`execute_body` runs on a worker thread, so it must not call N-API** — no
`JsString`, no `JsObject`, nothing touching `env`. It reads `ptr[].input0…N`
and writes `ptr[].result`, and that is all. The generated completion callback
runs back on the main thread and resolves the promise for you.

Async returns can be numeric (`number`, `int32`, `uint32`, `int64`) or
`string`; a string result is built on the worker thread and turned into a JS
string by the completion callback. Other tokens are refused, because the data
struct has to hold the value across the thread boundary. Argument count is not
limited.

## 7. A class with native state

A class can keep real Mojo data instead of stashing values as JS properties.
Name a declared struct as its `state`, and the generator heap-allocates it,
wraps it onto the instance, and hands it to every member:

```toml
[structs.tally_state]
js_name = "TallyState"
[structs.tally_state.fields]
total = "number"

[classes.tally]
js_name = "Tally"
state = "tally_state"
constructor_args = ["number"]
constructor_mojo_fn = "tally_new"

[classes.tally.instance_methods.add]
args = ["number"]
returns = "number"
mojo_fn = "tally_add"

[classes.tally.getters.total]
returns = "number"
mojo_fn = "tally_total"
```

```mojo
def tally_new(initial: Float64) -> TallyStateData:
    return TallyStateData(initial)


def tally_add(mut s: TallyStateData, n: Float64) -> Float64:
    s.total += n
    return s.total


def tally_total(s: TallyStateData) -> Float64:
    return s.total
```

```js
const t = new Tally(100);
t.add(5)   // 105
t.total    // 105
```

A mutating method takes the state `mut`; a getter borrows it. The allocation
belongs to JavaScript once the constructor returns — its garbage collector
runs the generated finalizer.

**Every instance is stamped with a 128-bit type tag**, and each member checks
it before unwrapping. That is what makes
`Tally.prototype.add.call(somethingElse)` a `TypeError` rather than a
reinterpret of unrelated memory — the failure mode is otherwise reachable from
plain JavaScript. The tag is derived from the class name, so regenerating
produces identical output.

`mojo_fn` is not available on setters or static methods yet; both are
rejected with that message rather than silently ignored. Use `body` there.

## 7b. A class without native state

```toml
[classes.counter]
js_name = "Counter"
constructor_args = ["number"]
constructor_body = """
JsObject(this_val).set_named_property(_b, env, "_n", arg0)
"""

[classes.counter.getters.value]
returns = "number"
body = """
return JsObject(this_val).get_named_property(_b, env, "_n")
"""

[classes.counter.instance_methods.plus]
args = ["number"]
returns = "number"
body = """
var current = JsNumber.from_napi_value(_b, env, JsObject(this_val).get_named_property(_b, env, "_n"))
var addend = JsNumber.from_napi_value(_b, env, arg0)
return JsNumber.create(_b, env, current + addend).value
"""
```

```js
const c = new Counter(10);
c.value    // 10
c.plus(5)  // 15
```

Without `state`, class members use `body` rather than `mojo_fn`: the body is spliced into the
generated callback, where `this_val` is the instance, `env` is the N-API
environment, and `_b` is the cached bindings pointer that every framework call
takes as its first argument. Getters, setters, static methods and inheritance
are all available — see the README.

**Argument names depend on arity.** With exactly one argument the generated
local is `arg0`; with two to four it is `args[0]`…`args[3]`. Using the wrong
one is a compile error (`use of unknown declaration 'args'`), not a silent
bug — which is why the tutorial's addon is compiled by CI rather than
transcribed by hand.

## 8. Zero-copy binary data

`float64array` hands your Mojo function a `Span` that aliases the JavaScript
`Float64Array`'s own memory — no copy on the way in. Returning a
`MojoFloat64Array` hands its buffer to JavaScript the same way: JS adopts the
allocation and its garbage collector frees it, so there is no copy out either.

```toml
[functions.scale_vec]
js_name = "scaleVec"
args = ["float64array", "number"]
returns = "float64array"
mojo_fn = "scale_vec"
```

```mojo
def scale_vec(v: Span[Float64, MutAnyOrigin], k: Float64) -> MojoFloat64Array:
    var out = MojoFloat64Array(len(v))
    for i in range(len(v)):
        out.ptr[unsafe_offset=i] = v[i] * k
    return out^
```

```js
scaleVec(new Float64Array([1, 2, 3]), 10)   // Float64Array [10, 20, 30]
```

**The input Span is only valid for the duration of the call.** It points into
memory owned by the JavaScript engine, which makes no promise about that
memory once your function returns — so do not store the Span, and do not hand
it to anything that outlives the call.

`buffer` gives you a `Span[Byte]` over a Node `Buffer` on the same terms. It is
argument-only: there is no Mojo-owned `Buffer` type to hand back without
copying, so `returns = "buffer"` is rejected rather than silently copying.

## 9. Ship it

```bash
npx napi-mojo build --bundle
```

`--bundle` copies the Mojo runtime libraries next to your `.node` and rewrites
its load paths, so the result runs on a machine with no Mojo installed. That is
what makes an addon publishable to npm: your users install a binary, not a
toolchain.

## Where to go next

- **[README — Code Generator](../README.md#code-generator)** — the full token
  and declaration reference.
- **[docs/EXPORTS.md](EXPORTS.md)** — every export of the demo addon, which is
  itself generated from `src/exports.toml`.
- **Hand-written callbacks** — the declarative surface does not cover
  everything. `ArrayBuffer`, `DataView`, non-Float64 TypedArrays, symbols and
  BigInt are reachable only from a hand-written callback using the framework
  directly; [`examples/hello-addon.mojo`](../examples/hello-addon.mojo) shows
  the minimal pattern, and `src/addon/` is the worked reference.
