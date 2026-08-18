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

# Usage: bundle-runtime.sh [path/to/addon.node]
# Default keeps the historical publish.yml invocation working unchanged.
# The napi-mojo CLI (`napi-mojo build --bundle`) passes an explicit path.
NODE_BIN="${1:-build/index.node}"
OUT_DIR="$(dirname "$NODE_BIN")"
NODE_BASE="$(basename "$NODE_BIN")"

if [ "$(uname -s)" = "Darwin" ]; then
    EXT=dylib
else
    EXT=so
fi

# THE TOOLCHAIN LIBRARY DIRECTORY IS DISCOVERED, NOT ASSUMED.
#
# This used to be `dirname(which mojo)/../lib`, which silently encodes the
# conda/pixi layout (<env>/bin/mojo next to <env>/lib). That is not the only
# layout Modular ships. Under a uv/pip install the same toolchain lands as:
#
#   .venv/bin/mojo                                  <- a POSIX SHELL SHIM
#   .venv/lib/python3.13/site-packages/modular/lib  <- the actual libraries
#
# There, `../lib` resolves to .venv/lib, which contains zero Mojo libraries.
# Worse, the shim is not a symlink, so realpath() does not rescue it either.
# The old expression would have "succeeded" and then found nothing to bundle.
#
# Candidates are tried in order and each is VALIDATED by requiring it to
# actually contain a library the built addon depends on, so a wrong guess is
# rejected rather than silently producing an empty bundle.
#
# The first candidate is the strongest: the compiler stamps the library
# directory into the binary itself as LC_RPATH (macOS) / RUNPATH (Linux). That
# is by definition where the loader looks, so it cannot disagree with reality
# the way a path convention can.
mojo_lib_candidates() {
    if [ "$EXT" = "dylib" ]; then
        otool -l "$NODE_BIN" 2>/dev/null \
            | awk '/LC_RPATH/{r=1} r && /path /{print $2; r=0}'
    else
        patchelf --print-rpath "$NODE_BIN" 2>/dev/null | tr ':' '\n'
    fi

    # The toolchain root reached from the `mojo` on PATH. Covers conda/pixi
    # directly, and uv once the shim is followed to the real binary.
    local m
    m="$(command -v mojo || true)"
    if [ -n "$m" ]; then
        echo "$(dirname "$m")/../lib"
        # A uv shim is a shell script that execs the real binary out of
        # site-packages; recover the path it points at.
        if [ -f "$m" ] && head -c2 "$m" 2>/dev/null | grep -q '#!'; then
            grep -oE '/[^"'"'"' ]*/modular/bin/mojo' "$m" 2>/dev/null \
                | head -1 | sed 's|/bin/mojo|/lib|'
        fi
    fi
}

# The addon's own DIRECT dependency basenames. Validating against these rather
# than a generic lib*.EXT glob matters: a conda env's lib/ holds hundreds of
# unrelated libraries, so the glob would accept a directory that cannot
# actually satisfy the addon.
# `|| true` is load-bearing: under `set -o pipefail` a failing otool/patchelf
# (missing file) makes the whole command substitution non-zero, and `set -e`
# would then kill the script BEFORE the diagnostics below ever print.
needed_basenames() {
    if [ "$EXT" = "dylib" ]; then
        { otool -L "$NODE_BIN" 2>/dev/null || true; } | tail -n +2 \
            | awk '{print $1}' | sed -n 's|^@rpath/||p'
    else
        patchelf --print-needed "$NODE_BIN" 2>/dev/null || true
    fi
}

if [ ! -f "$NODE_BIN" ]; then
    echo "error: $NODE_BIN not found — build the addon first." >&2
    exit 1
fi

