#!/bin/bash
set -e

export AIR_HOME=/home/me/Music/AIRSDK_Linux
export JAVA_HOME=$HOME/.sdkman/candidates/java/current
export PATH=$AIR_HOME/bin:$JAVA_HOME/bin:$PATH

echo "Compiling WorkerMain.swf"
cd /home/me/Music/aqw-mobile/loader
mkdir -p gamefiles/embed
$AIR_HOME/bin/amxmlc worker-src/WorkerMain.as  -source-path+=../../aqw-api-enhanced/src -source-path+=src -source-path+=worker-src -output gamefiles/embed/WorkerMain.swf -swf-version=18

if [ ! -f Desktop_base.swf ]; then
    cp Desktop.swf Desktop_base.swf
fi
cd ..

echo "Compiling Desktop_code.swf..."
$AIR_HOME/bin/amxmlc \
  +configname=air \
  -define+=POCKET::IS_DESKTOP,true \
  -define+=POCKET::IS_MOBILE,false \
  -library-path+=loader/libs \
  -source-path+=loader/worker-src \
   \
  -source-path+=loader/src \
  -source-path+=../aqw-api-enhanced/src \
  -output loader/Desktop_code.swf \
  loader/src/Pocket.as

echo "Extracting ABC..."
cd loader
abcexport Desktop_code.swf

echo "Injecting into Desktop.swf..."
cp Desktop_base.swf Desktop.swf
abcreplace Desktop.swf 0 Desktop_code-0.abc

mkdir -p assets
cp ../../aqw-api-enhanced/assets/skills_custom.json assets/skills.json

echo "Launching ADL (Windows AIR Debug Launcher) via Wine..."
wine /home/me/Music/AIRSDK_Windows/bin/adl.exe -profile extendedDesktop Desktop-app.xml -extdir libs
