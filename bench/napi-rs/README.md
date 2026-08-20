# napi-mojo vs napi-rs — per-call overhead

README.md has listed *"performance benchmarking against napi-rs"* as missing
since the project started. For a framework whose one-line pitch is "the Mojo
equivalent of napi-rs", this is the number people actually want.

## Running it

```bash
pixi run bash build.sh                 # from the repo root — builds the Mojo side
cd bench/napi-rs
npm install
npx napi build --release --platform    # builds the Rust side
node compare.mjs --rounds 5            # or --json, or --verify
```

Needs a Rust toolchain. Not wired into CI: it is a periodic measurement, not a
gate, and it would put `cargo` on every PR for a number that moves with the
machine more than with the diff.

## Method, and why it is fair

- **One process, one harness.** Both addons are loaded into the same Node
  process and timed by `measure()` from `scripts/bench-harness.mjs` — the same
  import `scripts/benchmark.mjs` uses, not a copy of it.
- **Verified-identical semantics.** `compare.mjs --verify` asserts all ten
  function pairs return the same values (`hello()` is compared by string
  length, since each returns its own framework's name). What is measured is the
  boundary, not the callee.
- **Interleaved and repeated.** A/B within each pair, repeated `--rounds`
  times, taking the per-pair minimum of medians. Running all of A then all of B
  would bake thermal drift straight into the comparison.
- **Idiomatic Rust.** The baseline is `#[napi]` macro code built with
  `napi build --release` — what a napi-rs user actually ships. Hand-rolling raw
  `napi_*` calls there would beat the framework being compared and would
  represent nobody's real code.

## Results

darwin-arm64, Node v24.18.0, best of 5 interleaved rounds, median ns/call:

| call | napi-mojo | napi-rs | ratio |
|---|---|---|---|
| `isPositive(42)` | 27.9 | 91.6 | 0.30x |
| `createObject()` | 35.1 | 101.5 | 0.35x |
| `add(1, 2)` | 35.8 | 97.5 | 0.37x |
| `strictEquals(1, 1)` | 36.4 | 93.9 | 0.39x |
| `getProperty(obj, "x")` | 74.7 | 189.4 | 0.39x |
| `greet("world")` | 78.0 | 185.7 | 0.42x |
| `addInts(1, 2)` | 43.8 | 98.9 | 0.44x |
| `getNull()` | 18.9 | 33.7 | 0.56x |
| `hello()` | 31.9 | 52.5 | 0.61x |
| `makeGreeting()` | 188.2 | 278.0 | 0.68x |

**Median 0.42x** — about 2.4x faster than napi-rs.

## How this number was 3.95x a day earlier

The first run of this benchmark said napi-mojo was **3.95x slower**, and that
result is why the framework is now faster. It is worth keeping the reasoning on
file, because the ratio column is what nearly hid it.

The **delta** was flat — 257 to 367 ns, median 330 — across calls whose absolute
cost varied by 8x. A constant tax, not a scaling penalty. Every napi-mojo
callback began by fetching its cached `NapiBindings` from callback data, and
reading callback data needs `napi_get_cb_info`, whose pointer could not come
from the cache it was fetching. So the env-only `raw_get_cb_info` ran
`OwnedDLHandle()` + `get_symbol` on **every call**. Measured in isolation from a
host-mode Mojo program:

```
OwnedDLHandle() + get_symbol   ~346 ns/op
  of which raw dlsym            ~280 ns   <- irreducible while it is called at all
  Mojo wrapper                   ~66 ns
  the String copy inside it       ~8 ns   <- the tempting fix; not the problem
```

~330 ns of measured delta against a ~346 ns bootstrap. It was the whole gap.

`src/napi/global_cache.mojo` now holds that one symbol address in a
module-private data-segment slot (`pop.global_alloc` + `@no_inline`), so the
dlsym happens once per module image instead of once per call. Read that file's
header for why it caches only the address and never the `NapiBindings` struct,
and why the failure mode is a silent slowdown rather than a crash —
`globalCacheActive()` and `tests/global_cache.test.js` exist to catch it.

## What this does and does not mean

- **Binding-layer overhead only.** Nothing here says anything about Mojo versus
  Rust as languages, or about compute throughput.
- **The gap narrows as the callee does more work** — `makeGreeting()` at 0.68x
  versus `isPositive()` at 0.30x — because what was removed is fixed overhead.
- napi-rs remains far more mature. This is one axis, measured honestly, on
  microbenchmarks that deliberately do as little as possible.
