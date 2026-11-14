# Why napi-mojo is no longer maintained: the November 2026 comparison

In November 2026 napi-mojo was tested against the tools a Node.js developer
already has, on three claims. Each claim had its pass line written down before
the first run. Five of the six verdicts were fails, and the one pass has no
user who needs it through Node. Development stopped at 0.18.0.

This page records what was measured, so that nobody has to repeat the work to
learn the answer.

## The question

Is there something napi-mojo lets a Node or TypeScript developer do that the
tools they already have do not, measured on those tools' home ground?

## Verdicts

| Claim | Platform | Verdict | napi-mojo against the best correct incumbent |
| --- | --- | --- | --- |
| Sentence embeddings from Node beat onnxruntime-node | Apple M4, GPU | **pass** | 4.13x single-text latency, 7.18x batch throughput, 1.86x cold start, against onnxruntime's CoreML provider |
| Same | Apple M4, CPU | fail | 0.37x single-text latency |
| Same | Linux x64, CPU | fail | 0.66x latency, 0.91x throughput, 0.89x cold start |
| A parallel scoring kernel in Mojo beats Rust with rayon | Apple M4 | fail | 0.77x of Rust's speed |
| Same | Linux x64 | fail | 0.98x |
| One Mojo source on GPU and CPU holds against WebGPU | Apple M4, GPU | fail | 0.87x at batch 1, 0.20x at batch 64 |

Ratios are written so that above 1 means napi-mojo is better.

## Limits of this evidence

- **The benchmark harnesses are not in this repository.** They were written as
  throwaway probes. The numbers below carry their date, machine and versions,
  but you cannot rerun them from a clone.
- **Two machines.** A Mac mini (Apple M4, 10 cores, 16 GB, macOS 27.0.1,
  Node v26.9.0) on 2026-11-14, and a rented cloud VM (4 dedicated vCPUs, AMD
  EPYC 7713, 8 GB, Ubuntu 24.04, glibc 2.39) on 2026-11-13. Nothing here says
  anything about an M5, an NVIDIA GPU, Windows or arm64 Linux.
- **One run per verdict**, of several rounds each. On the Mac the 1-minute load
  average stayed near 1.4 with no process above 4 % of a core, and the second
  and third benchmarks ran straight after the one before. No verdict is close
  enough to its line for that to decide it.
- **Toolchain:** Mojo 1.2.0, MAX 26.7.0, napi-mojo 0.18.0.

## Claim 1: sentence embeddings from Node

`all-MiniLM-L6-v2`, encoded by MAX's kernel library called from Mojo with a
tokenizer written in Mojo, loaded as an addon with no Python. Incumbents:
onnxruntime-node 1.31.1 (with `tokenizers` 0.23.2) and
`@huggingface/transformers` 4.3.2. An arm counts only if its vectors match
reference vectors to a minimum cosine of 0.995.

Pass line: on a device, at least 20 % better than the best correct incumbent on
latency, throughput or cold start, and no worse than 1.5x on each of those and
on install size.

| Platform | Arm | Batch-1 p50, ms | Texts/s, best shape | Cold start, ms | Event-loop p99, ms | Peak RSS, MB |
| --- | --- | --- | --- | --- | --- | --- |
| Apple M4 | napi-mojo, GPU | 2.24 | 723.2 | 186 | 1.2 | 518 |
| Apple M4 | napi-mojo, CPU | 6.36 | 287.2 | 131 | 1.2 | 491 |
| Apple M4 | onnxruntime, CPU | 2.34 | 268.3 | 151 | 660.1 | 1,526 |
| Apple M4 | onnxruntime, CoreML, fixed shapes | 9.24 | 100.7 | 346 | 704.1 | 1,765 |
| Linux x64 | napi-mojo, CPU | 12.46 | 64.5 | 521 | 2.6 | 402 |
| Linux x64 | onnxruntime, CPU, O3 model | 8.28 | 70.7 | 462 | 2,900 | 1,591 |

"Best shape" is batches of 64 for napi-mojo and a loop of single texts for
onnxruntime, which was faster that way than batched. Install size on the Mac:
95.1 MB against 189.1 MB.

**The pass, read strictly.** The pass line compares GPU with GPU. A developer
on an M4 can also run onnxruntime on the CPU, and against that the GPU arm ties
on single-text latency (2.24 ms against 2.34 ms), is slower to start (186 ms
against 141 ms for the O3 model) and leads only on batch throughput, by 2.70x.

