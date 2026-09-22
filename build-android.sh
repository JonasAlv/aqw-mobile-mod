#!/bin/bash
# build-android.sh - Build Android APK locally for testing
# Produces: AQWPocket-Mod-armv8-gpu.apk (GPU render mode, armv8)

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Discover AIR_HOME dynamically if not already set
if [ -z "$AIR_HOME" ]; then
  for candidate in "$DIR/../../AIRSDK_Linux" "$DIR/../AIRSDK_Linux" "$HOME/AIRSDK_Linux" "/home/me/Music/AIRSDK_Linux"; do
    if [ -d "$candidate" ]; then
      export AIR_HOME="$candidate"
      break
    fi
  done
fi

export JAVA_HOME="${JAVA_HOME:-$HOME/.sdkman/candidates/java/current}"
export PATH=$AIR_HOME/bin:$JAVA_HOME/bin:$PATH

KEYSTORE="aqwpocket_keystore_local.p12"
OUTPUT="AQWPocket-Mod-armv8-gpu.apk"

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
  -swf-version=18
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

# ---- Step 5: Set GPU render mode in app descriptor ----
echo "=> [5/5] Packaging APK (armv8, gpu)..."
cp loader/Mobile-app.xml loader/Mobile-app-gpu.xml
sed -i "s|<renderMode>.*</renderMode>|<renderMode>gpu</renderMode>|" loader/Mobile-app-gpu.xml

$AIR_HOME/bin/adt -package \
  -target apk-captive-runtime \
  -arch armv8 \
  -storetype PKCS12 \
  -keystore "$KEYSTORE" \
  -storepass password \
  "$OUTPUT" \
  loader/Mobile-app-gpu.xml \
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

# Cleanup temp files
rm -f loader/Mobile-app-gpu.xml loader/Mobile_code.swf loader/Mobile_code-0.abc loader/Mobile-*.abc loader/Mobile_base-*.abc

echo ""
echo "=> Done! Output: $OUTPUT ($(du -sh $OUTPUT | cut -f1))"
echo "   Install on device with: adb install -r $OUTPUT"
