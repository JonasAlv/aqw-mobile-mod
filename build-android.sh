#!/bin/bash
# build-android.sh - Build Android APK locally for testing
# Produces: AQWPocket-Mod-armv8-direct.apk (Direct render mode, armv8)

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

# Discover AIR_HOME dynamically if not already set
if [ -z "$AIR_HOME" ]; then
  for candidate in "$DIR/../../AIRSDK_Linux" "$DIR/../AIRSDK_Linux" "$HOME/AIRSDK_Linux" "$HOME/Music/AIRSDK_Linux"; do
    if [ -d "$candidate" ]; then
      export AIR_HOME="$candidate"
      break
    fi
  done
fi

export JAVA_HOME="${JAVA_HOME:-$HOME/.sdkman/candidates/java/current}"
export PATH=$AIR_HOME/bin:$JAVA_HOME/bin:$PATH

# Parse render modes: defaults to auto, gpu, and direct if none specified
# Example usage:
#   ./build-android.sh           # Builds auto, gpu, and direct
#   ./build-android.sh auto gpu  # Builds only auto and gpu
#   ./build-android.sh direct    # Builds only direct
TARGET_MODES=("$@")
if [ ${#TARGET_MODES[@]} -eq 0 ]; then
  TARGET_MODES=("auto" "gpu" "direct")
fi

KEYSTORE="aqwpocket_keystore_local.p12"

# ---- Step 0: Compile Haxe API & Mod UI ----
if [ "$SKIP_HAXE_API" != "1" ]; then
  if [ -d "$DIR/../aqw-haxe-api" ]; then
    echo "=> [0a/5] Compiling Haxe API (aqw-haxe-api)..."
    (cd "$DIR/../aqw-haxe-api" && (command -v haxe >/dev/null 2>&1 && haxe build.hxml || npx haxe build.hxml))
    mkdir -p "$DIR/loader/libs"
    cp "$DIR/../aqw-haxe-api/bin/AqwApi.swc" "$DIR/loader/libs/AqwApi.swc"
  fi
  if [ -d "$DIR/../aqw-haxe-ui" ]; then
    echo "=> [0b/5] Compiling Haxe UI (aqw-haxe-ui)..."
    (cd "$DIR/../aqw-haxe-ui" && (command -v haxe >/dev/null 2>&1 && haxe build.hxml || npx haxe build.hxml))
    mkdir -p "$DIR/loader/libs"
    cp "$DIR/../aqw-haxe-ui/bin/ModUI.swc" "$DIR/loader/libs/ModUI.swc"
  fi
fi

# ---- Step 1: Compile WorkerMain ----
echo "=> [1/5] Compiling WorkerMain.swf..."
cd loader
mkdir -p gamefiles/embed
$AIR_HOME/bin/amxmlc worker-src/WorkerMain.as \
  -source-path+=src \
  -source-path+=worker-src \
  -output gamefiles/embed/WorkerMain.swf \
  -swf-version=51
cd ..

# ---- Step 2: Compile Mobile_code.swf with Haxe SWCs ----
echo "=> [2/5] Compiling Mobile_code.swf with Haxe SWCs (AqwApi.swc & ModUI.swc)..."
$AIR_HOME/bin/amxmlc \
  +configname=air \
  -define+=POCKET::IS_DESKTOP,false \
  -define+=POCKET::IS_MOBILE,true \
  -library-path+=loader/libs \
  -source-path+=loader/worker-src \
  -source-path+=loader/src \
  -output loader/Mobile_code.swf \
  loader/src/Pocket.as

# ---- Step 3: Inject ABC into Mobile.swf ----
echo "=> [3/5] Injecting into Mobile.swf..."
cd loader
if [ ! -f Mobile_base.swf ]; then
  cp Mobile.swf Mobile_base.swf
fi
abcexport Mobile_code.swf
cp Mobile_base.swf Mobile.swf
abcreplace Mobile.swf 0 Mobile_code-0.abc
cd ..

# ---- Step 4: Generate local keystore (if missing) ----
echo "=> [4/5] Checking keystore..."
if [ ! -f "$KEYSTORE" ]; then
  echo "   Generating local test keystore..."
  $AIR_HOME/bin/adt -certificate -cn "AQWPocketLocal" 2048-RSA "$KEYSTORE" password
fi

# ---- Step 5: Packaging APK for requested render modes ----
echo "=> [5/5] Packaging APKs (${TARGET_MODES[*]})..."

BUILT_APKS=()
for MODE in "${TARGET_MODES[@]}"; do
  OUTPUT="AQWPocket-Mod-armv8-${MODE}.apk"
  TMP_APP_XML="loader/Mobile-app-${MODE}.xml"

  echo "   -> Packaging $OUTPUT (renderMode: $MODE)..."
  cp loader/Mobile-app.xml "$TMP_APP_XML"
  sed -i "s|<renderMode>.*</renderMode>|<renderMode>${MODE}</renderMode>|" "$TMP_APP_XML"

  $AIR_HOME/bin/adt -package \
    -target apk-captive-runtime \
    -arch armv8 \
    -storetype PKCS12 \
    -keystore "$KEYSTORE" \
    -storepass password \
    "$OUTPUT" \
    "$TMP_APP_XML" \
    -C loader \
      Mobile.swf \
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

  if [ "$MODE" = "auto" ]; then
    cp -f "$OUTPUT" "AQWPocket-Mod-armv8.apk"
  fi

  BUILT_APKS+=("$OUTPUT ($(du -sh "$OUTPUT" | cut -f1))")
done

# Cleanup temp files
rm -f loader/Mobile-app-*.xml loader/Mobile_code.swf loader/Mobile_code-0.abc loader/Mobile-*.abc loader/Mobile_base-*.abc

echo ""
echo "=> Done! Built Android APKs:"
for APK_INFO in "${BUILT_APKS[@]}"; do
  echo "   • $APK_INFO"
done
if [ -f "AQWPocket-Mod-armv8.apk" ]; then
  echo "   • AQWPocket-Mod-armv8.apk ($(du -sh AQWPocket-Mod-armv8.apk | cut -f1)) [alias for auto]"
fi
echo ""
echo "   Install on device with: adb install -r <apk-file>"

# Prevent patched SWFs from showing up as modified in git
git -C "$DIR" update-index --skip-worktree loader/Mobile.swf loader/Desktop.swf 2>/dev/null || true
