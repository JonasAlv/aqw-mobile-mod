#!/bin/bash

# Optional: Build before running if requested
if [ "$1" == "--build" ] || [ "$1" == "-b" ]; then
    ./build.sh
    if [ $? -ne 0 ]; then
        echo "Build failed! Aborting run."
        exit 1
    fi
fi

echo "=> Launching ADL (Windows AIR Debug Launcher) via Wine..."
echo "   (Using Desktop-app-local.xml - Discord RPC disabled for local testing)"
cd loader

# Use the local app descriptor which has Discord RPC stripped out.
# ADL on Wine crashes immediately if a native extension is declared but not loadable.
wine /home/me/Music/AIRSDK_Windows/bin/adl.exe -profile extendedDesktop Desktop-app-local.xml

echo "=> ADL closed."
