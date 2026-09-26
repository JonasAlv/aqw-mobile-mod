#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Always build desktop SWF by default unless --no-build is specified
if [ "$1" != "--no-build" ]; then
    "$DIR/build.sh"
fi

# Ensure bot.log exists and is symlinked for live tailing
WINE_LOG_DIR="$HOME/.wine/drive_c/users/me/AppData/Roaming/com.aqw.pocket/Local Store"
if [ -d "$HOME/.wine" ]; then
    mkdir -p "$WINE_LOG_DIR"
    touch "$WINE_LOG_DIR/bot.log"
    ln -sf "$WINE_LOG_DIR/bot.log" "$DIR/loader/bot.log"
    if [ -d "$DIR/.." ]; then
        ln -sf "$WINE_LOG_DIR/bot.log" "$DIR/../bot.log"
    fi
fi

echo "=> Launching ADL (Windows AIR Debug Launcher) via Wine..."
echo "   (Using Desktop-app-local.xml - Discord RPC disabled for local testing)"
cd "$DIR/loader"

if [ -z "$AIRSDK_WINDOWS" ]; then
    for candidate in "$DIR/../../AIRSDK_Windows" "$DIR/../AIRSDK_Windows" "$HOME/AIRSDK_Windows" "$HOME/Music/AIRSDK_Windows"; do
        if [ -d "$candidate" ]; then
            AIRSDK_WINDOWS="$candidate"
            break
        fi
    done
fi

wine "$AIRSDK_WINDOWS/bin/adl.exe" -profile extendedDesktop Desktop-app-local.xml

echo "=> ADL closed."
