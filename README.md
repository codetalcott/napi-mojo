# napi-mojo

[![CI](https://github.com/codetalcott/napi-mojo/actions/workflows/test.yml/badge.svg)](https://github.com/codetalcott/napi-mojo/actions/workflows/test.yml)

Build Node.js native addons in [Mojo](https://www.modular.com/mojo) — the Mojo
equivalent of Rust's [napi-rs](https://napi.rs).

```js
const addon = require("napi-mojo");

addon.hello(); // "Hello from Mojo!"
addon.add(2, 3); // 5
addon.greet("world"); // "Hello, world!"
```

## Project Status

**Alpha** — napi-mojo is under active development and not yet proven in
production. The API covers the full N-API v10 surface (140 exported functions, 3
classes, 605 tests). Expect breaking changes as the project matures.

- **Goal:** Become the Mojo equivalent of Rust's [napi-rs](https://napi.rs) — a
  complete, ergonomic framework for building Node.js native addons in Mojo.
  We're not there yet; reaching that bar requires exhaustive real-world testing,
  community feedback, and a stable Mojo language release.
- **Mojo compatibility:** Tracks the latest Mojo nightly (pinned in
  [`pixi.toml`](pixi.toml)). As Mojo approaches v1.0, this project aims to stay
  current with each nightly release. Expect occasional build breakage during
  Mojo language transitions.
- **What works:** Core N-API bindings, type wrappers, async work, classes, error
  handling, TypeScript definition generation, and a TOML-driven code generator
  with `mojo_fn` auto-trampolines, nullable returns, and struct-to-object
  mapping — all validated by the test suite.
- **What's missing:** Production hardening, cross-platform prebuild
  distribution, performance benchmarking against napi-rs, and documentation
  beyond this README and the generated `.d.ts`.

## Features

- **140 exported functions** and **3 classes** covering the full **N-API v10** surface (Node.js 22.12+ / 24+)
- Primitives: strings, numbers (Float64/Int32/UInt32/Int64), booleans, null,
  undefined, BigInt, Symbol, Date
- Objects: create, read/write properties, enumerate keys, freeze/seal, prototype
  access
- Arrays: create, map, element access, has/delete
- Functions: call, create from Mojo, closures with captured data
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

> **Note:** Prebuilt binaries are not yet available. Currently you must build
> from source.

```bash
git clone https://github.com/codetalcott/napi-mojo.git
cd napi-mojo
npm install
npm run build    # compiles Mojo → build/index.node + generates TypeScript defs
npm test         # 605 tests
```

**Prerequisites:** [Mojo nightly](https://docs.modular.com/magic/) via
[pixi](https://pixi.sh) (exact version pinned in [`pixi.toml`](pixi.toml)),
Node.js 22.12+ (N-API v10)

See [`examples/`](examples/) for runnable scripts.

## Usage Examples

### Primitives and type coercion

```js
const m = require("napi-mojo");

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
`int64`, `object`, `array`, `number[]`, `string[]`, `any`. Append `?` to skip
type validation on args.

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

## Development

```bash
npm run build        # compile + generate TypeScript defs
npm test             # run Jest test suite (605 tests)
npm run generate:addon  # regenerate src/generated/ from src/exports.toml
npx jest tests/basic.test.js   # run a single test file
npm run generate:docs  # generate HTML API docs → docs/api/ (requires: npm i -D typedoc)
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for coding standards and
[docs/METHODOLOGY.md](docs/METHODOLOGY.md) for the TDD workflow.

## License

[MIT](LICENSE)
