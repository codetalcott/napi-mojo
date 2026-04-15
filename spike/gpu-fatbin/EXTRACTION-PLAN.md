# `@qkstat/rag` extraction — hand-off plan

**Context for next session (in `mojo-addon-examples` repo):** napi-mojo v0.4.0 added GPU primitives (`loadMatrixGpu`, `matmulHandle`, `searchHandle`) that should be extracted to keep napi-mojo framework-shaped. Path B spike confirmed one Linux x86_64 sm_80 prebuilt covers all NVIDIA arches via driver PTX JIT; ldd shows 7 `.so`s from pixi to bundle with rpath. See [FINDINGS.md](./FINDINGS.md) for full spike results.

## Locked decisions (do not re-litigate)

- **npm scope:** `@qkstat` (org created)
- **Package name:** `@qkstat/rag` — shortest viable; leaves `@qkstat/simd-search` etc. as future siblings
- **Monorepo layout:** `packages/rag/` for publishables; existing top-level addons move under `examples/` in a prep commit
- **Build-time deps:** napi-mojo source tree (git submodule, or pixi path dep, or copy-on-build). `packages/rag/` depends on napi-mojo's framework to compile its `.node`; only the prebuilt `.node` + bundled `.so`s ship to npm, so end users don't need napi-mojo source.
- **Runtime deps:** zero direct CUDA deps. Only the NVIDIA driver (present on any GPU host).
- **CI:** GHA `ubuntu-latest` + `macos-14` runners, CPU-only (build is AOT PTX codegen per spike). Pixi cache keyed on `pixi.lock`. GPU correctness testing is manual RunPod per release.

## Prep commit (before creating `packages/rag/`)

```bash
cd /Users/williamtalcott/projects/mojo-addon-examples
mkdir -p examples
git mv matmul examples/
git mv simd-search examples/
git mv stats examples/
git mv image examples/
git mv wyhash examples/
# Update README + any intra-repo links
```

This is one commit of `git mv` + README link-fix. Converts the mixed-convention risk (top-level addons next to `packages/rag/`) into a clean split: `examples/*` = demos, `packages/*` = publishables.

## Directory skeleton (`packages/rag/`)

```
packages/rag/
├── package.json                   # @qkstat/rag glue package
├── README.md                      # what it is, install, example usage
├── LICENSE                        # match parent repo (MIT or Apache-2.0)
├── index.js                       # loads platform-specific prebuilt via require()
├── index.d.ts                     # TypeScript API surface
├── build.sh                       # cross-platform Mojo → .node build (adapted from napi-mojo)
├── pixi.toml                      # same `max` dep as napi-mojo (NOT `mojo`)
├── pixi.lock
├── src/
│   ├── lib.mojo                   # entry point (adapted from napi-mojo/src/gpu/lib.mojo)
│   ├── linalg.mojo                # the 402-line gpu_linalg.mojo body
│   └── napi/                      # submodule OR vendored copy of napi-mojo's framework
├── tests/
│   └── rag.test.js                # migrated from napi-mojo/tests/gpu-matmul.test.js
├── scripts/
│   ├── bundle-libs.sh             # patchelf rpath + copy 7 .so into prebuild dir
│   └── release.mjs                # bumps version across glue + platform sub-packages
├── npm/                           # per-platform sub-packages (napi-rs pattern)
│   ├── darwin-arm64/
│   │   ├── package.json           # @qkstat/rag-darwin-arm64
│   │   └── README.md
│   └── linux-x64/
│       ├── package.json           # @qkstat/rag-linux-x64
│       └── README.md
└── .github/workflows/
    ├── build.yml                  # matrix: {ubuntu-latest, macos-14} → upload prebuilt artifacts
    ├── test.yml                   # CPU-side tests on PR
    └── release.yml                # triggered on version tag: publish glue + platform packages
```

## Key file sketches

### `packages/rag/package.json`

```json
{
  "name": "@qkstat/rag",
  "version": "0.1.0",
  "description": "GPU-accelerated RAG primitives (matmul, top-k search) for Node.js, powered by Mojo",
  "main": "index.js",
  "types": "index.d.ts",
  "files": ["index.js", "index.d.ts", "README.md", "LICENSE"],
  "engines": { "node": ">=22.12" },
  "repository": { "type": "git", "url": "https://github.com/codetalcott/mojo-addon-examples.git", "directory": "packages/rag" },
  "homepage": "https://qkstat.com/rag",
  "license": "MIT",
  "optionalDependencies": {
    "@qkstat/rag-darwin-arm64": "0.1.0",
    "@qkstat/rag-linux-x64": "0.1.0"
  },
  "devDependencies": {
    "jest": "^29.0.0"
  },
  "scripts": {
    "build": "bash build.sh",
    "bundle": "bash scripts/bundle-libs.sh",
    "test": "jest"
  }
}
```

### `packages/rag/index.js`

```js
// Load the prebuilt .node for the current platform. Each @qkstat/rag-<platform>
// package ships build/rag.node with bundled .so deps and rpath set to $ORIGIN.
const { platform, arch } = process;
const key = `${platform}-${arch}`;
const map = {
  "darwin-arm64": "@qkstat/rag-darwin-arm64",
  "linux-x64": "@qkstat/rag-linux-x64",
};
const pkg = map[key];
if (!pkg) {
  throw new Error(
    `@qkstat/rag: no prebuilt for ${key}. Supported: ${Object.keys(map).join(", ")}. ` +
    `Source build requires Mojo + pixi — see README for instructions.`
  );
}
module.exports = require(pkg);
```

### `packages/rag/npm/linux-x64/package.json`