NEEDED="$(needed_basenames)"
if [ -z "$NEEDED" ]; then
    # Distinguish "already bundled" from "genuinely broken". Once this script
    # has run, the addon's load paths are rewritten from @rpath/$ORIGIN to
    # @loader_path, so there are no @rpath entries left to key on — which looks
    # identical to a broken binary unless we say otherwise.
    if ls "$OUT_DIR"/*."$EXT" >/dev/null 2>&1; then
        echo "error: $OUT_DIR/ already contains bundled libraries — this script has" >&2
        echo "       already run against this build. Rebuild the addon first." >&2
    else
        echo "error: $NODE_BIN has no Mojo runtime dependencies to key on." >&2
        echo "       Expected @rpath/RUNPATH entries; build the addon first." >&2
    fi
    exit 1
fi

PIXI_LIB=""
for cand in $(mojo_lib_candidates); do
    [ -d "$cand" ] || continue
    cand="$(cd "$cand" && pwd)"
    for name in $NEEDED; do
        if [ -f "$cand/$name" ]; then
            PIXI_LIB="$cand"
            break 2
        fi
    done
done

if [ -z "$PIXI_LIB" ]; then
    echo "error: could not locate the Mojo runtime library directory." >&2
    echo "       Tried, in order:" >&2
    mojo_lib_candidates | sed 's/^/         /' >&2
    echo "       Is a Mojo toolchain on PATH, and has build.sh run?" >&2
    exit 1
fi

echo "Mojo runtime libraries: $PIXI_LIB"

# deps_of FILE — print basenames of FILE's dependencies that live in the pixi
# environment. Libraries that resolve outside it (libc, libSystem, …) belong to
# the host and are left alone.
#
# Note what this does include on Linux: pixi ships its own libstdc++.so.6 and
# libgcc_s.so.1, and the Mojo runtime is built against those, so they are part
# of the closure and get bundled. That is deliberate — it is what makes the
# package work on a host whose C++ runtime is older than Mojo requires — and it
# is permitted: libstdc++/libgcc carry the GCC Runtime Library Exception, which
# exists precisely to allow redistribution alongside a binary.
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

# Breadth-first walk from the addon until no new pixi-env library appears.
bundled=""
worklist="$NODE_BIN"
while [ -n "$worklist" ]; do
    next=""
    for f in $worklist; do
        for name in $(deps_of "$f"); do
            case " $bundled " in *" $name "*) continue ;; esac
            [ -f "$PIXI_LIB/$name" ] || continue
            cp "$PIXI_LIB/$name" "$OUT_DIR/$name"
            bundled="$bundled $name"
            next="$next $OUT_DIR/$name"
        done
    done
    worklist="$next"
done

if [ -z "$bundled" ]; then
    # Distinguish "nothing to do because it already ran" from "the pixi
    # environment is not where we think it is". Re-running against an
    # already-bundled build finds nothing, because the load paths it looks for
    # have already been rewritten to @loader_path/$ORIGIN.
    if ls "$OUT_DIR"/*."$EXT" >/dev/null 2>&1; then
        echo "error: $OUT_DIR/ already contains bundled libraries — this script has" >&2
        echo "       already run against this build. Rebuild the addon first." >&2
    else
        echo "error: no Mojo runtime libraries found under $PIXI_LIB" >&2
    fi
    exit 1
fi

# A dependency the loader cannot resolve at all prints "=> not found" and would
# drop silently out of the walk above, since it never matches PIXI_LIB. Say so
# here rather than letting a consumer's require() be the thing that finds out.
if [ "$EXT" = "so" ]; then
    for f in "$NODE_BIN" $(for n in $bundled; do echo "$OUT_DIR/$n"; done); do
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
        install_name_tool -id "@loader_path/${name}" "$OUT_DIR/${name}"
        for dep in $bundled; do
            install_name_tool -change "@rpath/${dep}" "@loader_path/${dep}" "$OUT_DIR/${name}" 2>/dev/null || true
        done
    done
    # Fix the addon: self-reference, rpath, and sibling lib references.
    # The self-reference can be recorded under the pre-rename dylib path
    # (build.sh output) or the addon's own path (CLI direct -o); change both.
    install_name_tool -id "@loader_path/${NODE_BASE}" "$NODE_BIN"
    install_name_tool -change "build/libnapi_mojo.dylib" "@loader_path/${NODE_BASE}" "$NODE_BIN" 2>/dev/null || true
    install_name_tool -change "$NODE_BIN" "@loader_path/${NODE_BASE}" "$NODE_BIN" 2>/dev/null || true
    install_name_tool -delete_rpath "$PIXI_LIB" "$NODE_BIN" 2>/dev/null || true
    install_name_tool -add_rpath @loader_path "$NODE_BIN" 2>/dev/null || true
    for dep in $bundled; do
        install_name_tool -change "@rpath/${dep}" "@loader_path/${dep}" "$NODE_BIN" 2>/dev/null || true
    done
    # Re-sign all modified binaries (required on macOS arm64)
    codesign --force --sign - "$NODE_BIN"
    for name in $bundled; do
        codesign --force --sign - "$OUT_DIR/${name}"
    done
else
    patchelf --set-rpath '$ORIGIN' "$NODE_BIN"
    for name in $bundled; do
        patchelf --set-rpath '$ORIGIN' "$OUT_DIR/${name}"
    done
fi

# Record the exact set for downstream steps. publish.yml stages and packs from
# this manifest rather than re-deriving it from a glob, because a glob is how
# libstdc++.so.6 and libgcc_s.so.1 went missing: `build/*.so` does not match a
# versioned soname, and neither does an npm `files` entry of "*.so".
printf '%s\n' $bundled > "$OUT_DIR/bundled-libs.txt"

echo "Runtime bundled ($(printf '%s\n' $bundled | wc -w | tr -d ' ') libraries):"
for name in $bundled; do
    echo "  $name"
done
