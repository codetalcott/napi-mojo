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
- **Struct Layout**: `NapiPropertyDescriptor` must match the C struct layout exactly (8 fields, no reordering).

### Import Paths (2026 nightly)

```mojo
from ffi import OwnedDLHandle   # Correct: top-level ffi module
# NOT: from sys.ffi import ...  # Wrong: deprecated path
```

### Build Flag

```bash
mojo build --emit shared-lib src/lib.mojo -o build/lib.dylib  # Correct
# NOT: mojo build -shared ...                                   # Wrong flag
```

### Module Entry Point

```mojo
@export("napi_register_module_v1", ABI="C")
fn register_module(env: NapiEnv, exports: NapiValue) -> NapiValue:
    ...
    return exports
```

## Interaction Protocol (for LLM Agents)

- Present complete code first, then explanation.
- Justify implementation strategy with respect to project goals and standards.
- Ask for clarification before proceeding if a prompt is ambiguous.
- When in doubt about a Mojo API, test it in `spike/` before using it in `src/`.
