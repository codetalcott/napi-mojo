# napi-mojo: Node.js Addons in Mojo

**Project Goal:** A safe, ergonomic, and high-performance library for building Node.js native addons in the Mojo programming language. This project is the Mojo equivalent of Rust's [`napi-rs`](https://napi.rs).

## Guiding Principles

1. **Safety First:** Safe abstraction layer over the C-based N-API. Every FFI call that can fail is checked.
2. **Ergonomics:** A user-friendly API that feels natural to Mojo developers.
3. **Performance:** Leverage Mojo's zero-overhead abstractions for high-speed native modules.

## Project Structure

```
napi-mojo/
├── spike/          # FFI validation experiments (prove core mechanism works)
├── src/            # Mojo source code
│   └── napi/       # N-API bindings and framework layer
├── tests/          # JavaScript Jest tests
├── examples/       # Standalone usage examples
└── build/          # Compiled output (index.node) — gitignored
```

## Development

```bash
npm install          # Install Jest
npm run build        # Compile Mojo → build/index.node
npm test             # Run Jest test suite
```

## Requirements

- [Mojo nightly](https://docs.modular.com/magic/) (tested on v26.2.x)
- Node.js 18+

## Development Methodology

See [METHODOLOGY.md](METHODOLOGY.md) for the JavaScript-driven outside-in TDD workflow.
See [CONTRIBUTING.md](CONTRIBUTING.md) for coding standards.
