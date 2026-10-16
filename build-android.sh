#!/bin/bash
# build-android.sh - Build Android APKs locally using isolated build sandbox
# Builds separate Android APKs for selected architectures (armv7 and/or armv8).
# Set ANDROID_ARCHS="armv7 armv8" (default) or a single architecture.
# Output: android_builds/AQWMod-${UPSTREAM_VERSION}-${BUILD_DATE}-${ARCH}-${MODE}.apk

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"
# shellcheck source=lib.sh
. "$DIR/lib.sh"

# Optional machine-local paths for the API/UI checkouts; never committed.
if [ -f "$DIR/local-repos.sh" ]; then
    . "$DIR/local-repos.sh"
fi

resolve_air_env

BUILD="$DIR/build"
STAGING="$BUILD/staging"
OUTPUT_DIR="${OUTPUT_DIR:-$DIR/../android_builds}"

echo "=> Cleaning build sandbox and output directories..."

rm -rf "$STAGING"
rm -f "$BUILD/Mobile.swf"
rm -f "$BUILD"/Mobile-app-*.xml
mkdir -p "$BUILD"
mkdir -p "$STAGING"
mkdir -p "$OUTPUT_DIR"

trap 'rm -rf "$STAGING"; rm -f "$BUILD"/Mobile-app-*.xml' EXIT

TARGET_MODES=("$@")
if [ ${#TARGET_MODES[@]} -eq 0 ]; then
    TARGET_MODES=("cpu" "direct" "gpu")
fi

for mode in "${TARGET_MODES[@]}"; do
    case "$mode" in
        cpu|direct|gpu) ;;
        *)
            echo "ERROR: Unknown render mode '$mode'. Choose cpu, direct, or gpu." >&2
            exit 2
            ;;
    esac
done

ANDROID_ARCHS="${ANDROID_ARCHS:-armv7 armv8}"
read -r -a TARGET_ARCHS <<< "$ANDROID_ARCHS"
if [ ${#TARGET_ARCHS[@]} -eq 0 ]; then
    echo "ERROR: No Android architectures selected. Set ANDROID_ARCHS to armv7, armv8, or both." >&2
    exit 2
fi
SEEN_ARCHS=()
for arch in "${TARGET_ARCHS[@]}"; do
    case "$arch" in
        armv7|armv8) ;;
        *)
            echo "ERROR: Unknown Android architecture '$arch'. Choose armv7 and/or armv8." >&2
            exit 2
            ;;
    esac
    if [[ " ${SEEN_ARCHS[*]} " == *" $arch "* ]]; then
        echo "ERROR: Android architecture '$arch' was selected more than once." >&2
        exit 2
    fi
    SEEN_ARCHS+=("$arch")
done

KEYSTORE="${KEYSTORE:-$DIR/aqwpocket_keystore_local.p12}"
HAXE_API_DIR="${HAXE_API_DIR:-../aqw-haxe-api}"
HAXE_UI_DIR="${HAXE_UI_DIR:-../aqw-haxe-ui}"
HAXE_API_DIR="$(resolve_repo_dir "$DIR" "$HAXE_API_DIR")"
HAXE_UI_DIR="$(resolve_repo_dir "$DIR" "$HAXE_UI_DIR")"

