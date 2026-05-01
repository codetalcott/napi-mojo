#!/usr/bin/env bash
# @napi-mojo/gpu — build script
#
# Compiles gpu/src/lib.mojo into gpu/build/gpu.node, an N-API native addon
# loadable by Node 22.12+.
#
# Auto-detects the GPU target by platform; override with NAPI_MOJO_GPU_ACCEL.
# Set NAPI_MOJO_GPU_ACCEL="" to skip GPU codegen (useful when the build
# host has no GPU but the binary will be cross-shipped or just isn't
# wanted; you'll get a no-GPU-available error from the runtime instead).
#
# Reuses napi-mojo's framework code via -I ../src so we don't have to
# vendor or duplicate it. Long-term we may extract @napi-mojo/framework
# into its own published package.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAPI_MOJO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

mkdir -p "${SCRIPT_DIR}/build"

case "$(uname -s)" in
    Darwin) LIB_EXT="dylib" ;;
    Linux)  LIB_EXT="so" ;;
    *) echo "Unsupported platform: $(uname -s)" >&2; exit 1 ;;
esac

# Linux x86_64 GitHub runners don't have AVX-512; target Haswell to match
# the napi-mojo CPU build for binary portability.
MCPU_FLAG=""
if [ "$(uname -s)" = "Linux" ] && [ "$(uname -m)" = "x86_64" ]; then
    MCPU_FLAG="--mcpu haswell"
fi

# Auto-detect GPU target (override with NAPI_MOJO_GPU_ACCEL).
ACCEL_FLAG="${NAPI_MOJO_GPU_ACCEL-}"
if [ -z "${NAPI_MOJO_GPU_ACCEL+x}" ]; then
    if [ "$(uname -s)" = "Darwin" ] && [ "$(uname -m)" = "arm64" ]; then
        ACCEL_FLAG="--target-accelerator metal:4"
    elif [ "$(uname -s)" = "Linux" ] && [ "$(uname -m)" = "x86_64" ]; then
        # sm_90 = H100. Override for older NVIDIA hardware.
        ACCEL_FLAG="--target-accelerator sm_90"
    fi
fi

# -I flags resolve:
#   napi.*           → ${NAPI_MOJO_ROOT}/src         (napi-mojo framework)
#   module_data, registry, ops.* → ${SCRIPT_DIR}/src (this package)
mojo build \
    --emit shared-lib \
    ${MCPU_FLAG} \
    ${ACCEL_FLAG} \
    -I "${NAPI_MOJO_ROOT}/src" \
    -I "${SCRIPT_DIR}/src" \
    "${SCRIPT_DIR}/src/lib.mojo" \
    -o "${SCRIPT_DIR}/build/libnapi_mojo_gpu.${LIB_EXT}"

mv "${SCRIPT_DIR}/build/libnapi_mojo_gpu.${LIB_EXT}" "${SCRIPT_DIR}/build/gpu.node"

echo "Build complete: ${SCRIPT_DIR}/build/gpu.node"
