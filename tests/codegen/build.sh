#!/usr/bin/env bash
# Kitchen-sink compile target for scripts/generate-addon.mjs (compile-only).
#
# The drift gate (npm run generate:addon && git diff --exit-code src/generated/)
# only proves the templates src/exports.toml instantiates. This script
# generates from kitchen-sink.toml — which instantiates every emitter branch —
# into a scratch generated/ dir and compiles the result. Any template that
# emits Mojo the current toolchain rejects fails HERE instead of rotting until
# a user's exports.toml first reaches it (that has happened three times).
#
# Usage: bash tests/codegen/build.sh [output.so]
set -euo pipefail

KS_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$KS_DIR/../.." && pwd)"
OUT="${1:-/tmp/kitchen_sink.so}"

# Step 1: generate callbacks + structs from the kitchen-sink declarations
mkdir -p "$KS_DIR/generated"
touch "$KS_DIR/generated/__init__.mojo"

NAPI_MOJO_TOML="$KS_DIR/kitchen-sink.toml" \
NAPI_MOJO_OUT="$KS_DIR/generated" \
    node "$ROOT_DIR/scripts/generate-addon.mjs"

# Step 2: compile — this is the actual test. register_generated references
# every generated callback, so every template's output gets type-checked.
pixi run mojo build --emit shared-lib \
    -I "$ROOT_DIR/src" \
    "$KS_DIR/lib.mojo" \
    -o "$OUT"

echo "codegen kitchen sink compiled OK: $OUT"
