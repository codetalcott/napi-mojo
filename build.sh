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
mojo build --emit shared-lib src/lib.mojo -o "build/libnapi_mojo.${LIB_EXT}"

# Node.js requires native addons to have the .node extension
mv "build/libnapi_mojo.${LIB_EXT}" build/index.node

echo "Build complete: build/index.node"
