# spike/gpu-fatbin — Findings

**Status:** Question 1 answered locally (macOS, Mojo 0.26.3.0.dev2026041405). Questions 2–3 require a Linux + CUDA host (RunPod) to finish.

## Question 1 — Multi-arch fatbin from one Mojo build?

**Verdict: partial NO on explicit fatbin flag, but two plausible single-binary paths exist via PTX forward-compat and the generic `cuda` target.**

### Path A — Explicit multi-arch flag: NOT SUPPORTED

### Evidence

Mojo version: `Mojo 0.26.3.0.dev2026041405 (3bdc0579)`

`mojo build --help` lists `--target-accelerator <ACCELERATOR>` (singular). `--print-supported-accelerators` lists individual arches (sm_80, sm_90, sm_90a, …) but no fatbin/multi-arch syntax.

Three syntax attempts, all rejected:

| Attempt | Flag form | Result |
|---|---|---|
| A | `--target-accelerator sm_80,sm_90` | Parsed as one literal arch name. Error: `constraint failed: GPU architecture 'sm_80,sm_90' is not supported.` |
| B | `--target-accelerator sm_80 --target-accelerator sm_90` (repeated) | `error: too many specified target accelerators, expected exactly one` |
| C | `--target-accelerator "nvidia:sm_80,sm_90"` | Parsed as one literal arch. Error: `constraint failed: GPU architecture 'nvidia:sm_80,sm_90' is not supported.` |

### Path B — PTX forward-compatibility via driver JIT: PROMISING

`mojo build --emit asm --target-accelerator sm_80 ...` emits per-kernel `.ptx` sidecars. Inspection of `/tmp/test_matmul_kernel_naive.ptx` shows standard NVIDIA PTX with `.version 8.1` / `.target sm_80`. PTX is **forward-compatible** — the NVIDIA driver JIT-compiles PTX to SASS for any GPU with compute capability ≥ the PTX target at module load.

Implication: **a single `sm_80`-targeted Linux build should run unmodified on sm_80 (A100), sm_86 (A10), sm_89 (L4/RTX 4090), sm_90 (H100), and sm_100+ (Blackwell)** via driver JIT, at the cost of:

