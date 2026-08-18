# Contributor's Guide

Standards and rules for all contributions to `napi-mojo`, including LLM agents acting as pair programmers.

## Core Directives

1. **Safety is Paramount**: Build a safe boundary over N-API. Every FFI call that can fail **must** be checked via `check_status()`.
2. **Follow the Methodology**: All development follows the TDD pattern in [METHODOLOGY.md](METHODOLOGY.md).
3. **Reference the Source**: The [official Node.js N-API documentation](https://nodejs.org/api/n-api.html) is the single source of truth for N-API behavior.
4. **Explain Everything**: Code without explanation is incomplete. Justify implementation choices.

## Technical Standards

### Mojo Code

- **Naming**: `UpperCamelCase` for types (structs, traits), `snake_case` for functions and variables.
- **Error Handling**: All fallible public functions must use `raises`. N-API errors must convert to `NapiError`.
- **Documentation**: All public items must have docstring comments. Unsafe FFI blocks must explain why they are safe.
- **String Lifetimes**: Keep `String` values in named `var` bindings when passing to N-API. Mojo's ASAP (eager) destruction will free inline temporaries before N-API reads them.

### N-API Interaction

- **Status Checks**: Every N-API call returning `napi_status` **must** be immediately passed to `check_status()`.
- **FFI Isolation**: Only `src/napi/raw.mojo` may use `OwnedDLHandle` directly. All other code calls through the `raw_*` wrapper functions.
- **Cached Bindings**: Everything runs on cached function pointers (`b: Bindings` first parameter). The only env-only surface is the `raw_get_cb_info` bootstrap (`CbArgs`) and the `throw_js_*` except-block fallbacks — do not add new env-only overloads. See "Cached NapiBindings" in CLAUDE.md.
- **Struct Layout**: `NapiPropertyDescriptor` must match the C struct layout exactly (8 fields, no reordering).

### Coverage Rules (the two that bite)

- **Every new or changed public framework method gets a cover call in `tests/compile/framework_coverage.mojo` — one per overload — in the same commit.** Mojo elaborates imported-package `def` bodies lazily, so an uncovered method can ship broken with the build green. `scripts/check-compile-coverage.mjs` fails CI on a missing name but cannot see a missing overload; that part is on you.
- **Every new code-generator feature gets an instantiation in `tests/codegen/kitchen-sink.toml` in the same commit.** The drift gate only proves templates that `src/exports.toml` happens to use; the kitchen sink compiles every emitter branch in CI.

### Toolchain and Imports (Mojo 1.0.0 stable)

The pin lives in `pixi.toml` and is part of the public contract (downstream packages compile against the published `src/`). Stdlib imports use the `std.` prefix:

```mojo
from std.ffi import OwnedDLHandle
from std.memory.alloc import unsafe_alloc
from std.collections import Optional
```

### Build Flag

```bash
pixi run mojo build --emit shared-lib -I src src/lib.mojo -o build/index.node  # Correct
# NOT: mojo build -shared ...                                                  # Wrong flag
```

(or just `pixi run bash build.sh`; standalone addons compile with `-I <path-to-napi-mojo>/src`).

### Module Entry Point

```mojo
@export("napi_register_module_v1")
def register_module(env: NapiEnv, exports: NapiValue) abi("C") -> NapiValue:
    ...
    return exports
```

See `examples/hello-addon.mojo` for the full pattern, including the `NapiBindings` allocation that must precede `ModuleBuilder`.

## Interaction Protocol (for LLM Agents)

- Present complete code first, then explanation.
- Justify implementation strategy with respect to project goals and standards.
- Ask for clarification before proceeding if a prompt is ambiguous.
- When in doubt about a Mojo API, test it in `spike/` before using it in `src/`.
