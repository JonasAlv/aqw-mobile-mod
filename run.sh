#!/bin/bash
set -e

# Always build desktop SWF by default unless --no-build is specified
if [ "$1" != "--no-build" ]; then
    ./build.sh
fi

echo "=> Launching ADL (Windows AIR Debug Launcher) via Wine..."
echo "   (Using Desktop-app-local.xml - Discord RPC disabled for local testing)"
cd loader

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "$AIRSDK_WINDOWS" ]; then
    for candidate in "$DIR/../../AIRSDK_Windows" "$DIR/../AIRSDK_Windows" "$HOME/AIRSDK_Windows" "/home/me/Music/AIRSDK_Windows"; do
        if [ -d "$candidate" ]; then
            AIRSDK_WINDOWS="$candidate"
            break
        fi
    done
fi

wine "$AIRSDK_WINDOWS/bin/adl.exe" -profile extendedDesktop Desktop-app-local.xml

echo "=> ADL closed."
