#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"
# shellcheck source=lib.sh
. "$DIR/lib.sh"

resolve_air_env


CLIENT="$DIR/loader"
BUILD="$DIR/build"
STAGING="$BUILD/staging"

UPSTREAM_GAMEFILES="$BUILD/gamefiles-upstream"
LEGACY_GAMEFILES="$CLIENT/gamefiles"

HAXE_API_DIR="${HAXE_API_DIR:-$DIR/../aqw-haxe-api}"
HAXE_UI_DIR="${HAXE_UI_DIR:-$DIR/../aqw-haxe-ui}"

for required in "$CLIENT/src/Pocket.as" "$CLIENT/src/ModBootstrap.as" "$CLIENT/Desktop.swf" "$CLIENT/Mobile.swf"; do
    if [ ! -f "$required" ]; then
        echo "ERROR: '$required' is missing - the loader/ tree is incomplete." >&2
        exit 1
    fi
done

if [ "${1:-}" = "--clean" ] || [ "${2:-}" = "--clean" ]; then
    echo "=> Cleaning previous build artifacts..."
    rm -f "$BUILD/Desktop.swf" "$BUILD/Mobile.swf"
fi

mkdir -p "$BUILD"
rm -rf "$STAGING"
mkdir -p "$STAGING"
trap '' EXIT

if [ "${SKIP_SYNC:-0}" = "1" ]; then
    echo "=> [0/6] SKIP_SYNC=1 - using cached gamefiles."
elif ! "$DIR/sync-gamefiles.sh" "$UPSTREAM_GAMEFILES"; then
    echo "ERROR: Could not sync upstream gamefiles." >&2
    echo "       Re-run with SKIP_SYNC=1 to build offline against the cached copies." >&2
    exit 1
fi

echo "=> [0/6] Copying loader/ to sandbox (build/staging/)..."
mkdir -p "$STAGING/libs"
cp -r "$CLIENT/src" "$STAGING/src"
cp -r "$CLIENT/worker-src" "$STAGING/worker-src"
cp -r "$CLIENT/assets" "$STAGING/assets"
cp -r "$CLIENT/icons" "$STAGING/icons"
cp "$CLIENT/Desktop-app.xml" "$STAGING/Desktop-app.xml"
cp "$CLIENT/Mobile-app.xml" "$STAGING/Mobile-app.xml"
cp "$CLIENT/Desktop.swf" "$STAGING/Desktop.swf"
cp "$CLIENT/Mobile.swf" "$STAGING/Mobile.swf"
if [ -d "$CLIENT/libs" ]; then
    cp -r "$CLIENT/libs/." "$STAGING/libs/" 2>/dev/null || true
fi
if [ -d "$UPSTREAM_GAMEFILES" ] && [ -n "$(ls -A "$UPSTREAM_GAMEFILES" 2>/dev/null)" ]; then
    cp -r "$UPSTREAM_GAMEFILES" "$STAGING/gamefiles"
elif [ -d "$LEGACY_GAMEFILES" ]; then
    echo "   Notice: falling back to the legacy loader/gamefiles/ copy."
    cp -r "$LEGACY_GAMEFILES" "$STAGING/gamefiles"
else
    echo "   Notice: no gamefiles found. Run ./sync-gamefiles.sh to fetch the upstream"
    echo "   gamefiles before launching (the client downloads them otherwise)."
fi

DISCORD_EXT="$CLIENT/META-INF/AIR/extensions/fi.joniaromaa.adobeair.discordrpc"
if [ -f "$DISCORD_EXT/catalog.xml" ] && [ -f "$DISCORD_EXT/library.swf" ]; then
    python3 - "$DISCORD_EXT" "$STAGING/libs/DiscordRpc.swc" <<'PY'
import os
import sys
import zipfile

ext_dir, out_path = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out_path, "w", zipfile.ZIP_DEFLATED) as swc:
    swc.write(os.path.join(ext_dir, "catalog.xml"), "catalog.xml")
    swc.write(os.path.join(ext_dir, "library.swf"), "library.swf")
PY
fi

if [ "${SKIP_HAXE:-}" != "1" ]; then
    if [ -d "$HAXE_API_DIR" ]; then
        echo "=> [1/6] Compiling AqwApi (aqw-haxe-api)..."
        run_haxe_build "$HAXE_API_DIR"
        cp "$HAXE_API_DIR/bin/AqwApi.swc" "$STAGING/libs/AqwApi.swc"
    fi
    if [ -d "$HAXE_UI_DIR" ]; then
        echo "=> [2/6] Compiling ModUI (aqw-haxe-ui)..."
        run_haxe_build "$HAXE_UI_DIR"
        cp "$HAXE_UI_DIR/bin/ModUI.swc" "$STAGING/libs/ModUI.swc"
    fi