**Arms that did not count.** onnxruntime-node's WebGPU provider returned wrong
vectors at batch 64, and all three transformers.js configurations scored a
minimum cosine of 0.92 or lower, which we traced to truncated inputs losing
their final `[SEP]` token. Neither has a standalone reproducer yet, so treat
both as observations from one harness. onnxruntime's CoreML provider with
dynamic shapes grew past 14 GB and was run with fixed shapes only.

**Not gated, but measured.** napi-mojo ran the model off the JavaScript thread.
onnxruntime-node 1.31.1 runs `InferenceSession.run` on it, and its p99
event-loop delay was 0.6 to 2.9 seconds. A worker thread is the usual
answer to that.

## Claim 2: a parallel CPU kernel against Rust

Score one million rows of 384 floats against a query and keep the top ten, as
one fused parallel pass. Mojo used MAX's thread pool; Rust used napi-rs 3.16.2
with rayon 1.12.0. Pass line: Mojo at least 1.25x faster at one million rows.

| Platform | Rows | Mojo, ms | Rust, ms | Mojo against Rust | Threads, Mojo / Rust |
| --- | --- | --- | --- | --- | --- |
| Apple M4 | 1,000,000 | 8.169 | 6.262 | 0.767x | 4 / 10 |
| Apple M4 | 100,000 | 0.910 | 0.680 | 0.748x | 4 / 10 |
| Linux x64 | 1,000,000 | 24.045 | 23.565 | 0.980x | 4 / 4 |

For scale, on the Mac at one million rows: piscina 5.3.2 took 19.1 ms,
`@duckdb/node-api` 2.0.0-r.1 took 51.0 ms and single-threaded JavaScript
94.6 ms.

- The workload is memory-bound, and both compilers reach the same ceiling.
- On the Mac, Mojo's thread pool used the four performance cores and Rust used
  all ten. Rust held to four threads took 9.964 ms, so thread for thread Mojo
  was 1.22x faster there. The cause was not established.
- The Mojo arm was not shorter: 267 lines of kernel and binding against Rust's
  245, because napi-mojo's code generator has no typed-array argument and the
  binding was written by hand.
- Mojo built from clean in 2.7 s, Rust in 11.0 s.

## Claim 3: one source on GPU and CPU

Exact top-10 search over one million rows of 384 floats resident on the device.
The Mojo arm is [`@qkstat/retrieve`](https://github.com/codetalcott/mojo-addon-examples)
with a 37-line patch, which uses MAX's `linalg.matmul` on the device. The
incumbent is a hand-written WGSL kernel on the `webgpu` package (Dawn) 0.6.2.
Pass line: 1.25x of Dawn at batch 1 or 64, or 0.8x at both together with a
working CPU path from the same source.

| Arm | Batch-1 p50, ms | Queries/s at batch 64 | Cold start, ms |
| --- | --- | --- | --- |
| Mojo, GPU | 19.95 | 177 | 814 |
| Mojo, CPU, same binary | 84.67 | 731 | 856 |
| Dawn, top-k on the device | 17.28 | 874 | 280 |
| Dawn, scores read back | 19.80 | 311 | 280 |

- One Mojo source and one binary did serve both the GPU and the CPU. That works
  because MAX ships both matmul backends.
- The Mojo arm is untuned: its top-k is a single-threaded heap on the host,
  which is why its own CPU path beats its GPU path at batch 64. Moving the
  top-k to the device was not attempted; one profile put the best case at 0.66x
  to 0.80x of Dawn.
- 65 lines of WGSL were enough for the incumbent's kernel, so a Node developer
  already has a portable GPU language.

## What this means for a reader choosing a tool

- **Writing a native addon for Node:** use [napi-rs](https://napi.rs). It is
  maintained, runs on Windows, and its parallel kernel was as fast or faster.
- **Embeddings from Node:** use
  [onnxruntime-node](https://onnxruntime.ai/docs/get-started/with-javascript/node.html)
  on the CPU, in a worker thread if the event loop matters.
- **GPU compute from Node:** WebGPU through the
  [`webgpu`](https://www.npmjs.com/package/webgpu) package.
- **Where napi-mojo did measure ahead:** per-call binding overhead (see the
  README's Performance section), build time, event-loop latency and memory in
  the embedding test, and batch embedding throughput on an Apple-silicon GPU.
  None of these found a user who needed it through Node.

## What may still be useful here

- [`MOJO-RULES.md`](MOJO-RULES.md) and
  [`toolchain-migrations.md`](toolchain-migrations.md): C interop in Mojo as of
  1.2.0, including pointer origins, keep-alives across FFI calls and a
  process-lifetime cache without global variables.
- [`plan-lazily-checked-artifacts.md`](plan-lazily-checked-artifacts.md): how
  Mojo's per-method elaboration lets broken code ship, and the gates that catch
  it.
