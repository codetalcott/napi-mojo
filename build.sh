#!/usr/bin/env bash
# Build script for napi-mojo
# Compiles src/lib.mojo into build/index.node (the CPU addon) and, when a
# GPU target is detected, src/gpu/lib.mojo into build/gpu.node (optional
# GPU linalg primitives, lazily loaded by index.js).
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
mojo build --emit shared-lib ${MCPU_FLAG} src/lib.mojo -o "build/libnapi_mojo.${LIB_EXT}"

# Node.js requires native addons to have the .node extension
mv "build/libnapi_mojo.${LIB_EXT}" build/index.node

echo "Build complete: build/index.node"

# --- GPU addon (optional) ----------------------------------------------------
# Compiled into a separate .node so the CPU binary doesn't link GPU runtime
# (avoids loader failures on hosts without CUDA). Target accelerator is
# auto-detected by platform; override with NAPI_MOJO_GPU_ACCEL="" to skip
# the GPU build entirely, or set an explicit flag like sm_80 to retarget.

ACCEL_FLAG="${NAPI_MOJO_GPU_ACCEL-}"
if [ -z "${NAPI_MOJO_GPU_ACCEL+x}" ]; then
    if [ "$(uname -s)" = "Darwin" ] && [ "$(uname -m)" = "arm64" ]; then
        ACCEL_FLAG="--target-accelerator metal:4"
    elif [ "$(uname -s)" = "Linux" ] && [ "$(uname -m)" = "x86_64" ]; then
        ACCEL_FLAG="--target-accelerator sm_90"
    fi
fi

if [ -n "$ACCEL_FLAG" ]; then
    # src/gpu/lib.mojo sits below src/, so -I src lets it resolve
    # napi.* and addon.* packages the same way src/lib.mojo does.
    if mojo build --emit shared-lib ${MCPU_FLAG} ${ACCEL_FLAG} -I src \
        src/gpu/lib.mojo -o "build/libnapi_mojo_gpu.${LIB_EXT}" 2>&1; then
        mv "build/libnapi_mojo_gpu.${LIB_EXT}" build/gpu.node
        echo "Build complete: build/gpu.node (${ACCEL_FLAG})"
    else
        echo "Build skipped: build/gpu.node (GPU toolchain error; core addon unaffected)"
        rm -f "build/libnapi_mojo_gpu.${LIB_EXT}"
    fi
else
    echo "Build skipped: build/gpu.node (no GPU target for this platform)"
fi
