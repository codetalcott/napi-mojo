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
mojo build --emit shared-lib ${MCPU_FLAG} src/lib.mojo -o "build/libnapi_mojo.${LIB_EXT}"

# Node.js requires native addons to have the .node extension
mv "build/libnapi_mojo.${LIB_EXT}" build/index.node

# Bundle Mojo runtime libraries and fix rpaths so the binary is self-contained
PIXI_LIB="$(dirname "$(which mojo)")/../lib"
MOJO_LIBS="libKGENCompilerRTShared libAsyncRTMojoBindings libAsyncRTRuntimeGlobals libMSupportGlobals"

if [ "$(uname -s)" = "Darwin" ]; then
    for lib in $MOJO_LIBS; do
        cp "$PIXI_LIB/${lib}.dylib" build/
        install_name_tool -id "@loader_path/${lib}.dylib" "build/${lib}.dylib"
        # Fix any @rpath references to sibling libs
        for dep in $MOJO_LIBS; do
            install_name_tool -change "@rpath/${dep}.dylib" "@loader_path/${dep}.dylib" "build/${lib}.dylib" 2>/dev/null || true
        done
    done
    # Fix index.node: self-reference, rpath, and sibling lib references
    install_name_tool -id @loader_path/index.node build/index.node
    install_name_tool -change "build/libnapi_mojo.dylib" "@loader_path/index.node" build/index.node
    install_name_tool -delete_rpath "$PIXI_LIB" build/index.node 2>/dev/null || true
    install_name_tool -add_rpath @loader_path build/index.node
    for dep in $MOJO_LIBS; do
        install_name_tool -change "@rpath/${dep}.dylib" "@loader_path/${dep}.dylib" build/index.node 2>/dev/null || true
    done
else
    for lib in $MOJO_LIBS; do
        cp "$PIXI_LIB/${lib}.so" build/
    done
    # Rewrite rpath in index.node and all libs to look next to themselves
    patchelf --set-rpath '$ORIGIN' build/index.node
    for lib in $MOJO_LIBS; do
        patchelf --set-rpath '$ORIGIN' "build/${lib}.so"
    done
fi

echo "Build complete: build/index.node"
