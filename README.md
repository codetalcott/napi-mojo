# napi-mojo

[![CI](https://github.com/codetalcott/mojo-node-api/actions/workflows/test.yml/badge.svg)](https://github.com/codetalcott/mojo-node-api/actions/workflows/test.yml)

Build Node.js native addons in [Mojo](https://www.modular.com/mojo) — the Mojo equivalent of Rust's [napi-rs](https://napi.rs).

```js
const addon = require('napi-mojo');

addon.hello();           // "Hello from Mojo!"
addon.add(2, 3);         // 5
addon.greet('world');     // "Hello, world!"
```

## Features

- **74 exported functions** and **3 classes** covering the full N-API surface
- Primitives: strings, numbers (Float64/Int32/UInt32/Int64), booleans, null, undefined, BigInt, Symbol, Date
- Objects: create, read/write properties, enumerate keys, freeze/seal, prototype access
- Arrays: create, map, element access, has/delete
- Functions: call, create from Mojo, closures with captured data
- Binary data: ArrayBuffer, Buffer, TypedArray, DataView, external (Mojo-owned) memory
- Classes: constructors, instance methods, getters/setters, static methods, inheritance
- Async: Promises, worker thread execution, ThreadsafeFunction (call JS from worker threads)
- Error handling: Error/TypeError/RangeError, throw/catch any value, exception propagation
- References, handle scopes, escapable handle scopes, GC finalizers
- Type coercion, strict equality, instanceof, external data with GC cleanup
- Auto-generated TypeScript definitions
- **Ergonomic API**: `ModuleBuilder`/`ClassBuilder` for registration, `fn_ptr()` helper, `unwrap_native[T]()` for class methods, `ToJsValue`/`FromJsValue` conversion traits, and a code generator (`npm run generate:addon` + `src/exports.toml`) for auto-generating callback trampolines

## Installation

> **Note:** napi-mojo currently requires building from source. Prebuilt binaries are planned.

### Prerequisites

- [Mojo nightly](https://docs.modular.com/magic/) (v26.2.x) via [pixi](https://pixi.sh)
- Node.js 18+

### Build from source

```bash
git clone https://github.com/codetalcott/mojo-node-api.git
cd mojo-node-api
npm install
npm run build    # compiles Mojo → build/index.node + generates TypeScript defs
npm test         # 349 tests
```

See [`examples/`](examples/) for runnable scripts.

## Usage Examples

### Primitives and type coercion

```js
const m = require('napi-mojo');

m.add(2.5, 3.7);            // 6.2
m.addInts(10, 20);           // 30  (Int32)
m.addBigInts(1n, 2n);        // 3n
m.isPositive(42);             // true
m.coerceToString(123);        // "123"
m.strictEquals(1, 1);         // true
```

### Objects and properties

```js
const obj = m.makeGreeting();       // { message: "Hello!" }
m.getProperty(obj, 'message');      // "Hello!"
m.getKeys({ a: 1, b: 2 });         // ["a", "b"]
m.freezeObject({ x: 1 });          // frozen object
m.hasOwn({ a: 1 }, 'a');           // true

const sym = m.createSymbol('key');
m.setPropertyByKey(obj, sym, 42);   // set symbol-keyed property
```

### Async and promises

```js
const result = await m.asyncDouble(21);  // 42  (computed on worker thread)

// Call JS from a worker thread via ThreadsafeFunction
const values = [];
await m.asyncProgress(3, (i) => values.push(i));
// values: [0, 1, 2]
```

### Classes

```js
const counter = new m.Counter(10);
counter.value;        // 10
counter.increment();
counter.value;        // 11
m.Counter.isCounter(counter);  // true

const dog = new m.Dog('Rex', 'Labrador');
dog.name;             // "Rex"  (inherited from Animal)
dog.breed;            // "Labrador"
dog.speak();          // "Rex says woof!"
```

### Binary data

```js
const ab = m.createArrayBuffer(8);       // 8-byte ArrayBuffer
const buf = m.createBuffer(4);           // Node.js Buffer
const f64 = new Float64Array(ab);
m.doubleFloat64Array(f64);               // doubles each element in-place

const dv = m.createDataView(ab, 0, 8);   // DataView over ArrayBuffer
m.getDataViewInfo(dv);                    // { byteLength: 8, byteOffset: 0 }
```

## API Reference

See [CLAUDE.md](CLAUDE.md) for the complete function table (74 exports + 3 classes) and architecture documentation.

TypeScript definitions are auto-generated at `build/index.d.ts`.

## Architecture

1. `mojo build --emit shared-lib` produces a `.dylib`/`.so` renamed to `.node`
2. Node.js calls `dlopen` on the `.node` file, then `dlsym("napi_register_module_v1")`
3. Our exported Mojo function registers all callbacks via `napi_define_properties`
4. Each callback acts as a `napi_callback`: receives `(env, cbinfo)`, returns `napi_value`
5. N-API symbols are resolved at runtime from the host process via `dlopen(NULL)`

## Development

```bash
npm run build        # compile + generate TypeScript defs
npm test             # run Jest test suite (349 tests)
npx jest tests/basic.test.js   # run a single test file
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for coding standards and [docs/METHODOLOGY.md](docs/METHODOLOGY.md) for the TDD workflow.

## License

[MIT](LICENSE)
