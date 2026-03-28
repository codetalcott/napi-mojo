#!/usr/bin/env bash
# Build the codegen example addon
#
# Usage: cd examples/codegen && bash build.sh
set -euo pipefail

EXAMPLE_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$EXAMPLE_DIR/../.." && pwd)"

# Step 1: Generate callbacks and structs from our exports.toml
mkdir -p "$EXAMPLE_DIR/generated"
touch "$EXAMPLE_DIR/generated/__init__.mojo"

NAPI_MOJO_TOML="$EXAMPLE_DIR/exports.toml" \
NAPI_MOJO_OUT="$EXAMPLE_DIR/generated" \
    node "$ROOT_DIR/scripts/generate-addon.mjs"

# Step 2: Compile
mkdir -p "$EXAMPLE_DIR/build"

PLATFORM="$(uname -s)"
if [ "$PLATFORM" = "Darwin" ]; then
    EXT="dylib"
else
    EXT="so"
fi

echo "Compiling lib.mojo..."
pixi run mojo build --emit shared-lib \
    -I "$ROOT_DIR/src" \
    "$EXAMPLE_DIR/lib.mojo" \
    -o "$EXAMPLE_DIR/build/libcodegen.$EXT"

mv "$EXAMPLE_DIR/build/libcodegen.$EXT" "$EXAMPLE_DIR/build/index.node"
echo "Build complete: examples/codegen/build/index.node"