fi

for required_swc in AqwApi.swc ModUI.swc; do
    if [ ! -f "$STAGING/libs/$required_swc" ]; then
        echo "ERROR: libs/$required_swc is missing." >&2
        if [ "$required_swc" = "ModUI.swc" ]; then
            echo "       aqw-haxe-ui did not produce it - run 'haxe build.hxml' in $HAXE_UI_DIR." >&2
        else
            echo "       aqw-haxe-api did not produce it - run 'haxe build.hxml' in $HAXE_API_DIR." >&2
        fi
        exit 1
    fi
done

if [ -f "$DIR/loader/libs/WorkerMain.swf" ]; then
    echo "=> [3/6] Staging WorkerMain.swf from loader/libs/WorkerMain.swf..."
    mkdir -p "$STAGING/gamefiles/embed"
    cp "$DIR/loader/libs/WorkerMain.swf" "$STAGING/gamefiles/embed/WorkerMain.swf"
else
    echo "ERROR: loader/libs/WorkerMain.swf is missing." >&2
    echo "       Obtain a prebuilt copy from a desktop release that bundles it and save it at" >&2
    echo "       loader/libs/WorkerMain.swf. Recompiling from loader/worker-src/ is not possible:" >&2
    echo "       SWFStripper.as needs com.codeazur.as3swf, which is neither vendored nor a SWC." >&2
    exit 1
fi

resolve_flex_tools
echo "=> Toolchain: $(basename "$AMXMLC"), java ${JAVA_HOME##*/}, flex tools in ${FLEX_TOOLS}"

inject_code_into_shell() {
    local is_desktop="$1" is_mobile="$2" label="$3"

    echo "   -> ${label}: compiling ${label}_code.swf (upstream AS3 + Haxe SWCs)..."
    "$AMXMLC" \
        +configname=air \
        -strict=false \
        -debug=true \
        -default-size 960 550 \
        -default-frame-rate 120 \
        -default-background-color 0x000000 \
        -define+=POCKET::IS_DESKTOP,"$is_desktop" \
        -define+=POCKET::IS_MOBILE,"$is_mobile" \
        -library-path+="$STAGING/libs" \
        -source-path+="$STAGING/src" \
        -output "$STAGING/${label}_code.swf" \
        "$STAGING/src/Pocket.as"

    echo "   -> ${label}: injecting mod code (artwork preserved)..."
    (
        cd "$STAGING"
        abcexport "${label}_code.swf"
        abcreplace "${label}.swf" 0 "${label}_code-0.abc"
        cp "${label}_code.swf" /tmp/inspect_${label}_code.swf; rm -f "${label}_code-0.abc" "${label}"-*.abc
    )
    cp "$STAGING/${label}.swf" "$BUILD/${label}.swf"
}

echo "=> [4/6] Injecting mod code into the pristine upstream shells..."
inject_code_into_shell true false Desktop
inject_code_into_shell false true Mobile

echo "=> [5/6] Assembling build/ ..."
rm -rf "$BUILD/assets" "$BUILD/icons" "$BUILD/gamefiles" "$BUILD/META-INF"
cp -r "$STAGING/assets" "$BUILD/assets"
cp -r "$STAGING/icons" "$BUILD/icons"
if [ -d "$STAGING/gamefiles" ]; then
    cp -r "$STAGING/gamefiles" "$BUILD/gamefiles"
fi

if [ -d "$CLIENT/META-INF" ]; then
    cp -r "$CLIENT/META-INF" "$BUILD/META-INF"
fi

write_descriptor "$CLIENT/Desktop-app.xml" "$BUILD/Desktop-app.xml"
sed "s|<renderMode>.*</renderMode>|<renderMode>gpu</renderMode>|" \
    "$BUILD/Desktop-app.xml" > "$BUILD/Desktop-app-gpu.xml"

echo "=> Build complete. Upstream loader/ untouched; artifacts in build/:"
ls -la "$BUILD/Desktop.swf" "$BUILD/Mobile.swf" 2>/dev/null || true
echo "=> Launch with: ./run.sh [--auto|--direct|--gpu]"
