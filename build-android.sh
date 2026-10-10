#!/bin/bash
# build-android.sh - Build Android APKs locally using isolated build sandbox
# Supports ARMv8, ARMv7, or both (default)
# Output: android_builds/aqwmod-${UPSTREAM_VERSION}-${BUILD_DATE}-${ARCH}.apk

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"
# shellcheck source=lib.sh
. "$DIR/lib.sh"

resolve_air_env

BUILD="$DIR/build"
STAGING="$BUILD/staging"
OUTPUT_DIR="${OUTPUT_DIR:-$DIR/../android_builds}"

echo "=> Cleaning build sandbox and output directories..."
# Only this script's own artifacts. `rm -rf "$BUILD"` would also destroy the cached upstream APK and
# the synced gamefiles, forcing a full re-download on every run.
rm -rf "$STAGING"
rm -f "$BUILD/Mobile.swf"
rm -f "$BUILD"/Mobile-app-*.xml
mkdir -p "$BUILD"
mkdir -p "$STAGING"
mkdir -p "$OUTPUT_DIR"
rm -rf "${OUTPUT_DIR:?}"/*

# Ensure staging sandbox is cleaned up when script exits
trap 'rm -rf "$STAGING"' EXIT

# Determine target architectures (default: both armv8 and armv7)
if [ -n "${ARCH:-}" ] && [ "$ARCH" != "all" ]; then
    ARCHS=("$ARCH")
else
    ARCHS=("armv8" "armv7")
fi

# Parse render modes: defaults to auto, gpu, and direct if none specified
TARGET_MODES=("$@")
if [ ${#TARGET_MODES[@]} -eq 0 ]; then
    TARGET_MODES=("auto" "gpu" "direct")
fi

KEYSTORE="${KEYSTORE:-$DIR/aqwpocket_keystore_local.p12}"
HAXE_API_DIR="${HAXE_API_DIR:-$DIR/../aqw-haxe-api}"
HAXE_UI_DIR="${HAXE_UI_DIR:-$DIR/../aqw-haxe-ui}"

# The whole mod is these two files: ModBootstrap.as, and one ModBootstrap.init(this)
# line in Pocket.as. Everything else under loader/ is upstream's. Fail loudly if a
# future upstream sync dropped the seam, rather than silently shipping a vanilla client.
if [ ! -f "$DIR/loader/src/ModBootstrap.as" ]; then
    echo "ERROR: loader/src/ModBootstrap.as is missing - the mod seam was lost." >&2
    exit 1
fi
if ! grep -q "ModBootstrap.init(this)" "$DIR/loader/src/Pocket.as" 2>/dev/null; then
    echo "ERROR: loader/src/Pocket.as no longer calls ModBootstrap.init(this)." >&2
    echo "       Re-add it after '_SINGLETON = this;' (keep the file's CRLF endings)." >&2
    exit 1
fi

# ---- Step 0: Fetch the latest upstream gamefiles ----
# Delegates to sync-gamefiles.sh rather than re-implementing it. The inline version this replaced had
# no SHA-256 verification, no draft/prerelease guard, no armv7 fallback and no URL validation, and
# ended in `|| true` everywhere - so a failed download still reported success.
echo "=> [0/5] Syncing upstream gamefiles (anthony-hyo/aqw-mobile)..."
if [ "${SKIP_SYNC:-0}" = "1" ]; then
    echo "   SKIP_SYNC=1 - using cached gamefiles."
elif ! "$DIR/sync-gamefiles.sh"; then
    echo "ERROR: Could not sync upstream gamefiles." >&2
    echo "       Re-run with SKIP_SYNC=1 to build offline against the cached copies." >&2
    exit 1
fi

# ---- Step 1: Copy pristine files into sandbox ----
echo "=> [1/5] Copying repository files to sandbox ($STAGING)..."
mkdir -p "$STAGING/libs"
cp -r "$DIR/loader/src" "$STAGING/src"
cp -r "$DIR/loader/worker-src" "$STAGING/worker-src"
GAMEFILES_SRC="$BUILD/gamefiles-upstream"
[ -d "$GAMEFILES_SRC" ] || GAMEFILES_SRC="$DIR/loader/gamefiles"
mkdir -p "$STAGING/gamefiles"
if [ -d "$GAMEFILES_SRC" ]; then
    cp -r "$GAMEFILES_SRC/"* "$STAGING/gamefiles/"
else
    echo "   Warning: no gamefiles found; the APK will ship without them." >&2
fi
cp -r "$DIR/loader/assets" "$STAGING/assets"
cp -r "$DIR/loader/icons" "$STAGING/icons"
cp "$DIR/loader/Mobile-app.xml" "$STAGING/Mobile-app.xml"
cp "$DIR/loader/Mobile.swf" "$STAGING/Mobile.swf"
if [ -d "$DIR/loader/libs" ]; then
    cp -r "$DIR/loader/libs/"* "$STAGING/libs/" 2>/dev/null || true
fi

# ---- Step 2: Compile Haxe API & UI into sandbox ----
if [ "${SKIP_HAXE_API:-}" != "1" ]; then
    if [ -d "$HAXE_API_DIR" ]; then
        echo "=> [2a/5] Compiling Haxe API (aqw-haxe-api)..."
        run_haxe_build "$HAXE_API_DIR"
        cp "$HAXE_API_DIR/bin/AqwApi.swc" "$STAGING/libs/AqwApi.swc"
    fi
    if [ -d "$HAXE_UI_DIR" ]; then
        echo "=> [2b/5] Compiling Haxe UI (aqw-haxe-ui)..."
        run_haxe_build "$HAXE_UI_DIR"
        cp "$HAXE_UI_DIR/bin/ModUI.swc" "$STAGING/libs/ModUI.swc"
    fi
fi

# ---- Step 3: WorkerMain.swf ----
# WorkerMain.as is a background worker that strips SWF animation/filters. It is NOT shipped in
# upstream release assets, and recompiling it from loader/worker-src/ fails: SWFStripper.as
# imports com.codeazur.as3swf, which is neither vendored in the repo nor available as a SWC.
#
# The working prebuilt copy lives in the desktop release zip at
# gamefiles/embed/WorkerMain.swf (148477 bytes). sync-gamefiles.sh does not pull it because the
# current upstream release assets do not bundle it, so we vendor a copy at
# loader/libs/WorkerMain.swf and stage it from there. loader/worker-src/ is kept for reference
# but is NOT compiled.
#
# SWFWorkerClient embeds it at compile time via [Embed(source="../../gamefiles/embed/WorkerMain.swf")],
# which resolves relative to Pocket.as's source-path ($STAGING/src/), i.e. exactly that path — so
# the Embed class is emitted into the injected ABC and the runtime does not throw
# "Variable SWFWorkerClient_WorkerSWF is not defined".
if [ -f "$DIR/loader/libs/WorkerMain.swf" ]; then
    echo "=> [3/5] Staging WorkerMain.swf from loader/libs/WorkerMain.swf..."
    mkdir -p "$STAGING/gamefiles/embed"
    cp "$DIR/loader/libs/WorkerMain.swf" "$STAGING/gamefiles/embed/WorkerMain.swf"
else
    echo "ERROR: loader/libs/WorkerMain.swf is missing." >&2
    echo "       Obtain a prebuilt copy from a desktop release that bundles it and save it at" >&2
    echo "       loader/libs/WorkerMain.swf. Recompiling from loader/worker-src/ is not possible:" >&2
    echo "       SWFStripper.as needs com.codeazur.as3swf, which is neither vendored nor a SWC." >&2
    exit 1
fi

# ---- Step 4: Compile Mobile_code.swf & Inject into Mobile.swf inside sandbox ----
echo "=> [4/5] Compiling Mobile_code.swf with Haxe SWCs..."
"$AMXMLC" \
    +configname=air \
    -strict=false \
    -define+=POCKET::IS_DESKTOP,false \
    -define+=POCKET::IS_MOBILE,true \
    -library-path+="$STAGING/libs" \
    -source-path+="$STAGING/src" \
    -output "$STAGING/Mobile_code.swf" \
    "$STAGING/src/Pocket.as"

resolve_flex_tools

echo "   Injecting into Mobile.swf..."
cd "$STAGING"
abcexport Mobile_code.swf
abcreplace Mobile.swf 0 Mobile_code-0.abc
rm -f Mobile_code.swf Mobile_code-0.abc Mobile-*.abc
cd "$DIR"

# Copy injected Mobile.swf to build/
cp "$STAGING/Mobile.swf" "$BUILD/Mobile.swf"

# ---- Step 5: Keystore & Packaging ----
echo "=> [5/5] Checking keystore..."
if [ ! -f "$KEYSTORE" ]; then
    echo "   Generating local test keystore..."
    "$ADT" -certificate -cn "AQWPocketLocal" 2048-RSA "$KEYSTORE" password
fi

# Resolve upstream version (e.g. v3.6.0)
if [ -z "${UPSTREAM_VERSION:-}" ]; then
    if [ -f "$BUILD/upstream-apk-cache/latest.tag" ]; then
        UPSTREAM_VERSION="$(cat "$BUILD/upstream-apk-cache/latest.tag" | tr -d '[:space:]')"
    elif [ -f "$DIR/build/upstream-apk-cache/latest.tag" ]; then
        UPSTREAM_VERSION="$(cat "$DIR/build/upstream-apk-cache/latest.tag" | tr -d '[:space:]')"
    fi
fi
if [ -z "${UPSTREAM_VERSION:-}" ]; then
    UPSTREAM_VERSION="$(grep -oPm1 "(?<=<versionNumber>)[^<]+" "$DIR/loader/Mobile-app.xml" 2>/dev/null || echo "3.6.0")"
fi

# Date in dd-mm-yy format (e.g. 05-10-26)
BUILD_DATE="${BUILD_DATE:-$(date +'%d-%m-%y')}"

echo "=> Packaging APKs (${TARGET_MODES[*]}) for architectures: ${ARCHS[*]} (version: $UPSTREAM_VERSION, date: $BUILD_DATE)..."

BUILT_APKS=()
for CURRENT_ARCH in "${ARCHS[@]}"; do
    for MODE in "${TARGET_MODES[@]}"; do
        if [ "${#TARGET_MODES[@]}" -eq 1 ]; then
            OUTPUT_FILE="aqwmod-${UPSTREAM_VERSION}-${BUILD_DATE}-${CURRENT_ARCH}.apk"
        else
            if [ "$MODE" = "auto" ]; then
                OUTPUT_FILE="aqwmod-${UPSTREAM_VERSION}-${BUILD_DATE}-${CURRENT_ARCH}.apk"
            else
                OUTPUT_FILE="aqwmod-${UPSTREAM_VERSION}-${BUILD_DATE}-${CURRENT_ARCH}-${MODE}.apk"
            fi
        fi
        OUTPUT_PATH="$OUTPUT_DIR/$OUTPUT_FILE"
        TMP_APP_XML="$BUILD/Mobile-app-${CURRENT_ARCH}-${MODE}.xml"

        echo "   -> Packaging $OUTPUT_FILE (renderMode: $MODE, arch: $CURRENT_ARCH)..."
        cp "$STAGING/Mobile-app.xml" "$TMP_APP_XML"
        sed -i "s|<renderMode>.*</renderMode>|<renderMode>${MODE}</renderMode>|" "$TMP_APP_XML"

        "$ADT" -package \
            -target apk-captive-runtime \
            -arch "$CURRENT_ARCH" \
            -storetype PKCS12 \
            -keystore "$KEYSTORE" \
            -storepass password \
            "$OUTPUT_PATH" \
            "$TMP_APP_XML" \
            -C "$BUILD" Mobile.swf \
            -C "$STAGING" \
                assets \
                icons/icon-36x36.png \
                icons/icon-48x48.png \
                icons/icon-72x72.png \
                icons/icon-96x96.png \
                icons/icon-144x144.png \
                icons/icon-192x192.png \
                gamefiles/game.swf \
                gamefiles/world-map.swf \
                gamefiles/book-of-lore.swf \
                gamefiles/character-select.swf

        rm -f "$TMP_APP_XML"

        FILE_SIZE=$(du -sh "$OUTPUT_PATH" | cut -f1)
        BUILT_APKS+=("$OUTPUT_FILE ($FILE_SIZE)")
    done
done

echo ""
echo "=> Done! Built Android APKs in ${OUTPUT_DIR:-}:"
for APK_INFO in "${BUILT_APKS[@]}"; do
    echo "   • $APK_INFO"
done
echo ""
echo "   Install on device with: adb install -r ${OUTPUT_DIR:-}/<apk-file>"
