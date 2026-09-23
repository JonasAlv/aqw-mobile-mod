#!/bin/bash
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

if [ "$SKIP_HAXE_API" != "1" ]; then
    if [ -d "$DIR/../aqw-haxe-api" ]; then
        echo "=> [0a/3] Compiling Haxe API (aqw-haxe-api)..."
        (cd "$DIR/../aqw-haxe-api" && (command -v haxe >/dev/null 2>&1 && haxe build.hxml || npx haxe build.hxml))
        mkdir -p "$DIR/loader/libs"
        cp "$DIR/../aqw-haxe-api/bin/AqwApi.swc" "$DIR/loader/libs/AqwApi.swc"
    fi
    if [ -d "$DIR/../aqw-haxe-ui" ]; then
        echo "=> [0b/3] Compiling Haxe UI (aqw-haxe-ui)..."
        (cd "$DIR/../aqw-haxe-ui" && (command -v haxe >/dev/null 2>&1 && haxe build.hxml || npx haxe build.hxml))
        mkdir -p "$DIR/loader/libs"
        cp "$DIR/../aqw-haxe-ui/bin/ModUI.swc" "$DIR/loader/libs/ModUI.swc"
    fi
fi

echo "=> [1/3] Compiling WorkerMain.swf..."
cd loader
mkdir -p gamefiles/embed
$AIR_HOME/bin/amxmlc worker-src/WorkerMain.as -source-path+=src -source-path+=worker-src -output gamefiles/embed/WorkerMain.swf -swf-version=51

if [ ! -f Desktop_base.swf ]; then
    cp Desktop.swf Desktop_base.swf
fi
cd ..

echo "=> [2/3] Compiling Desktop_code.swf with Haxe SWCs (AqwApi.swc & ModUI.swc)..."
$AIR_HOME/bin/amxmlc \
  +configname=air \
  -debug=true \
  -define+=POCKET::IS_DESKTOP,true \
  -define+=POCKET::IS_MOBILE,false \
  -library-path+=loader/libs \
  -source-path+=loader/worker-src \
  -source-path+=loader/src \
  -output loader/Desktop_code.swf \
  loader/src/Pocket.as


echo "=> [3/3] Injecting into Desktop.swf..."
cd loader
abcexport Desktop_code.swf
cp Desktop_base.swf Desktop.swf
abcreplace Desktop.swf 0 Desktop_code-0.abc
rm -f Desktop_code.swf Desktop_code-0.abc Desktop-*.abc Desktop_base-*.abc
cd ..

echo "=> Build Complete!"

# Prevent patched SWFs from showing up as modified in git
git -C "$DIR" update-index --skip-worktree loader/Desktop.swf loader/Mobile.swf 2>/dev/null || true
