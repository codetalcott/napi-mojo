# Plan: an API reference for the framework

**Status:** scoped 2026-08-19, tooling **verified in CI**, work **not started.**
The recommendation is still content first — but the tooling turned out to be
cheaper and better than the original scoping assumed.

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

- **A bare file with no `-I`** fails with `'None' has no attributes` on an
  explicit `__moveinit__`. That is the error CLAUDE.md already documents for a
  struct compiled as a *main module* rather than as part of a package —
  `mojo doc` treats a bare path that way. Always pass `-I src`.
- **A directory** (`mojo doc -I src src/napi/`) produces no output file. The
  renderer has to iterate files itself.

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
2. **Add `scripts/check-docstring-coverage.mjs` and a CI step**: run
   `mojo doc --diagnose-missing-doc-strings -I src` over the consumer-facing
   modules, count the warnings, compare against a floor committed in the repo,
   fail if it rises. Model it on `check-compile-coverage.mjs`, which already
   does exactly this shape of job.
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
| 2. Ratcheting gate | ~2 h | was half a day; `--diagnose-missing-doc-strings` did the hard part |
| 3. ~150 docstrings | days | the real cost, and the only part that cannot be automated |
| 4. Renderer | ~half a day | JSON walk; no parsing, no third-party doc tool |

## Revisit when

Someone outside this repo asks where the API docs are, or the docstring floor
from step 2 passes ~60% on the consumer-facing modules — whichever comes first.