for repo_spec in "aqw-haxe-api:$HAXE_API_DIR:bin/AqwApi.swc" "aqw-haxe-ui:$HAXE_UI_DIR:bin/ModUI.swc"; do
    repo_name="${repo_spec%%:*}"
    repo_rest="${repo_spec#*:}"
    repo_path="${repo_rest%:*}"
    if [ ! -d "$repo_path" ] || [ ! -f "$repo_path/build.hxml" ]; then
        echo "ERROR: $repo_name checkout or build.hxml not found at $repo_path." >&2
        echo "       Set HAXE_API_DIR/HAXE_UI_DIR in local-repos.sh to your actual checkout paths." >&2
        exit 1
    fi
    printf "=> Source %s: %s" "$repo_name" "$repo_path"
    if git -C "$repo_path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        printf " [branch=%s commit=%s]" "$(git -C "$repo_path" branch --show-current 2>/dev/null || echo detached)" "$(git -C "$repo_path" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    fi
    printf "\\n"
done

if [ ! -f "$DIR/loader/src/ModBootstrap.as" ]; then
    echo "ERROR: loader/src/ModBootstrap.as is missing - the mod seam was lost." >&2
    exit 1
fi
if ! grep -q "ModBootstrap.init(this)" "$DIR/loader/src/Pocket.as" 2>/dev/null; then
    echo "ERROR: loader/src/Pocket.as no longer calls ModBootstrap.init(this)." >&2
    echo "       Re-add it after '_SINGLETON = this;' (keep the file's CRLF endings)." >&2
    exit 1
fi

echo "=> [0/5] Syncing upstream gamefiles (anthony-hyo/aqw-mobile)..."
if [ "${SKIP_SYNC:-0}" = "1" ]; then
    echo "   SKIP_SYNC=1 - using cached gamefiles."
elif ! "$DIR/sync-gamefiles.sh"; then
    echo "ERROR: Could not sync upstream gamefiles." >&2
    echo "       Re-run with SKIP_SYNC=1 to build offline against the cached copies." >&2
    exit 1
fi

echo "=> [1/5] Copying repository files to sandbox ($STAGING)..."
mkdir -p "$STAGING/libs"
cp -r "$DIR/loader/src" "$STAGING/src"
cp -r "$DIR/loader/worker-src" "$STAGING/worker-src"
GAMEFILES_SRC="$BUILD/gamefiles-upstream"
[ -d "$GAMEFILES_SRC" ] || GAMEFILES_SRC="$DIR/loader/gamefiles"
mkdir -p "$STAGING/gamefiles"
if [ -d "$GAMEFILES_SRC" ]; then
    cp -r "$GAMEFILES_SRC/." "$STAGING/gamefiles/"
else
    echo "   Warning: no gamefiles found; the APK will ship without them." >&2
fi
rm -f "$STAGING/gamefiles/book-of-lore.swf" "$STAGING/gamefiles/character-select.swf"
rm -rf "$STAGING/gamefiles/embed"



mkdir -p "$STAGING/assets"
if [ -d "$DIR/loader/assets" ]; then
    cp -r "$DIR/loader/assets/." "$STAGING/assets/"
fi

cp -r "$DIR/loader/icons" "$STAGING/icons"
cp "$DIR/loader/Mobile-app.xml" "$STAGING/Mobile-app.xml"
cp "$DIR/loader/Mobile.swf" "$STAGING/Mobile.swf"
if [ -d "$DIR/loader/libs" ]; then
    cp -r "$DIR/loader/libs/"* "$STAGING/libs/" 2>/dev/null || true
fi

if [ "${SKIP_HAXE_API:-}" != "1" ]; then
    echo "=> [2a/5] Compiling Haxe API from $HAXE_API_DIR..."
    rm -f "$HAXE_API_DIR/bin/AqwApi.swc"
    run_haxe_build "$HAXE_API_DIR"
    if [ ! -s "$HAXE_API_DIR/bin/AqwApi.swc" ]; then
        echo "ERROR: Haxe API build did not produce bin/AqwApi.swc." >&2
        exit 1
    fi
    cp "$HAXE_API_DIR/bin/AqwApi.swc" "$STAGING/libs/AqwApi.swc"
    echo "   API SWC SHA-256: $(sha256sum "$STAGING/libs/AqwApi.swc" | awk '{print $1}')"

    echo "=> [2b/5] Compiling Haxe UI from $HAXE_UI_DIR..."
    rm -f "$HAXE_UI_DIR/bin/ModUI.swc"
    run_haxe_ui_build "$HAXE_UI_DIR" "$HAXE_API_DIR"
    if [ ! -s "$HAXE_UI_DIR/bin/ModUI.swc" ]; then
        echo "ERROR: Haxe UI build did not produce bin/ModUI.swc." >&2
        exit 1
    fi
    cp "$HAXE_UI_DIR/bin/ModUI.swc" "$STAGING/libs/ModUI.swc"
    echo "   UI SWC SHA-256: $(sha256sum "$STAGING/libs/ModUI.swc" | awk '{print $1}')"
    echo "=> Using freshly built UI library: $STAGING/libs/ModUI.swc"
else
    echo "WARNING: SKIP_HAXE_API=1; using prebuilt SWCs copied from loader/libs/ (not compiling Haxe sources)." >&2
fi

for required_swc in AqwApi.swc ModUI.swc; do
    if [ ! -f "$STAGING/libs/$required_swc" ]; then
        echo "ERROR: Required library '$required_swc' is missing from $STAGING/libs." >&2
        echo "       Build the matching Haxe project or place its prebuilt SWC in loader/libs/." >&2
        exit 1
    fi
done

if [ -f "$DIR/loader/libs/WorkerMain.swf" ]; then
    echo "=> [3/5] WorkerMain.swf verified in loader/libs/WorkerMain.swf (embedded at compile time)..."
    cp "$DIR/loader/libs/WorkerMain.swf" "$STAGING/libs/WorkerMain.swf"
else
    echo "ERROR: loader/libs/WorkerMain.swf is missing." >&2
    echo "       Obtain a prebuilt copy from a desktop release that bundles it and save it at" >&2
    echo "       loader/libs/WorkerMain.swf. Recompiling from loader/worker-src/ is not possible:" >&2
    echo "       SWFStripper.as needs com.codeazur.as3swf, which is neither vendored nor a SWC." >&2
    exit 1
fi

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

cp "$STAGING/Mobile.swf" "$BUILD/Mobile.swf"

echo "=> [5/5] Checking keystore..."
if [ ! -f "$KEYSTORE" ]; then
    echo "   Generating local test keystore..."
    "$ADT" -certificate -cn "AQWPocketLocal" 2048-RSA "$KEYSTORE" password
fi

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

BUILD_DATE="${BUILD_DATE:-$(date +'%d-%m-%y')}"

echo "=> Packaging Android APKs (architectures: ${TARGET_ARCHS[*]}; render modes: ${TARGET_MODES[*]}) (version: $UPSTREAM_VERSION, date: $BUILD_DATE)..."

BUILT_APKS=()
for ARCH in "${TARGET_ARCHS[@]}"; do
    case "$ARCH" in
        armv7) EXPECTED_ABI="armeabi-v7a" ;;
        armv8) EXPECTED_ABI="arm64-v8a" ;;
    esac
    for MODE in "${TARGET_MODES[@]}"; do
        OUTPUT_FILE="AQWMod-${UPSTREAM_VERSION}-${BUILD_DATE}-${ARCH}-${MODE}.apk"
        OUTPUT_PATH="$OUTPUT_DIR/$OUTPUT_FILE"
        TMP_APP_XML="$BUILD/Mobile-app-${ARCH}-${MODE}.xml"

        rm -f "$OUTPUT_PATH"
        echo "   -> Packaging $OUTPUT_FILE (renderMode: $MODE, arch: $ARCH)..."
        cp "$STAGING/Mobile-app.xml" "$TMP_APP_XML"
        sed -i "s|<renderMode>.*</renderMode>|<renderMode>${MODE}</renderMode>|" "$TMP_APP_XML"

        "$ADT" -package \
            -arch "$ARCH" \
            -target apk-captive-runtime \
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
                gamefiles

        rm -f "$TMP_APP_XML"

        echo "   -> Verifying $EXPECTED_ABI native libraries are present..."
        python3 - "$OUTPUT_PATH" "$EXPECTED_ABI" <<'PY'
import sys, zipfile
apk, abi = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(apk) as z:
    names = z.namelist()
if not any(n.startswith(f"lib/{abi}/") and n.endswith(".so") for n in names):
    print(f"Missing native library ABI: {abi}", file=sys.stderr)
    sys.exit(1)
print(f"Verified native libraries for {abi}")
PY

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
