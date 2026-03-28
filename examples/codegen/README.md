# Code Generator Example

A self-contained addon built entirely with the TOML code generator — no
hand-written N-API callbacks. This is the recommended way to build napi-mojo
addons for typical use cases.

## What this demonstrates

- **`mojo_fn` auto-trampolines** — write pure Mojo functions, declare them in
  TOML, and the generator creates type-checked N-API callbacks
- **Nullable returns** — `returns = "number?"` maps `Optional[T]` to `T | null`
- **Struct-to-object mapping** — `[structs.*]` defines a typed JS object shape
  with auto-generated bidirectional converters

## Files

| File | Purpose |
|------|---------|
| `exports.toml` | Function and struct declarations |
| `fns.mojo` | Pure Mojo functions (no N-API imports) |
| `lib.mojo` | Entry point — imports generated callbacks |
| `codegen.js` | JavaScript consumer |
| `build.sh` | Generate + compile |

## Build and run

```bash
cd examples/codegen
bash build.sh
node codegen.js
```

## How it works

1. You write pure Mojo functions in `fns.mojo` — no N-API types, no callbacks
2. You declare them in `exports.toml` with typed args and returns
3. `build.sh` runs the code generator, which produces:
   - `generated/callbacks.mojo` — type-checked N-API callbacks
   - `generated/structs.mojo` — Mojo struct definitions + JS object converters
4. `lib.mojo` imports the generated code and registers everything
5. The generator also produces TypeScript definitions automatically
