#!/usr/bin/env bash
# Bundle Mojo runtime libraries alongside index.node and fix rpaths
# so the binary is fully self-contained (no Mojo installation needed).
# Run AFTER tests pass, before packaging for npm.
set -euo pipefail

PIXI_LIB="$(dirname "$(which mojo)")/../lib"
MOJO_LIBS="libKGENCompilerRTShared libAsyncRTMojoBindings libAsyncRTRuntimeGlobals libMSupportGlobals"

if [ "$(uname -s)" = "Darwin" ]; then
    for lib in $MOJO_LIBS; do
        cp "$PIXI_LIB/${lib}.dylib" build/
        install_name_tool -id "@loader_path/${lib}.dylib" "build/${lib}.dylib"
        for dep in $MOJO_LIBS; do
            install_name_tool -change "@rpath/${dep}.dylib" "@loader_path/${dep}.dylib" "build/${lib}.dylib" 2>/dev/null || true
        done
    done
    # Fix index.node: self-reference, rpath, and sibling lib references
    install_name_tool -id @loader_path/index.node build/index.node
    install_name_tool -change "build/libnapi_mojo.dylib" "@loader_path/index.node" build/index.node
    install_name_tool -delete_rpath "$PIXI_LIB" build/index.node 2>/dev/null || true
    install_name_tool -add_rpath @loader_path build/index.node 2>/dev/null || true
    for dep in $MOJO_LIBS; do
        install_name_tool -change "@rpath/${dep}.dylib" "@loader_path/${dep}.dylib" build/index.node 2>/dev/null || true
    done
else
    for lib in $MOJO_LIBS; do
        cp "$PIXI_LIB/${lib}.so" build/
    done
    patchelf --set-rpath '$ORIGIN' build/index.node
    for lib in $MOJO_LIBS; do
        patchelf --set-rpath '$ORIGIN' "build/${lib}.so"
    done
fi

echo "Runtime bundled: $(ls build/*.dylib build/*.so 2>/dev/null | wc -l | tr -d ' ') libraries"
