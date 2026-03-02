#!/usr/bin/env bash
# Build script for napi-mojo
# Compiles src/lib.mojo into a Node.js native addon (index.node)
set -euo pipefail

mkdir -p build

# Compile Mojo source to a shared library
# --emit shared-lib produces a .dylib (macOS) or .so (Linux)
mojo build --emit shared-lib src/lib.mojo -o build/libnapi_mojo.dylib

# Node.js requires native addons to have the .node extension
mv build/libnapi_mojo.dylib build/index.node

echo "Build complete: build/index.node"
