# Plan: an API reference for the framework

**Status:** steps 1, 2 and 4 **done**; step 3 (content) **in progress — 149 of
~351 symbols documented**, covering the consumer-facing core.

- Step 1 (convention) — done; recorded in `CONTRIBUTING.md`.
- Step 2 (ratcheting gate) — done; `scripts/check-docstring-coverage.mjs`.
- Step 3 (content) — the consumer core is documented: `args.mojo` (CbArgs),
  `error.mojo`, `js_object`, `js_array`, `js_function`, `js_value`, and every
  primitive wrapper. The floor moved 351 -> 202. **The rest of step 3 is what
  remains**, and the highest-value next targets are `convert.mojo` (35),
  `js_typedarray.mojo` (23), `js_class.mojo` (16) and `async_work.mojo` (10).
- Step 4 (renderer) — done; `scripts/generate-api-reference.mjs` renders
  `docs/api/`, and `npm run check:api-reference` gates it in CI.

**The renderer honours this plan's central finding rather than working around
it**: a module below 75% documented is NOT rendered. It is listed in the index
with its ratio and linked to source, so the reference cannot become the "87%
bare signatures" artifact this document warned about. Modules cross into the
reference as their docstrings land — which makes step 3's remaining work
visible in the published output instead of only in a floor file.

## The problem

`npm run generate:docs` runs typedoc over `build/index.d.ts`, which describes
the **demo addon** — `greet`, `asyncSum`, `Counter`. The product is the
framework: `JsString.create`, `unwrap_native[T]`, `ThreadsafeFunction`,
`MojoFloat64Array`. (The script now says "demo addon" in its name and output
path, so it no longer misrepresents itself; the framework reference is what is
still missing.)

## The finding that orders the work

A scan of every public `def` in `src/napi/` (397 of them):

| doc style | count | share |
|---|---|---|
| preceded by a `##` comment block | 47 | 11% |
| with a `"""` docstring | 3 | <1% |
| **neither** | **347** | **87%** |

Worst concentrations: `raw.mojo` (130 of 147 undocumented), `args.mojo` (22 of
23), `js_typedarray.mojo` (20 of 20), `error.mojo` (18 of 18), `js_object.mojo`
(17 of 18).

**Measured precisely, 2026-08-19**, once the gate existed: **351 undocumented
public symbols across the 38 consumer-facing modules** `mojo doc` can open
(`scripts/docstring-floor.json`). The heaviest are `args.mojo` (48),
`convert.mojo` (39), `js_typedarray.mojo` (23), `js_object.mojo` (21) and
`error.mojo` (18). Five modules are already at zero — `js_coerce.mojo`,
`instance_data.mojo`, `runtime.mojo` and the two `__init__` shims — so the
convention is not starting from nothing.

**A pipeline run today would emit a reference that is 87% bare signatures** —
worse than none, because it looks complete and says nothing. The bottleneck is
content, not tooling. Note also that the documented 11% use `##` comments,
which is a napi-mojo convention rather than a language feature: no extractor
finds them, and they do not appear in editor hovers.

## Tooling: settled, in CI, on the pinned toolchain

The original version of this plan listed `mojo doc` as unverified, because
this repo's dev sandbox has no Mojo and `docs.modular.com` is egress-blocked.
A temporary CI job (removed again in the same PR) settled it.

**`mojo doc` exists on the Mojo 1.0.0 pin** and emits JSON:

```bash
# WORKS. Per file, with -I so the package imports resolve.
pixi run mojo doc -I src src/napi/framework/js_object.mojo -o /tmp/js_object.json
```

```json
{ "decl": { "kind": "module", "name": "js_object",
            "structs": [ { "name": "JsObject", "description": "",
                           "fields": [ { "name": "value", "type": "NapiValue", "summary": "" } ],
                           "functions": [ … ] } ] } }
```

Every declaration carries `description` and `summary` fields, so rendering is a
JSON-to-Markdown walk, not a parser.

