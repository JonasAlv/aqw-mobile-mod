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
cd loader

# Run ADL, filtering out the known Discord RPC extension error that causes wine to complain
wine /home/me/Music/AIRSDK_Windows/bin/adl.exe -profile extendedDesktop Desktop-app.xml -extdir libs 2>&1 | grep -v "fi.joniaromaa.adobeair.discordrpc"

echo "=> ADL closed."
