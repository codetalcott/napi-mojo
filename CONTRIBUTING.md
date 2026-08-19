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

### Coverage Rules (the three that bite)

- **Every new or changed public framework method gets a cover call in `tests/compile/framework_coverage.mojo` — one per overload — in the same commit.** Mojo elaborates imported-package `def` bodies lazily, so an uncovered method can ship broken with the build green. `scripts/check-compile-coverage.mjs` fails CI on a missing name but cannot see a missing overload; that part is on you.
- **Every new code-generator feature gets an instantiation in `tests/codegen/kitchen-sink.toml` in the same commit.** The drift gate only proves templates that `src/exports.toml` happens to use; the kitchen sink compiles every emitter branch in CI.
- **Every new public `def` in `src/napi/framework/`, `src/napi/error.mojo` or `src/napi/module.mojo` gets a `"""` docstring in the same commit.** `scripts/check-docstring-coverage.mjs` ratchets against a committed floor, so the undocumented count can fall but never rise. See the docstring convention below.

### Performance

`npm run check:benchmark` measures per-call overhead and compares the median against per-platform ceilings in `scripts/benchmark-ceilings.json`. CI runs it as a non-required `benchmark` job.

Be clear about what it is for. It carries 4x headroom and runs on shared runners, so it catches a *structural* regression — a per-call `OwnedDLHandle()` + dlsym back on the hot path, costing 10-100x — and will not see a 10% one. A gate tuned tighter than the noise floor gets ignored, which is worse than one that admits its limits.

The two platforms are genuinely far apart — on the same commit, `macos-latest` measures **~2.7x** the per-call cost of `ubuntu-latest`. That is why ceilings are keyed by platform and why a platform with no recorded ceilings is a hard error rather than a silent skip.

If you add or rename a benchmark, reseed the ceilings **on each platform** (they are not comparable) and commit the result:

```bash
node scripts/check-benchmark.mjs --update
```

### Docstrings

Public framework symbols use Mojo `"""` docstrings — not the `##`-above-the-def comments found in older code. Only `"""` is a language feature: it is what `mojo doc` extracts, what an editor hover shows, and what the coverage gate counts. Convert a `##` block opportunistically when you touch the method; there is no sweep planned.

```mojo
def create(b: Bindings, env: NapiEnv, value: String) raises -> Self:
    """Create a JS string from a Mojo String.

    Args:
        b: Cached N-API bindings.
        env: The N-API environment.
        value: UTF-8 content; the byte length is passed explicitly, so the
            String need not be NUL-terminated.

    Returns:
        A JsString wrapping the new napi_value.

    Raises:
        If napi_create_string_utf8 does not return napi_ok.
    """
```

The gate is a **ratchet, not a target**: it fails when the undocumented count rises, and equally when it falls without `scripts/docstring-floor.json` being updated in the same change (otherwise the coverage you just added can be silently undone). To move the floor:

```bash
node scripts/check-docstring-coverage.mjs --print    # see current counts
node scripts/check-docstring-coverage.mjs --update   # rewrite the floor, then commit it
```

`src/napi/raw.mojo` is deliberately out of scope: its 147 thin FFI wrappers are an implementation detail, and a docstring on each would only restate the N-API name.

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