**Two invocations that do not work**, both worth knowing before someone loses
an hour to them:

- **A directory** (`mojo doc -I src src/napi/`) produces no output file. The
  renderer has to iterate files itself.
- **`-I src` resolves the imports but does not make the target a package
  member.** The file named on the command line is still compiled as a *main
  module*, which is the context where an explicit
  `def __moveinit__(out self, deinit take: Self)` fails with `'None' has no
  attributes` — the bug CLAUDE.md documents. An earlier version of this plan
  said `-I src` fixed that; it does not. It was written from a probe on
  `js_object.mojo`, which happens to declare no explicit move constructor.
  Three framework files do (`js_string.mojo`, `js_mojo_array.mojo`,
  `register.mojo`) and `mojo doc` cannot open any of them. They are listed in
  `KNOWN_UNDOCUMENTABLE` in the coverage script, which fails if one ever starts
  working — so the skip cannot outlive the compiler bug. **The renderer (step 4)
  inherits this limitation and will need the same list.**

### `mojo doc` type-checks declarations the build never elaborates

Not in the original scoping, and the more useful finding of the two. The gate's
very first CI run failed on `types.mojo:224` — `NapiNodeVersion.release` was
missing `@__allow_legacy_any_origin_fields`, so the struct could not compile at
all. Nothing had noticed since dev2026062206 because nothing constructs
`NapiNodeVersion`, and **struct definitions elaborate lazily** exactly the way
method bodies do (CLAUDE.md says so; this is that rule firing).

So `mojo doc` reaches a third lazily-checked surface, after
`framework_coverage.mojo` (method bodies) and `tests/codegen/` (generator
templates). A doc failure in this gate should be read as a finding, not as gate
noise.

### The coverage gate is free

`mojo doc --diagnose-missing-doc-strings` emits one warning per undocumented
public symbol, with position and name:

```
src/napi/framework/js_object.mojo:98:9: warning: public symbol 'set_named_property' is missing a doc string
src/napi/framework/js_object.mojo:105:9: warning: public symbol 'set' is missing a doc string
```

So the ratcheting gate this plan called for is a **warning count against a
committed floor**, not a custom Mojo parser. That is both cheaper than the
original estimate and more durable: it is the compiler's own notion of a
missing docstring, so it cannot drift from the language the way a regex would.

## Plan

1. **Adopt `"""` docstrings** for the public framework surface, replacing the
   `##`-above-the-def style, and record the convention in `CONTRIBUTING.md`.
   Convert the 47 existing `##` blocks opportunistically, not in one sweep.
2. ~~**Add `scripts/check-docstring-coverage.mjs` and a CI step**~~ — **done.**
   Per-file counts against `scripts/docstring-floor.json`; the count may fall
   (with the floor updated in the same change) but never rise.
3. **Document the surface a consumer actually touches** — the `Js*` wrappers,
   `CbArgs`, `register.mojo`, `convert.mojo`, `async_work.mojo`, `js_class.mojo`:
   roughly 150 of the 397. **`raw.mojo`'s 147 thin FFI wrappers are an
   implementation detail and stay out of the reference and out of the gate.**
4. **Render**, once there is something worth rendering: iterate the framework
   files, `mojo doc -I src <file> -o <json>`, walk the JSON to Markdown, publish
   next to the tutorial. Wire it into `generate:docs` alongside the demo-addon
   typedoc rather than replacing it.

## Sizing

| step | size | notes |
|---|---|---|
| 1. Convention | ~1 h | mostly deciding and writing it down |
| 2. Ratcheting gate | ~~2 h~~ **done** | `--diagnose-missing-doc-strings` did the hard part |
| 3. ~150 docstrings | days | the real cost, and the only part that cannot be automated |
| 4. Renderer | ~half a day | JSON walk; no parsing, no third-party doc tool |

## Revisit when

Someone outside this repo asks where the API docs are, or the docstring floor
from step 2 passes ~60% on the consumer-facing modules — whichever comes first.
