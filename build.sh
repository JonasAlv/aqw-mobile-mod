#!/bin/bash
set -e

export AIR_HOME=/home/me/Music/AIRSDK_Linux
export JAVA_HOME=$HOME/.sdkman/candidates/java/current
export PATH=$AIR_HOME/bin:$JAVA_HOME/bin:$PATH

echo "=> [0/3] Compiling Haxe API (aqw-haxe-api)..."
if [ -d "../aqw-haxe-api" ]; then
    if command -v haxe >/dev/null 2>&1; then
        (cd ../aqw-haxe-api && haxe build.hxml)
    else
        (cd ../aqw-haxe-api && npx haxe build.hxml)
    fi
    mkdir -p loader/libs
    cp ../aqw-haxe-api/bin/AqwApi.swc loader/libs/AqwApi.swc
fi

echo "=> [1/3] Compiling WorkerMain.swf..."
cd loader
mkdir -p gamefiles/embed
$AIR_HOME/bin/amxmlc worker-src/WorkerMain.as -source-path+=src -source-path+=worker-src -output gamefiles/embed/WorkerMain.swf -swf-version=18

if [ ! -f Desktop_base.swf ]; then
    cp Desktop.swf Desktop_base.swf
fi
cd ..

echo "=> [2/3] Compiling Desktop_code.swf with Haxe AqwApi.swc..."
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
rm -f Desktop_code.swf Desktop_code-0.abc
cd ..

echo "=> Build Complete!"