- First-load JIT latency (seconds, cacheable via CUDA's `~/.nv/ComputeCache`).
- Forgone arch-specific instructions (wgmma on sm_90, TMA on sm_90+, Blackwell tensor cores) — sm_80 baseline PTX gets ~70–90% of peak on newer hardware for most kernels; dramatically less for tensor-core-heavy code.

**Verified 2026-04-15 (local macOS cross-build):** `mojo build --emit shared-lib --target-accelerator sm_80 src/gpu/lib.mojo` on darwin-arm64 produced a 225 KB `.dylib`. `strings` on the output shows:

- 3 embedded PTX modules, each headed with `.version 8.1 / .target sm_80 / .address_size 64` — **PTX text, not cubin**.
- Visible kernel entries: `matmul_kernel_naive_float32_...`, `gevm_kernel_float32_...`, `gemv_kernel_float32_...`.
- Zero occurrences of `nv_fatbin`, `cubin`, `ELFCUDA`, `__nv_module`, or any arch-locked markers.

PTX-text embedding means the Mojo runtime calls `cuModuleLoadData` on the string at load; the NVIDIA driver JIT-compiles to SASS for the present GPU. This is the standard PTX forward-compat path — an `sm_80`-built binary runs on sm_80/86/89/90/100/120 without rebuild.

**Path B is viable.** Remaining validation is end-to-end: copy the sm_80 Linux build to a box with a real NVIDIA GPU (ideally ≠ sm_80, e.g. an A10 or L4 at sm_86/sm_89) and run the Jest GPU test. If it passes, one Linux prebuilt ships.

### Path C — Generic `cuda` target: INCONCLUSIVE

`mojo build --target-accelerator cuda` is accepted by the CLI (no "architecture not supported" error — unlike `sm_80,sm_90`). `--print-supported-accelerators` lists `cuda — Generic CUDA` alongside the specific sm_XX entries. On macOS the compile ran for 5+ minutes before hitting the test timeout (SIGKILL at 300s, still consuming ~3 GB RAM). This suggests it emits code for many/all arches and is viable but slow to build.

**Needs Linux retest with longer timeout + more RAM.** If `cuda` produces a working single binary that dispatches across all NVIDIA arches, the prebuilt count collapses to **one per OS** — the best-case outcome.

### Revised packaging plan

In priority order:

1. **Linux retest Path B first** (sm_80 baseline + driver JIT). If a single sm_80 Linux build works on an H100, ship one Linux prebuilt + one Darwin arm64 Metal prebuilt + CPU fallback. This is the simplest outcome.
2. If Path B hits cubin-embed issues, **try Path C** (`--target-accelerator cuda`) with a 30-min timeout on the RunPod box. Same outcome if it succeeds.
3. If both fail, **fall back to per-arch prebuilts**: `sm_80`, `sm_90`, optionally `sm_89`. The RAG workload is matmul-dominated, so arch-specific builds matter for H100 perf — but correctness-first via Path B is still the v1 shipping plan.

The spike's extraction verdict is no longer gated on "must ship N prebuilts"; it's gated on **which of A/B/C works on real Linux hardware**.

## Question 2 — `ldd build/gpu.node` classification — TODO (Linux required)

Not runnable on macOS. On macOS, `otool -L build/gpu.node` (built with `--target-accelerator metal:4`) should be captured too for reference, but the shipping question is Linux-only since macOS doesn't need CUDA/MAX runtime bundling (Metal is in-OS).

**Plan (RunPod A100, pixi env installed):**

1. `pixi run bash build.sh` with `NAPI_MOJO_GPU_ACCEL="--target-accelerator sm_80"` → `build/gpu.node`.
2. `ldd build/gpu.node` — capture full output.
3. Classify each `.so` as:
   - **(a) system** — libc, libstdc++, libdl, libpthread, libm → always present, do not bundle.
   - **(b) CUDA runtime** — libcudart, libcublas, libcusparse, etc. → check if bundleable via rpath vs peer-dep CUDA install.
   - **(c) MAX runtime** — libKGEN*.so, libMAXEngine*.so from `.pixi/envs/default/lib/` → bundleable? check Modular license.
   - **(d) other** — anything unexpected.

## Question 3 — rpath bundling probe — TODO (Linux required)

**Plan:**

1. Copy all non-system deps from `ldd` output into `build/gpu-libs/`.
2. `patchelf --set-rpath '$ORIGIN/gpu-libs' build/gpu.node`.
3. Move the `.node` + `gpu-libs/` to a clean directory outside the repo; unset `LD_LIBRARY_PATH`; uninstall pixi env from `PATH`.
4. `node -e "require('./gpu.node')"` + run existing GPU Jest test against it.
5. Pass = self-contained deploy possible (2 GB MAX SDK on dev machine only). Fail = peer-dep required; end users need pixi or a Modular-blessed runtime tarball.

## One-line verdict (preliminary, pending Linux steps)

**Single-binary shipping is plausible via PTX driver-JIT (Path B) or the `cuda` generic target (Path C); neither has been verified on Linux+CUDA hardware yet, so per-arch prebuilts remain the fallback plan.**

## Next session

- Provision RunPod A100 (~$1.50/hr, 1 hour budget).
- Install pixi, clone repo at `spike/gpu-fatbin`, `pixi install`.
- Execute Question 2 + 3 plans above.
- Update this file with the real ldd table and bundling result.
- Update [project_gpu_extraction.md](../../../../.claude/projects/-Users-williamtalcott-projects-mojo-node-api/memory/project_gpu_extraction.md) with the final verdict so extraction can proceed.
