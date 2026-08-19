# Plan: an API reference for the framework

**Status:** scoped 2026-08-19, **not started.** The recommendation is to *not*
build the pipeline first.

## The problem

`npm run generate:docs` runs typedoc over `build/index.d.ts`. That file
describes the **demo addon** — `greet`, `asyncSum`, `Counter`. The product is
the framework: `JsString.create`, `unwrap_native[T]`, `ThreadsafeFunction`,
`MojoFloat64Array`. So the one command named "docs" documents the thing nobody
installs napi-mojo to use, under a title that says `napi-mojo`.

The design review filed this as "no API reference for the actual product". It
is real, but the obvious framing — "pick a doc generator that reads Mojo" — is
the wrong first move.

## The finding that reorders the work

A scan of every public `def` in `src/napi/` (397 of them):

| doc style | count | share |
|---|---|---|
| preceded by a `##` comment block | 47 | 11% |
| with a `"""` docstring | 3 | <1% |
| **neither** | **347** | **87%** |

Worst concentrations: `raw.mojo` (130 of 147 undocumented), `args.mojo` (22 of
23), `js_typedarray.mojo` (20 of 20), `error.mojo` (18 of 18), `js_object.mojo`
(17 of 18).

**Any pipeline run today would emit a reference that is 87% bare signatures.**
That is worse than no reference: it looks complete, ranks in search, and tells
a reader nothing. The bottleneck is content, not tooling.

Note also that the 11% which *are* documented use `##` comments above the
`def`, which is a napi-mojo convention, not a Mojo language feature — no
extractor will find them without custom parsing, and they do not appear in
editor hovers either.

## Options for the renderer (secondary)

1. **`mojo doc`, if the pinned toolchain has it.** Mojo's own doc extractor
   reads `"""` docstrings and emits JSON, which a small script can render.
   Language-native, survives syntax changes, and the docstrings double as
   editor hover text. **Unverified from this repo's sandbox** — docs.modular.com
   is egress-blocked here and there is no local toolchain. First step of any
   work on this item:

   ```bash
   pixi run mojo doc --help          # does the 1.0.0 pin ship it?
   pixi run mojo doc src/napi/framework/js_object.mojo -o /tmp/doc.json
   ```

2. **A custom extractor.** `scripts/generate-dts.js` already parses Mojo source
   with regexes (registration passes, body extraction), so the machinery is not
   new ground. But it re-implements a parser the compiler already has, and this
   repo has been burned by regex-over-Mojo drifting across toolchain bumps.
   Fallback only if option 1 does not exist.

3. **Hand-written reference pages.** Rejected: 397 entries cannot be kept
   truthful by hand, and this repo's whole discipline is generated-or-gated.

## Recommendation

Phased, content first.

1. **Adopt `"""` docstrings as the convention** for the public framework
   surface, replacing the `##`-above-def style, and record it in
   `CONTRIBUTING.md`. Convert the 47 existing `##` blocks as they are touched —
   not in one sweep.
2. **Add a docstring-coverage gate that ratchets.** The pattern already exists:
   `scripts/check-compile-coverage.mjs` fails CI when a public framework method
   is missing from the coverage target. The analogue counts documented public
   defs against a floor committed in the repo, and the floor only goes up. That
   turns 87% undocumented from a number nobody owns into a number that cannot
   regress.
3. **Document the surface a consumer actually touches first** — the `Js*`
   wrappers, `CbArgs`, `register.mojo`, `convert.mojo`, `async_work.mojo`. That
   is roughly 150 of the 397. `raw.mojo`'s 147 thin FFI wrappers are an
   implementation detail and should be excluded from the reference entirely.
4. **Only then wire the renderer**, once there is something worth rendering.

## Sizing

- Step 1: an hour, mostly deciding and writing it down.
- Step 2: half a day (the gate is a sibling of a script that already exists).
- Step 3: the real cost — ~150 docstrings, days of work, and the only part that
  cannot be automated.
- Step 4: half a day if `mojo doc` exists; two days for a custom extractor.

## What to do about `generate:docs` meanwhile

Left in place but renamed to say what it is (the demo addon's API), so it stops
reading as the framework reference it is not. Removing it would lose a working
artifact; leaving it mislabelled was the actual defect.

## Revisit when

Someone outside this repo asks where the API docs are, or the docstring floor
from step 2 passes ~60% on the consumer-facing modules — whichever comes first.
