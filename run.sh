#!/bin/bash
set -e

# Always build desktop SWF by default unless --no-build is specified
if [ "$1" != "--no-build" ]; then
    ./build.sh
fi

echo "=> Launching ADL (Windows AIR Debug Launcher) via Wine..."
echo "   (Using Desktop-app-local.xml - Discord RPC disabled for local testing)"
cd loader

wine /home/me/Music/AIRSDK_Windows/bin/adl.exe -profile extendedDesktop Desktop-app-local.xml

echo "=> ADL closed."