```json
{
  "name": "@qkstat/rag-linux-x64",
  "version": "0.1.0",
  "description": "Prebuilt @qkstat/rag binary for Linux x86_64 (NVIDIA GPU, any CC >= 8.0)",
  "main": "build/rag.node",
  "files": ["build/rag.node", "build/gpu-libs/", "README.md"],
  "os": ["linux"],
  "cpu": ["x64"],
  "engines": { "node": ">=22.12" },
  "license": "MIT"
}
```

(Same shape for `darwin-arm64`, minus `gpu-libs/` since Metal runtime is in-OS.)

### `packages/rag/scripts/bundle-libs.sh`

```bash
#!/usr/bin/env bash
# Post-build: copy the 7 .so deps from pixi env into build/gpu-libs/ and
# patch rpath on the .node to $ORIGIN/gpu-libs. Runs on Linux only;
# darwin builds skip this (Metal runtime is part of the OS).
set -euo pipefail

[ "$(uname -s)" = "Linux" ] || { echo "skipping — not Linux"; exit 0; }
which patchelf >/dev/null || { echo "install patchelf"; exit 1; }

LIBS_DIR=build/gpu-libs
mkdir -p "$LIBS_DIR"

for lib in \
  libKGENCompilerRTShared.so \
  libAsyncRTMojoBindings.so \
  libAsyncRTRuntimeGlobals.so \
  libMSupportGlobals.so \
  libNVPTX.so \
  libstdc++.so.6 \
  libgcc_s.so.1
do
  src="$(pwd)/.pixi/envs/default/lib/$lib"
  [ -f "$src" ] || { echo "missing $src"; exit 1; }
  cp -L "$src" "$LIBS_DIR/"
done

patchelf --set-rpath '$ORIGIN/gpu-libs' build/rag.node
echo "bundled $(ls $LIBS_DIR | wc -l) libs + rpath patched"
```

### `packages/rag/.github/workflows/build.yml` (skeleton)

Matrix build, no GPU needed. Uploads `build/rag.node` + `build/gpu-libs/` as artifacts for the release workflow to pick up.

```yaml
name: build
on: [push, pull_request]
jobs:
  build:
    strategy:
      matrix:
        include:
          - os: ubuntu-latest
            target: linux-x64
          - os: macos-14
            target: darwin-arm64
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: prefix-dev/setup-pixi@v0.8.1
        with:
          pixi-version: v0.34.0
          cache: true
      - run: pixi run bash build.sh
      - if: runner.os == 'Linux'
        run: sudo apt-get install -y patchelf && pixi run bash scripts/bundle-libs.sh
      - uses: actions/upload-artifact@v4
        with:
          name: rag-${{ matrix.target }}
          path: |
            build/rag.node
            build/gpu-libs/
```

## Hand-off checklist for the mojo-addon-examples session

1. **Prep:** move existing top-level addons under `examples/`; single commit.
2. **Scaffold:** create `packages/rag/` from the skeleton above.
3. **Copy sources from napi-mojo:**
   - `napi-mojo/src/gpu/lib.mojo` → `packages/rag/src/lib.mojo`
   - `napi-mojo/src/addon/gpu_linalg.mojo` → `packages/rag/src/linalg.mojo`
   - `napi-mojo/tests/gpu-matmul.test.js` → `packages/rag/tests/rag.test.js` (rename matmul → rag where appropriate)
4. **Decide napi-mojo framework delivery:** pick one:
   - Git submodule `napi-mojo` at `packages/rag/vendor/napi-mojo/` (pinned to v0.4.0 tag)
   - Vendored copy (simpler, loses upstream sync — fine if napi-mojo is stable)
   - Pixi path dep (requires monorepo co-location — only works if napi-mojo also lives in mojo-addon-examples)
5. **Adapt `build.sh`** from napi-mojo to point at the framework location chosen in (4).
6. **Verify local build:** `cd packages/rag && pixi run bash build.sh && npm test` (CPU-side tests should pass on dev machine without GPU — only tests that actually launch kernels need GPU).
7. **CI:** commit `build.yml`; first PR should produce artifacts for both platforms.
8. **Pre-publish smoke test:** manually run the GHA-built Linux artifact on RunPod H100 once to confirm the bundled rpath works end-to-end (reuse `napi-mojo/spike/gpu-fatbin/runpod.sh` as a template).
9. **Publish v0.1.0:** `npm publish` for `@qkstat/rag-linux-x64`, `@qkstat/rag-darwin-arm64`, then `@qkstat/rag`.
10. **Clean up napi-mojo:** once downstream publish succeeds, back in napi-mojo repo remove `src/gpu/`, `src/addon/gpu_linalg.mojo`, the GPU half of `build.sh` + `index.js`, `tests/gpu-matmul.test.js`, `examples/gpu-matmul.js`. Drop pixi dep from `max` back to `mojo`. Release napi-mojo v0.5.0 (breaking: GPU addon moved).

## What NOT to do

- Don't split `@qkstat/rag-linux-x64-cuda-sm_80` / `sm_89` / `sm_90` — spike proved one build covers all arches via driver JIT. Adding a native sm_90 prebuilt is a future optimization if Hopper tensor-core perf becomes a bottleneck, not a v0.1.0 concern.
- Don't attempt fat binaries — Mojo doesn't support multi-arch `--target-accelerator`.
- Don't bundle CUDA toolkit. The 7 `.so`s from pixi are enough; the driver handles the rest.
- Don't block v0.1.0 on GPU CI runners. Manual RunPod per release is fine until the release cadence demands otherwise.
