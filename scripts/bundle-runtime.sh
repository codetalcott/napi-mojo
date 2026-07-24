#!/usr/bin/env bash
# Bundle Mojo runtime libraries alongside index.node and fix rpaths
# so the binary is fully self-contained (no Mojo installation needed).
# Run AFTER tests pass, before packaging for npm.
#
# THE DEPENDENCY SET IS COMPUTED, NOT HARDCODED.
#
# It used to be a fixed list of four libraries, and that list silently went
# stale: on Linux the Mojo runtime also pulls in libNVPTX.so, so the published
# @napi-mojo/linux-x64 package fails at require() with ERR_DLOPEN_FAILED for
# anyone without a Mojo installation. Confirmed by unpacking 0.5.1 from npm —
# it contains only the four. macOS stayed correct by luck: its closure really
# is those four, because they reference nothing but each other.
#
# Nothing caught it because `npm test` runs against the PRE-bundle build with
# the pixi environment still on the library search path. publish.yml now loads
# the bundled binary with the search paths cleared, which is what surfaced it.
#
# A hardcoded list cannot survive Mojo nightly bumps that change the runtime's
# own dependency graph. Walking the graph can.
set -euo pipefail

PIXI_LIB="$(cd "$(dirname "$(which mojo)")/../lib" && pwd)"

if [ "$(uname -s)" = "Darwin" ]; then
    EXT=dylib
else
    EXT=so
fi

# deps_of FILE — print basenames of FILE's dependencies that live in the pixi
# environment. System libraries (libc, libSystem, …) are deliberately excluded:
# they belong to the host, and bundling them would be both wrong and a
# licensing problem.
#
# Must run BEFORE any rpath rewriting, while the binaries still point at
# PIXI_LIB — that is what lets the loader resolve them for us.
deps_of() {
    if [ "$EXT" = "dylib" ]; then
        # Mojo's dylibs reference each other as @rpath/libFoo.dylib.
        otool -L "$1" 2>/dev/null | tail -n +2 | awk '{print $1}' \
            | sed -n 's|^@rpath/||p' || true
    else
        # ldd prints "libfoo.so => /resolved/path/libfoo.so (0x...)"; keep only
        # the ones that resolved inside the pixi env.
        ldd "$1" 2>/dev/null \
            | awk '{for (i = 1; i <= NF; i++) if ($i == "=>") print $(i + 1)}' \
            | { grep "^${PIXI_LIB}/" || true; } | xargs -r -n1 basename
    fi
}

# Breadth-first walk from index.node until no new pixi-env library appears.
bundled=""
worklist="build/index.node"
while [ -n "$worklist" ]; do
    next=""
    for f in $worklist; do
        for name in $(deps_of "$f"); do
            case " $bundled " in *" $name "*) continue ;; esac
            [ -f "$PIXI_LIB/$name" ] || continue
            cp "$PIXI_LIB/$name" "build/$name"
            bundled="$bundled $name"
            next="$next build/$name"
        done
    done
    worklist="$next"
done

if [ -z "$bundled" ]; then
    # Distinguish "nothing to do because it already ran" from "the pixi
    # environment is not where we think it is". Re-running against an
    # already-bundled build finds nothing, because the load paths it looks for
    # have already been rewritten to @loader_path/$ORIGIN.
    if ls build/*."$EXT" >/dev/null 2>&1; then
        echo "error: build/ already contains bundled libraries — this script has" >&2
        echo "       already run against this build. Re-run build.sh first." >&2
    else
        echo "error: no Mojo runtime libraries found under $PIXI_LIB" >&2
    fi
    exit 1
fi

# A dependency the loader cannot resolve at all prints "=> not found" and would
# drop silently out of the walk above, since it never matches PIXI_LIB. Say so
# here rather than letting a consumer's require() be the thing that finds out.
if [ "$EXT" = "so" ]; then
    for f in build/index.node $(printf 'build/%s\n' $bundled); do
        if ldd "$f" 2>/dev/null | grep -q "not found"; then
            echo "error: unresolved dependencies in $f:" >&2
            ldd "$f" | grep "not found" >&2
            exit 1
        fi
    done
fi

# --- rewrite load paths so everything resolves next to index.node ------------
if [ "$EXT" = "dylib" ]; then
    for name in $bundled; do
        install_name_tool -id "@loader_path/${name}" "build/${name}"
        for dep in $bundled; do
            install_name_tool -change "@rpath/${dep}" "@loader_path/${dep}" "build/${name}" 2>/dev/null || true
        done
    done
    # Fix index.node: self-reference, rpath, and sibling lib references
    install_name_tool -id @loader_path/index.node build/index.node
    install_name_tool -change "build/libnapi_mojo.dylib" "@loader_path/index.node" build/index.node 2>/dev/null || true
    install_name_tool -delete_rpath "$PIXI_LIB" build/index.node 2>/dev/null || true
    install_name_tool -add_rpath @loader_path build/index.node 2>/dev/null || true
    for dep in $bundled; do
        install_name_tool -change "@rpath/${dep}" "@loader_path/${dep}" build/index.node 2>/dev/null || true
    done
    # Re-sign all modified binaries (required on macOS arm64)
    codesign --force --sign - build/index.node
    for name in $bundled; do
        codesign --force --sign - "build/${name}"
    done
else
    patchelf --set-rpath '$ORIGIN' build/index.node
    for name in $bundled; do
        patchelf --set-rpath '$ORIGIN' "build/${name}"
    done
fi

echo "Runtime bundled ($(printf '%s\n' $bundled | wc -w | tr -d ' ') libraries):"
for name in $bundled; do
    echo "  $name"
done
