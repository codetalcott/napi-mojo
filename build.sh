#!/usr/bin/env bash
# Build script for napi-mojo
# Compiles src/lib.mojo into a Node.js native addon (index.node)
set -euo pipefail

mkdir -p build

# Detect platform-specific shared library extension
case "$(uname -s)" in
    Darwin) LIB_EXT="dylib" ;;
    Linux)  LIB_EXT="so" ;;
    *)      echo "Unsupported platform: $(uname -s)" >&2; exit 1 ;;
esac

# Compile Mojo source to a shared library
# --emit shared-lib produces a .dylib (macOS) or .so (Linux)
# On Linux x86_64, target Haswell (2013) to avoid AVX-512 instructions
# that aren't available on GitHub Actions runners
MCPU_FLAG=""
if [ "$(uname -s)" = "Linux" ] && [ "$(uname -m)" = "x86_64" ]; then
    MCPU_FLAG="--mcpu haswell"
fi
# Warnings are errors. Every compile of this repo's own Mojo in CI carries
# --Werror: a deprecation that only warns is invisible until someone reads the
# log, which is how 27 of them sat in the build output through the Mojo 1.1.0
# bump with every signal green (docs/plan-lazily-checked-artifacts.md). During
# a toolchain bump — when the runbook says to fix hard errors before
# deprecations — opt out with NAPI_MOJO_WERROR=0. scripts/check-werror.mjs
# proves in CI that the flag still fails on a warning inside an imported module.
WERROR_FLAG="--Werror"
if [ "${NAPI_MOJO_WERROR:-1}" = "0" ]; then
    WERROR_FLAG=""
fi
mojo build --emit shared-lib ${MCPU_FLAG} ${WERROR_FLAG} src/lib.mojo -o "build/libnapi_mojo.${LIB_EXT}"

# Node.js requires native addons to have the .node extension
mv "build/libnapi_mojo.${LIB_EXT}" build/index.node

echo "Build complete: build/index.node"
