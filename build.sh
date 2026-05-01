#!/usr/bin/env bash
# Build script for napi-mojo
# Compiles src/lib.mojo + src/napi_callbacks.c into a Node.js native addon
# (build/index.node).
#
# The C file owns the actual N-API entry point (napi_register_module_v1)
# and the C-callable finalizer trampolines. Mojo provides the entry-point
# logic (napi_mojo_register_module) and each finalizer body as
# @export(ABI="C") symbols. See src/napi_callbacks.c for why.
set -euo pipefail

mkdir -p build

# Detect platform-specific shared library extension and rpath flag
case "$(uname -s)" in
    Darwin)
        LIB_EXT="dylib"
        RPATH_DIR="@loader_path/../.pixi/envs/default/lib"
        ;;
    Linux)
        LIB_EXT="so"
        RPATH_DIR="\$ORIGIN/../.pixi/envs/default/lib"
        ;;
    *) echo "Unsupported platform: $(uname -s)" >&2; exit 1 ;;
esac

# On Linux x86_64, target Haswell (2013) to avoid AVX-512 instructions
# that aren't available on GitHub Actions runners.
MCPU_FLAG=""
if [ "$(uname -s)" = "Linux" ] && [ "$(uname -m)" = "x86_64" ]; then
    MCPU_FLAG="--mcpu haswell"
fi

# Step 1: compile Mojo to a relocatable object file.
mojo build --emit object ${MCPU_FLAG} src/lib.mojo -o build/lib.o

# Step 2: compile the C trampolines.
clang -c -O2 -fPIC src/napi_callbacks.c -o build/napi_callbacks.o

# Step 3: link Mojo + C objects into the .node, with rpath to Mojo's
# runtime libs (libKGENCompilerRTShared, libAsyncRTMojoBindings).
RUNTIME_LIB_DIR=".pixi/envs/default/lib"
clang -shared \
    build/lib.o \
    build/napi_callbacks.o \
    -L "${RUNTIME_LIB_DIR}" \
    -lKGENCompilerRTShared \
    -lAsyncRTMojoBindings \
    -Wl,-rpath,"${RPATH_DIR}" \
    -o build/index.node

echo "Build complete: build/index.node"
