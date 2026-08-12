# Toolchain management: pixi vs uv

**Status:** investigated 2026-08-12, **decision — keep pixi for now.** Revisit when a
trigger below fires.

Modular now ships Mojo and MAX to PyPI as well as conda, so `uv` is a genuine
alternative to `pixi` for this repo. This records what was verified, what it
would cost, and what would change the decision — so the next person does not
re-derive it.

## Correcting the premise

Modular's install docs present **uv and pixi as equal-priority options**, uv
listed first, **neither marked recommended or preferred**. pixi is still
documented as a first-class path with `-c https://conda.modular.com/max/`. So
uv is newly available, not a replacement, and pixi is not deprecated.

## What was verified (not inferred)

uv produces a **fully working, byte-identical toolchain**:

| Check | Result |
| --- | --- |
| `uv pip install mojo max` (Python 3.13) | `Mojo 1.0.0 (ed45d567)` — **identical build hash to conda** |
| Build the real addon with the uv toolchain | succeeds |
| Full Jest suite against the uv-built binary | **641 pass** |
| GC finalizer suite against the uv-built binary | **7 pass** |
| `asyncRuntimeInitOk()` (exercises `initialize_runtime()` + `max.algorithm`) | `true` |
| Mojo package library (`.mojoc`) | all **29** present, same as conda |
| Nightlies (the Canary's requirement) | works — `1.1.0.dev2026081105` |

Nightly install under uv:

```bash
uv pip install mojo --index https://whl.modular.com/nightly/simple/ --prerelease allow
```

> The nightly index **moved**: `dl.modular.com/public/nightly/python/simple/` now
> 404s. The current URL is `https://whl.modular.com/nightly/simple/` (which 301s
> to a Google Artifact Registry host — follow redirects).

### Packaging trap: the `.mojoc` libraries live in separate wheels

Inspecting the `mojo` and `max` wheels alone is **misleading** and led to a wrong
conclusion mid-investigation:

- `mojo` wheel — LSP/debugger tooling only. **No compiler binary, no dylibs.**
- `max` wheel — Python MAX framework only. No compiler, no dylibs, no `.mojoc`.
  (`max/support/algorithm.py` is Python, *not* the Mojo `max.algorithm` we import.)
- `mojo-compiler` — `modular/bin/mojo` + 3 of our 4 bundled dylibs.
- `max-core` — the 4th (`libAsyncRTMojoBindings.dylib`).
- **`mojo-compiler-mojo-libs` / `max-mojo-libs`** — the 29 `.mojoc` files. These
  are what make `from max.algorithm import parallelize` resolve, and they are
  easy to miss because they are pulled in transitively.

`uv pip install mojo max` resolves all of them. Note `max[all]` (as in some docs)
additionally drags in the whole serve/benchmark ML stack — transformers,
datasets, openai — which this project has no use for.

## What migrating would cost

1. **`scripts/bundle-runtime.sh` breaks. This is the blocker.** It derives the
   library directory as `$(dirname "$(which mojo)")/../lib`. Under uv that
   resolves to `.venv/lib`, which contains **zero** Mojo dylibs; the real path is
   `.venv/lib/python3.13/site-packages/modular/lib/`. Also `.venv/bin/mojo` is a
   **shell shim**, not the binary, so naive symlink-following does not fix it.

   This matters more than its size suggests: per CLAUDE.md, the packaging
   pipeline is the single most historically fragile part of this repo — five
   pipeline layers each silently dropped runtime libraries, and the Linux package
   was broken through 0.5.1. Any change here must be validated by loading the
   **packed tarball** in a cleared environment on **both** platforms.

2. **Python version cap.** PyPI `max` ships cp310–cp313 wheels; there is no
   cp314 for 26.5.0. conda currently gives us Python 3.14. Functionally
   irrelevant (this project contains no Python), but it is a real constraint.

3. **glibc floor.** PyPI Linux wheels are `manylinux_2_34` → glibc 2.34+.
   This affects who can **build** the framework, not who can **use** it —
   consumers get prebuilt binaries. `ubuntu-latest` is comfortably above it.

4. **CI rework.** `setup-pixi` → `setup-uv`, and the Nightly Canary's
   channel-swap becomes an index-URL swap. Equivalent work, not free.

5. **Lockfile rewrite.** `pixi.lock` (multi-platform, format v7) → `pyproject.toml`
   + `uv.lock`. uv's resolution is universal too, so parity is achievable, but it
   is a rewrite of a currently-correct artifact.

6. **Disk is not an argument for uv here** — measured: uv venv **872M** vs pixi
   env **687M**.

## What argues for uv

- **pixi currently manages exactly one package: `max`.** There is no conda-only
  dependency anchoring this repo to pixi. Node comes from the system /
  `actions/setup-node`, not pixi. This directly answers the "other project
  dependencies" question: there are none.
- **Audience fit.** This is a Node.js addon framework. Its contributors are JS
  developers, for whom conda is unfamiliar and uv increasingly is not.
- **It removes a documented friction point.** README already has to warn that
  **pixi 0.73+ is required** because `pixi.lock` is format v7 — a fresh clone on
  pixi 0.66 fails with a lockfile-version error that points nowhere near this
  project.

## Decision

**Keep pixi.** It works, it is fully validated against Mojo 1.0.0, and the
benefit of switching (contributor familiarity) does not currently justify
reworking the most fragile part of the build. uv is a viable fallback, now
proven, rather than an upgrade.

**Do this regardless:** make `bundle-runtime.sh`'s toolchain-root discovery
layout-agnostic — resolve the *real* `mojo` binary (following shims) and locate
`modular/lib` relative to that, rather than assuming `../lib`. It is better code
under pixi alone, and it removes the single blocker to a future uv migration.

**Revisit if any of these fire:**

- A contributor actually hits the pixi-version friction.
- Modular starts favoring uv in its docs (today they are equal).
- We need a conda-free CI, or a Python-side integration that wants one env.
- conda packaging lags PyPI on a release we need.
