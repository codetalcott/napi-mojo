# napi-mojo

[![CI](https://github.com/codetalcott/napi-mojo/actions/workflows/test.yml/badge.svg)](https://github.com/codetalcott/napi-mojo/actions/workflows/test.yml)

Build Node.js native addons in [Mojo](https://www.modular.com/mojo) — the Mojo
equivalent of Rust's [napi-rs](https://napi.rs).

napi-mojo is a **source framework**, the way `node-addon-api` is for C++: your
addon compiles against it with `mojo build -I <include>`. The package's JS
entry exposes the paths your build needs; the compiled demonstration addon
(the binary this repo's 650+-test suite runs against) lives behind a subpath:

```js
const napiMojo = require("napi-mojo");
napiMojo.include; //   …/node_modules/napi-mojo/src — pass to `mojo build -I`
napiMojo.generator; // the TOML → Mojo code generator

const demo = require("napi-mojo/demo"); // prebuilt demo addon
demo.hello(); // "Hello from Mojo!"
demo.add(2, 3); // 5
demo.greet("world"); // "Hello, world!"
```

## Project Status

**Alpha** — napi-mojo is under active development and not yet proven in
production. The API covers the full N-API v10 surface (153 exported functions, 5
classes, 650+ tests). Expect breaking changes as the project matures.

- **Goal:** Become the Mojo equivalent of Rust's [napi-rs](https://napi.rs) — a
  complete, ergonomic framework for building Node.js native addons in Mojo.
  We're not there yet; reaching that bar requires exhaustive real-world testing
  and community feedback. The third prerequisite — a stable Mojo language
  release — arrived with Mojo 1.0.0, which this project now builds against.
- **Mojo compatibility:** Builds against **Mojo 1.0.0** (stable), pinned in
  [`pixi.toml`](pixi.toml) as `max = "==26.5.0"`. napi-mojo ships Mojo source
  that your addon compiles against, so the framework tracks *stable* language
  releases rather than nightlies — pinning a nightly would force every consumer
  onto that exact nightly. A twice-weekly Nightly Canary builds and tests
  against the newest nightly to catch breaking changes ahead of the next
  release.
- **What works:** Core N-API bindings, type wrappers, async work, classes, error
  handling, TypeScript definition generation, and a TOML-driven code generator
  with `mojo_fn` auto-trampolines, nullable returns, and struct-to-object
  mapping — all validated by the test suite.
- **What's missing:** Production hardening, cross-platform prebuild
  distribution (currently darwin-arm64 + linux-x64 only), and documentation
  beyond this README and the generated `.d.ts`.
- **Performance vs napi-rs:** measured — **median 0.42x**, i.e. about 2.4x
  faster per call. See [Performance](#performance) for the method and caveats.

## Two directions

Most native-addon frameworks serve one direction: JavaScript calls a fast
native function. napi-mojo does that, and also the inverse — a Mojo **program**
that drives Node, using the JavaScript runtime and npm as its standard library.

```bash
napi-mojo build lib.mojo    # JS calls Mojo   — an addon Node requires
napi-mojo run  main.mojo    # Mojo calls JS   — a program Node hosts
```

Host mode needs no N-API boilerplate. You write `mojo_main`; `napi-mojo run`
generates the registration wrapper and launches Node on a bootstrap that calls
it:

```mojo
def mojo_main(b: Bindings, env: NapiEnv, ctx: NapiValue) raises -> NapiValue:
    var host = NodeHost.from_context(b, env, ctx)

    var fs = host.require("fs")
    var args = List[NapiValue]()
    args.append(JsString.create(b, env, "input.txt").value)
    args.append(JsString.create(b, env, "utf8").value)
    var text = fs.call_method(b, env, "readFileSync", args)

    host.console_log("read " + js_to_string(b, env, text))
    return JsNumber.create_int(b, env, 0).value   # becomes the exit code
```

```bash
napi-mojo init myprog --host && cd myprog && napi-mojo run main.mojo
```

[`examples/host/pipeline.mojo`](examples/host/pipeline.mojo) is the demo worth
reading: Mojo computes statistics over 200,000 samples, Node does the JSON,
the gzip and the file write, and the samples themselves never cross the
boundary.

`ctx` carries `{ require, argv, cwd }` from the bootstrap. `require` is
module-scoped in Node and is *not* reachable through `globalThis`, so the
bootstrap hands it in rather than Mojo scavenging for it. See
[`examples/host/`](examples/host/) and
[`docs/plan-bidirectional.md`](https://github.com/codetalcott/napi-mojo/blob/main/docs/plan-bidirectional.md) for the design.

**Two hosts, one language.** For a standalone Mojo binary that owns `main()`
and needs no Node at all, there is [`mojo-http`](https://github.com/codetalcott/mojo-http)
— an HTTP/1.1 server and web framework for Mojo. The two are complements, not
competitors, and share no build-time dependency:

| | owns `main()` | reaches npm | deployment |
|---|---|---|---|
| **mojo-http** | Mojo | no | standalone binary |
| **napi-mojo run** | Node | yes | Node + a `.node` |

Pick by whether you need the ecosystem more than you need the standalone
binary.

**What it costs.** Measured on darwin-arm64 / Node 24 (`node scripts/benchmark.mjs`), a full
JS -> Mojo -> JS -> Mojo -> JS round trip through `callN(fn, [])` is ~435 ns,
against ~375 ns for a forward-only call like `hello()`. So the Mojo -> JS call
itself is not the expensive part — **argument marshalling is**: `callN` with
three arguments costs ~735 ns, i.e. roughly **~100 ns per value crossing the
boundary**. A `this`-bound `callMethod` with one argument is ~680 ns.

The practical rule that follows: host mode is right for I/O-bound glue, where a
syscall dwarfs a few hundred nanoseconds, and wrong for a hot numeric loop.
Keep data on the Mojo side and cross the boundary with few, coarse values
rather than many fine ones.

**What host mode cannot do:** Mojo has no `await`. A JS function returning a
Promise hands Mojo a *pending* Promise it cannot suspend on. Use synchronous
APIs (`readFileSync`), or pass a continuation — build a Mojo callback with
`JsFunction.create` and give it to `.then()`; `mojo_main` returns, the event
loop runs, and the callback fires later.

## Features

- **153 exported functions** and **5 classes** covering the full **N-API v10** surface (Node.js 22.12+ / 24+)
- Primitives: strings, numbers (Float64/Int32/UInt32/Int64), booleans, null,
  undefined, BigInt, Symbol, Date
- Objects: create, read/write properties, enumerate keys, freeze/seal, prototype
  access
- Arrays: create, map, element access, has/delete
- Functions: call, create from Mojo, closures with captured data —
  `call0`/`call1`/`call2` plus `call_n` for runtime-length argument lists and
  `call_with` for an explicit `this`
- **Node as a host** (`napi-mojo run`): `NodeHost.require()` to load any
  builtin or npm package from Mojo, `JsObject.call_method` for correctly-bound
  method calls, `with_handle_scope` for Mojo-driven loops that call JS
- Binary data: ArrayBuffer, Buffer (including zero-copy slice from ArrayBuffer), TypedArray, DataView, external (Mojo-owned) memory
- Classes: constructors, instance methods, getters/setters, static methods,
  inheritance
- Async: Promises, worker thread execution, ThreadsafeFunction (call JS from
  worker threads)
- Error handling: Error/TypeError/RangeError, throw/catch any value, exception
  propagation
- References, handle scopes, escapable handle scopes, GC finalizers
- Type coercion, strict equality, instanceof, external data with GC cleanup
- **Typed wrappers**: `JsExternal.create_typed[T]` / `get_typed[T]` and
  `set_instance_data[T]` / `get_instance_data[T]` — stash typed Mojo structs
  behind N-API handles or per-env singletons without hand-writing
  alloc/init/finalize/bitcast plumbing
- Auto-generated TypeScript definitions
- **TOML code generator** (`npm run generate:addon` + `src/exports.toml`):
  - `mojo_fn` auto-trampolines — write a pure Mojo function, declare it in
    TOML, and the generator creates type-checked N-API callbacks with zero
    boilerplate
  - **Nullable returns** — `returns = "number?"` generates `Optional[T]` →
    `T | null` in JS/TS
  - **Struct-to-object mapping** — `[structs.*]` TOML sections define typed
    JS object shapes, generating bidirectional Mojo struct ↔ JS object
    converters (the Mojo equivalent of napi-rs `#[napi(object)]`)
  - Async function generation, class generation (constructor + methods +
    getters/setters + statics), auto-generated TypeScript `.d.ts` with
    interfaces
- **Ergonomic API**: `ModuleBuilder`/`ClassBuilder` for registration, `fn_ptr()`
  helper, `unwrap_native[T]()` for class methods, `ToJsValue`/`FromJsValue`
  conversion traits, `AsyncWork` helpers, `MojoFloat64Array` for zero-copy
  TypedArray output, and `parallelize_safe()` for SIMD parallel computation

## Installation

```bash
npm install napi-mojo
```

The install gives you:

- **The `napi-mojo` CLI** — scaffold, generate, and build addons (below).
- **The framework source** (`require('napi-mojo').include`) — compile your
  addon against it: `mojo build --emit shared-lib -I <include> lib.mojo -o addon.node`
- **The code generators** (`require('napi-mojo').generator`) — declare your
  exports in TOML, generate the N-API trampolines. See
  [`examples/codegen/`](examples/codegen/) for a worked example.
- **The demo addon** (`require('napi-mojo/demo')`) — prebuilt for
  **darwin-arm64** and **linux-x64** (Node.js 22.12+ / N-API v10) so you can
  poke at a napi-mojo-built binary without a Mojo toolchain. On other
  platforms the demo throws on load; the framework itself works anywhere Mojo
  does.

### Build your own addon (CLI)

`init` scaffolds a `pixi.toml` pinned to the Mojo version this framework is
tested against, so with [pixi](https://pixi.sh) installed the sequence below
needs no other toolchain setup — the first build provisions the compiler.
Already have `mojo` on your PATH? Delete that file. Want a different compiler?
Pass `--mojo "<command>"` or set `NAPI_MOJO_MOJO`.

```bash
npx napi-mojo init my-addon && cd my-addon
npx napi-mojo generate --dts index.d.ts   # exports.toml → generated/ + index.d.ts
npx napi-mojo build                       # lib.mojo → build/index.node
node -e "console.log(require('./build/index.node').greet('world'))"
```

Declare functions in `exports.toml`, implement them as pure Mojo in
`fns.mojo`, rerun `generate`. `napi-mojo build --bundle` additionally copies
the Mojo runtime libraries next to the `.node` and rewrites its load paths, so
the result runs on machines with no Mojo installation (this is how the demo
packages on npm are produced).

**API reference:** [docs/api/](docs/api/) documents the framework surface your
addon calls into — `JsObject`, `CbArgs`, the error helpers — generated from the
Mojo docstrings. It covers the consumer-facing core today and names the modules
that are not yet documented rather than rendering empty pages for them.

**New here? [docs/TUTORIAL.md](docs/TUTORIAL.md)** walks the whole path — a
function, a nullable return, a struct in both directions, async work on a
worker thread, and a class — building [`examples/tutorial/`](examples/tutorial),
which CI compiles and calls on both platforms.

See [`examples/`](examples/) for runnable scripts.

### Building from source

```bash
git clone https://github.com/codetalcott/napi-mojo.git
cd napi-mojo
npm install
npm run build    # compiles Mojo → build/index.node + generates TypeScript defs
npm test         # full Jest suite (7 GC tests need `npm run test:gc`)
```

**Prerequisites:** [Mojo 1.0.0](https://mojolang.org/install/) via
[pixi](https://pixi.sh) (exact version pinned in [`pixi.toml`](pixi.toml);
`npm run build` provisions it from the stable `max` conda channel
automatically), Node.js 22.12+ (N-API v10)

**pixi 0.73 or newer is required** — `pixi.lock` is lockfile format v7, which
older pixi cannot read. A fresh clone on pixi 0.66 fails at `pixi install` with
a lockfile-version error rather than anything that points at this project.

## Usage Examples

### Primitives and type coercion

```js
const m = require("napi-mojo/demo");

m.add(2.5, 3.7); // 6.2
m.addInts(10, 20); // 30  (Int32)
m.addBigInts(1n, 2n); // 3n
m.isPositive(42); // true
m.coerceToString(123); // "123"
m.strictEquals(1, 1); // true
```

### Objects and properties

```js
const obj = m.makeGreeting(); // { message: "Hello!" }
m.getProperty(obj, "message"); // "Hello!"
m.getKeys({ a: 1, b: 2 }); // ["a", "b"]
m.freezeObject({ x: 1 }); // frozen object
m.hasOwn({ a: 1 }, "a"); // true

const sym = m.createSymbol("key");
m.setPropertyByKey(obj, sym, 42); // set symbol-keyed property
```

### Async and promises

```js
const result = await m.asyncDouble(21); // 42  (computed on worker thread)

// Call JS from a worker thread via ThreadsafeFunction
const values = [];
await m.asyncProgress(3, (i) => values.push(i));
// values: [0, 1, 2]
```

### Classes

```js
const counter = new m.Counter(10);
counter.value; // 10
counter.increment();
counter.value; // 11
m.Counter.isCounter(counter); // true

const dog = new m.Dog("Rex", "Labrador");
dog.name; // "Rex"  (inherited from Animal)
dog.breed; // "Labrador"
dog.speak(); // "Rex says hello"
```

### Binary data

```js
const ab = m.createArrayBuffer(8); // 8-byte ArrayBuffer
const buf = m.createBuffer(4); // Node.js Buffer
const f64 = new Float64Array(ab);
m.doubleFloat64Array(f64); // doubles each element in-place

const dv = m.createDataView(ab, 0, 8); // DataView over ArrayBuffer
m.getDataViewInfo(dv); // { byteLength: 8, byteOffset: 0 }
```

## Code Generator

The TOML code generator eliminates N-API boilerplate. Write a pure Mojo function,
declare it in `src/exports.toml`, and run `npm run generate:addon` — the generator
creates type-checked callbacks, struct converters, and TypeScript definitions
automatically.

### Bind a pure Mojo function (`mojo_fn`)

```toml
# src/exports.toml
[functions.square]
js_name = "square"
args = ["number"]
returns = "number"
mojo_fn = "square_pure"
```

```mojo
# src/addon/user_fns.mojo
def square_pure(x: Float64) -> Float64:
    return x * x
```

Supported type tokens: `number`, `string`, `boolean`/`bool`, `int32`, `uint32`,
`int64`, `object`, `array`, `number[]`, `string[]`, `any`, any declared struct
and its array form `<struct>[]`, plus the zero-copy binary tokens
`float64array` (argument and return) and `buffer` (argument only). Append `?` to a return type to map `Optional[T]` to `T | null`. On an
argument, `?` accepts null/undefined: converting tokens (number, string,
boolean, the integer tokens, declared structs) arrive as `Optional[T]`, while
`any?`/`object?`/`array?` pass the raw value through. `number[]`,
`float64array` and `buffer` have no meaningful Optional form and are refused.

### Async returns

`returns` accepts `number`, `int32`, `uint32`, `int64` and `string` for
`async = true`. A `string` result is allocated by `execute_body` on the
worker thread and consumed by the generated completion callback on the main
thread, which is also where its destructor runs.

### Classes with native state

```toml
[classes.tally]
js_name = "Tally"
state = "tally_state"            # a declared [structs.*]
constructor_args = ["number"]
constructor_mojo_fn = "tally_new"

[classes.tally.instance_methods.add]
args = ["number"]
returns = "number"
mojo_fn = "tally_add"            # def tally_add(mut s: TallyStateData, n: Float64) -> Float64
```

The generator heap-allocates the struct, wraps it onto the instance with a
128-bit type tag derived from the class name, hands the unwrapped state to
every `mojo_fn` member, and emits the GC finalizer. Borrowing a method onto a
foreign object is a TypeError, not a reinterpret. `mojo_fn` on setters and
static methods is rejected (no instance to unwrap); use `body`.

### Nullable returns (`Optional[T]` → `T | null`)

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

```js
safeDivide(10, 2); // 5
safeDivide(10, 0); // null
```

### Struct-to-object mapping (`[structs.*]`)

Define a typed JS object shape and get bidirectional Mojo struct ↔ JS object
converters — the Mojo equivalent of napi-rs `#[napi(object)]`:

```toml
[structs.config]
js_name = "Config"
[structs.config.fields]
host = "string"
port = "number"
verbose = "boolean"

[functions.process_config]
js_name = "processConfig"
args = ["config"]
returns = "string"
mojo_fn = "process_config_pure"
```

```mojo
from generated.structs import ConfigData

def process_config_pure(c: ConfigData) -> String:
    return c.host + ":" + String(Int(c.port))
```

Generates TypeScript:

```ts
export interface Config { host: string; port: number; verbose: boolean; }
export function processConfig(arg0: Config): string;
```

### Other generator features

- **Async functions**: `async = true` + `execute_body` for worker-thread computation
- **Classes**: `[classes.*]` with constructor, instance methods, getters/setters,
  static methods
- **Inline body**: Use `body` instead of `mojo_fn` for callbacks that need direct
  N-API access

See `src/exports.toml` for the full set of examples.

## API Reference

Full typed API: [`build/index.d.ts`](build/index.d.ts) — auto-generated on every
build, works in any TypeScript-aware IDE.

| Category | Exports |
| --- | --- |
| Math & arithmetic | `add` `addInts` `bitwiseOr` `addIntsStrict` `addBigInts` `sumArgs` `isPositive` |
| Strings | `hello` `greet` `toJsString` `createPropertyKey` `createExternalString` |
| Objects | `createObject` `makeGreeting` `getProperty` `getKeys` `hasOwn` `deleteProperty` `setPropertyByKey` `hasPropertyByKey` `freezeObject` `sealObject` `getPrototype` |
| Arrays | `sumArray` `mapArray` `arrayHasElement` `arrayDeleteElement` |
| Binary data | `createArrayBuffer` `createBuffer` `createBufferCopy` `bufferFromArrayBuffer` `doubleFloat64Array` `createTypedArrayView` `createDataView` `createExternalArrayBuffer` |
| Async & promises | `asyncDouble` `asyncTriple` `asyncProgress` `resolveWith` `rejectWith` `cancelAsyncWork` |
| Callbacks | `callFunction` `createCallback` `createAdder` `makeCallback` `makeCallback0` `makeCallback2` |
| Classes | `Counter` (increment/reset/value) · `Animal` (name/speak) · `Dog` (breed) |
| BigInt / Symbol / Date | `createSymbol` `symbolFor` `addBigInts` `bigIntFromWords` `bigIntToWords` `createDate` `getDateValue` |
| Type checks & coercion | `strictEquals` `isInstanceOf` `coerceToBool` `coerceToNumber` `coerceToString` `coerceToObject` `isExternal` `isError` `isDataView` |
| Errors | `throwTypeError` `throwRangeError` `throwSyntaxError` `throwValue` `catchAndReturn` |
| GC & lifecycle | `createExternal` `attachFinalizer` `setInstanceData` `getInstanceData` `addCleanupHook` `removeCleanupHook` |
| Runtime introspection | `getGlobal` `getNapiVersion` `getNodeVersion` `runScript` `adjustExternalMemory` |
| Code-generated | `square` `clamp` `uppercase` `sumArrayPure` `negateBoolPure` `addInt32Pure` `describePure` `reverseStringsPure` `safeDivide` `findName` `echoConfig` `configSummary` `exampleAdd` `exampleGreet` `exampleIsPositive` `exampleClamp` `asyncSum` `ExamplePoint` |

## Performance

Per-call boundary overhead against [napi-rs](https://napi.rs), same Node
process, same timing harness, verified-identical function semantics
(darwin-arm64, Node 24, best of 5 interleaved rounds):

| call | napi-mojo | napi-rs | ratio |
|---|---|---|---|
| `isPositive(42)` | 27.9 ns | 91.6 ns | 0.30x |
| `createObject()` | 35.1 ns | 101.5 ns | 0.35x |
| `add(1, 2)` | 35.8 ns | 97.5 ns | 0.37x |
| `getNull()` | 18.9 ns | 33.7 ns | 0.56x |
| `hello()` | 31.9 ns | 52.5 ns | 0.61x |
| `makeGreeting()` | 188.2 ns | 278.0 ns | 0.68x |

**Median 0.42x** — about 2.4x faster than napi-rs on these microbenchmarks.
Full table and method in [`bench/napi-rs/README.md`](bench/napi-rs/README.md);
reproduce with `node bench/napi-rs/compare.mjs`.

This is a recent change, and the honest version of the story is that napi-mojo
was **3.95x slower** until the measurement itself found the cause. The delta
against napi-rs was flat at ~330 ns across calls whose absolute cost varied 8x
— a constant tax, not a scaling one. It was the per-callback bootstrap: reading
a callback's data requires `napi_get_cb_info`, whose pointer could not come
from the cache it was fetching, so every call ran `dlopen(NULL)` + `dlsym`
(~346 ns). That single symbol is now held in a module-private data-segment slot
(see `src/napi/global_cache.mojo`), and the tax is gone.

Caveats worth knowing: this measures **binding-layer overhead only** — nothing
here says anything about Mojo versus Rust as languages. And the gap narrows as
the callee does more work (`makeGreeting()` at 0.68x), because fixed overhead
is what is being removed.

## Architecture

1. `mojo build --emit shared-lib` produces a `.dylib`/`.so` renamed to `.node`
2. Node.js calls `dlopen` on the `.node` file, then
   `dlsym("napi_register_module_v1")`
3. Our exported Mojo function registers all callbacks via
   `napi_define_properties`
4. Each callback acts as a `napi_callback`: receives `(env, cbinfo)`, returns
   `napi_value`
5. N-API symbols are resolved at runtime from the host process via
   `dlopen(NULL)`

In host mode the same machinery runs in reverse: `napi-mojo run` emits a
wrapper that registers `mojo_main` as an ordinary export, plus a CJS bootstrap
that `require()`s the built `.node` and calls it with
`{ require, argv, cwd }`. Node is still the process; Mojo is the program.

## Development

```bash
npm run build        # compile + generate TypeScript defs
npm test             # run the full Jest suite
npm run test:gc      # run the 7 GC finalizer tests (needs --expose-gc)
npm run generate:addon  # regenerate src/generated/ from src/exports.toml
npx jest tests/basic.test.js   # run a single test file
npm run generate:docs  # HTML API docs for the DEMO ADDON → docs/api-demo-addon/
                       # (requires: npm i -D typedoc). A reference for the
                       # framework itself is scoped in docs/plan-api-reference.md
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for coding standards and
[docs/METHODOLOGY.md](https://github.com/codetalcott/napi-mojo/blob/main/docs/METHODOLOGY.md) for the TDD workflow.

## License

[MIT](LICENSE)
