#!/usr/bin/env bash
#
# Builds game_fixes.so for a Linux CS2 server. No docker needed.
#
#   ./build.sh                 normal build
#   ./build.sh --update        pull the latest SDKs first (do this when a CS2
#                              update breaks the plugin)
#   ./build.sh --clean         wipe the build folder first
#   SEMVER=v1.0.21-nh ./build.sh   set the version "meta list" shows
#
# It compiles inside Valve's Steam Runtime (sniper) SDK using bwrap, with the
# same gcc-14 the game itself is built with, so the result runs anywhere the
# game does. Downloads go into .deps/ (about 4 GB). Delete that folder if you
# want a fresh start.
#
# You get dist/addons/ (copy into game/csgo/) and a tar.gz next to it.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPS="${GAMEFIXES_DEPS:-$ROOT/.deps}"
BUILD="$DEPS/build"
RT="$DEPS/steamrt-sniper"
SEMVER="${SEMVER:-v1.0.20-nh}"

S2SDK_URL="https://github.com/alliedmodders/s2sdk.git"            # branch cs2
MMS_URL="https://github.com/alliedmodders/metamod-source.git"      # master, carries KHook
MANIFESTS_URL="https://github.com/Source2Mod/s2sdk-manifests.git"
RT_BASE="https://repo.steampowered.com/steamrt3/images"
RT_FILE="com.valvesoftware.SteamRuntime.Sdk-amd64,i386-sniper-sysroot.tar.gz"

UPDATE=0
CLEAN=0
for arg in "$@"; do
    case "$arg" in
        --update) UPDATE=1 ;;
        --clean)  CLEAN=1 ;;
        -h|--help) sed -n '2,18p' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) echo "Unknown option: $arg (try --help)" >&2; exit 1 ;;
    esac
done

for tool in git curl tar bwrap sha256sum; do
    command -v "$tool" >/dev/null || { echo "ERROR: '$tool' is needed (bwrap is the 'bubblewrap' package)." >&2; exit 1; }
done

mkdir -p "$DEPS"

# --- SDK checkouts -----------------------------------------------------------
fetch() { # <dir> <url> <branch> [extra clone args]
    local dir="$DEPS/$1" url="$2" branch="$3"; shift 3
    if [ ! -d "$dir/.git" ]; then
        echo "=== Cloning $url ($branch)"
        git clone --depth 1 --branch "$branch" "$@" "$url" "$dir"
    elif [ "$UPDATE" = 1 ]; then
        echo "=== Updating $dir"
        git -C "$dir" pull --ff-only --depth 1
        git -C "$dir" submodule update --init --recursive --depth 1
    fi
}
fetch s2sdk "$S2SDK_URL" cs2
fetch metamod-source "$MMS_URL" master --recursive --shallow-submodules
fetch s2sdk-manifests "$MANIFESTS_URL" master

# --- Steam Runtime SDK (the build environment) -------------------------------
if [ ! -x "$RT/usr/bin/g++-14" ]; then
    echo "=== Downloading the Steam Runtime sniper SDK (about 1.2 GB)"
    tarball="$DEPS/steamrt-sniper-sdk.tar.gz"
    encoded="${RT_FILE//,/%2C}"
    ok=0
    for attempt in 1 2 3 4 5 6 7 8 9 10; do
        # Their server likes to cut big downloads off, so resume instead of restarting.
        if curl -fL --http1.1 -C - --retry 3 -o "$tarball" "$RT_BASE/latest-container-runtime-public-beta/$encoded"; then
            ok=1; break
        fi
        echo "    transfer interrupted, resuming (attempt $attempt)"
    done
    [ "$ok" = 1 ] || { echo "ERROR: could not download the runtime SDK." >&2; exit 1; }

    echo "=== Unpacking"
    rm -rf "$RT.tmp"; mkdir -p "$RT.tmp"
    tar -xzf "$tarball" -C "$RT.tmp" --no-same-owner

    # The checksum list in "latest" is sometimes out of date, so check against
    # the list for the build we actually got.
    build_id="$(grep -h '^BUILD_ID=' "$RT.tmp/usr/lib/os-release" | head -n1 | cut -d= -f2 | tr -d '"')"
    want="$(curl -fsSL "$RT_BASE/$build_id/SHA256SUMS" | grep -F "*$RT_FILE" | cut -d' ' -f1)"
    have="$(sha256sum "$tarball" | cut -d' ' -f1)"
    if [ -z "$want" ] || [ "$want" != "$have" ]; then
        rm -rf "$RT.tmp"
        echo "ERROR: checksum mismatch for the runtime SDK $build_id (expected '${want:-?}', got '$have')." >&2
        echo "       Delete $tarball and run again." >&2
        exit 1
    fi
    echo "    runtime $build_id, checksum ok"
    mkdir -p "$RT.tmp/src" "$RT.tmp/deps" "$RT.tmp/build"
    rm -rf "$RT"; mv "$RT.tmp" "$RT"
    rm -f "$tarball"
fi
mkdir -p "$RT/src" "$RT/deps" "$RT/build"

# --- Build -------------------------------------------------------------------
[ "$CLEAN" = 1 ] && rm -rf "$BUILD"
mkdir -p "$BUILD"

SHA="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo "s2sdk-$(git -C "$DEPS/s2sdk" rev-parse --short HEAD)")"

echo "=== Building $SEMVER ($SHA)"
bwrap --bind "$RT" / --dev /dev --proc /proc --tmpfs /tmp \
    --bind "$ROOT" /src --ro-bind "$DEPS/s2sdk" /deps/s2sdk \
    --ro-bind "$DEPS/metamod-source" /deps/metamod-source \
    --ro-bind "$DEPS/s2sdk-manifests" /deps/s2sdk-manifests \
    --bind "$BUILD" /build \
    --unshare-user --uid 0 --gid 0 --unshare-net --die-with-parent \
    --setenv PATH /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    --setenv HOME /tmp --setenv CC gcc-14 --setenv CXX g++-14 \
    --setenv S2SDK /deps/s2sdk --setenv MMSOURCE_DEV /deps/metamod-source \
    --setenv S2SDK_MANIFESTS_DIR /deps/s2sdk-manifests \
    --setenv SEMVER "$SEMVER" --setenv GITHUB_SHA_SHORT "$SHA" \
    --chdir /build -- /bin/bash -euc '
        cmake -S /src -B /build -G Ninja -DCMAKE_BUILD_TYPE=Release >/dev/null
        cmake --build /build
        so=/build/addons/game_fixes/bin/linuxsteamrt64/game_fixes.so
        # If anything is unresolved here the server will refuse to load the plugin, so fail now.
        if ldd -r "$so" 2>&1 | grep -E "undefined symbol|not found"; then
            echo "ERROR: unresolved symbols in game_fixes.so" >&2; exit 1
        fi
    '

# --- Package -----------------------------------------------------------------
rm -rf "$ROOT/dist"
mkdir -p "$ROOT/dist"
cp -r "$BUILD/addons" "$ROOT/dist/addons"
tar -czf "$ROOT/dist/NH_GameFixes_${SEMVER}-linux.tar.gz" -C "$ROOT/dist" addons

echo
echo "=== Done"
echo "    $ROOT/dist/addons   (copy into game/csgo/)"
echo "    $ROOT/dist/NH_GameFixes_${SEMVER}-linux.tar.gz"
