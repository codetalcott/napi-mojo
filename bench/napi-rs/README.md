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

| call | napi-mojo | napi-rs | ratio | delta |
|---|---|---|---|---|
| `hello()` | 411.0 | 79.7 | 5.16x | 331 |
| `greet("world")` | 463.6 | 206.8 | 2.24x | 257 |
| `add(1, 2)` | 441.9 | 112.0 | 3.95x | 330 |
| `addInts(1, 2)` | 423.3 | 105.3 | 4.02x | 318 |
| `isPositive(42)` | 432.5 | 98.7 | 4.38x | 334 |
| `getNull()` | 405.7 | 38.8 | 10.46x | 367 |
| `createObject()` | 441.8 | 116.9 | 3.78x | 325 |
| `makeGreeting()` | 632.0 | 339.8 | 1.86x | 292 |
| `getProperty(obj, "x")` | 506.7 | 234.8 | 2.16x | 272 |
| `strictEquals(1, 1)` | 445.9 | 114.4 | 3.90x | 332 |

**Median 3.95x slower.** napi-mojo is not competitive with napi-rs on per-call
overhead today.

## The ratio is the wrong column

Read the **delta**. It is flat — 257 to 367 ns, median 330 — across calls whose
absolute cost varies by 8x. That is not a scaling penalty; it is a **constant
per-call tax**, and the ratio column is just that tax divided by however little
napi-rs was doing. `getNull()` looks catastrophic at 10.46x only because
napi-rs does the same work in 38.8 ns.

The cause is identified, not guessed. Every napi-mojo callback begins with
`CbArgs.get_bindings(env, info)` to retrieve the cached `NapiBindings` pointer
from its callback data — and reading that data needs `napi_get_cb_info`, whose
pointer cannot itself come from the cache. So the **env-only** `raw_get_cb_info`
([`src/napi/raw.mojo`](../../src/napi/raw.mojo), the one without a `Bindings`
parameter) runs `OwnedDLHandle()` + `get_symbol` on **every single call**.

Measured directly, from a host-mode Mojo program:

```
OwnedDLHandle() + get_symbol   366.7 ns/op
OwnedDLHandle() alone           41.7 ns/op   <- so ~325 ns is the dlsym
```

**~325 ns of dlsym against a ~330 ns median delta.** The bootstrap accounts for
essentially the whole gap.

## Why it is not simply fixed

The obvious fix — resolve `napi_get_cb_info` once at module init and keep it in
a process-global — is blocked: **Mojo has no module-level `var`** (hard error,
recorded in `spike/global_probe.mojo` and in CLAUDE.md). Every other N-API
pointer avoids this by travelling in a *designated carrier* — callback data,
a TSFN context, a finalize hint — but the bootstrap is by definition the call
that reads the carrier, so it has nowhere to travel in.

So the cached-`NapiBindings` architecture is doing its job: 142 of 143 pointers
cost zero dlsym per call. The 143rd is structural, and it is worth ~330 ns.
If a Mojo release ever ships module-level globals, re-run `spike/global_probe.mojo`
— that single change would close most of this gap.

## What this does and does not mean

- **Chatty, fine-grained APIs**: a real cost. 330 ns per crossing, and it is
  the same 330 ns whether the call does anything or not.
- **Compute-heavy addons — the reason to reach for Mojo at all**: irrelevant. A
  fixed 330 ns disappears against any kernel worth writing in Mojo.
- Note `makeGreeting()` at 1.86x: the more the callee actually does, the more
  the fixed tax amortises. The gap is widest where the work is smallest.

This measures **binding-layer overhead only**. Neither language's compute
performance is in evidence here, and nothing in this table says anything about
Mojo versus Rust.
