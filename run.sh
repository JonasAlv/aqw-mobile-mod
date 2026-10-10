#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$DIR/lib.sh"

CLIENT="$DIR/loader"
BUILD="$DIR/build"
BUILD_REQUESTED=0
RENDER_MODE=""

for arg in "$@"; do
    case "$arg" in
        --build|-b)
            BUILD_REQUESTED=1
            ;;
        --auto|--direct|--gpu)
            if [ -n "$RENDER_MODE" ]; then
                echo "ERROR: Choose only one of --auto, --direct, or --gpu." >&2
                exit 2
            fi
            RENDER_MODE="${arg#--}"
            ;;
        --help|-h)
            echo "Usage: ./run.sh [--build|-b] [--auto|--direct|--gpu]"
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option '$arg'." >&2
            echo "Usage: ./run.sh [--build|-b] [--auto|--direct|--gpu]" >&2
            exit 2
            ;;
    esac
done

if [ "$BUILD_REQUESTED" -eq 1 ] || [ ! -f "$BUILD/Desktop.swf" ]; then
    if [ ! -f "$BUILD/Desktop.swf" ]; then
        echo "=> Desktop.swf not found. Building before launch..."
    fi
    "$DIR/build.sh"
fi

if [ ! -f "$BUILD/Desktop.swf" ]; then
    echo "ERROR: $BUILD/Desktop.swf is missing after build." >&2
    exit 1
fi

mkdir -p "$BUILD"


LOG_SRC="$BUILD/assets/api.log"
mkdir -p "$BUILD/assets"
touch "$LOG_SRC"

# Convenience links to the same log. All point at build/, none at loader/.
ln -sf "$LOG_SRC" "$DIR/../api.log" 2>/dev/null || true
ln -sf "$LOG_SRC" "$DIR/api.log" 2>/dev/null || true

CURRENT_USER="${USER:-$(whoami)}"
WINE_PREFIX="${WINEPREFIX:-$HOME/.wine}"
if [ -d "$WINE_PREFIX" ]; then
    WINE_LOG_DIR="${WINE_LOG_DIR:-$WINE_PREFIX/drive_c/users/$CURRENT_USER/AppData/Roaming/com.aqw.pocket/Local Store}"
    mkdir -p "$WINE_LOG_DIR/assets"
    ln -sf "$LOG_SRC" "$WINE_LOG_DIR/assets/api.log" 2>/dev/null || true
    ln -sf "$LOG_SRC" "$WINE_LOG_DIR/api.log" 2>/dev/null || true
fi


DESCRIPTOR="$BUILD/Desktop-app.xml"
if [ ! -f "$DESCRIPTOR" ]; then
    write_descriptor "$CLIENT/Desktop-app.xml" "$DESCRIPTOR"
fi
if [ -n "$RENDER_MODE" ]; then
    sed -i -E "s|<renderMode>[^<]*</renderMode>|<renderMode>$RENDER_MODE</renderMode>|" "$DESCRIPTOR"
fi

resolve_air_windows

echo "=> Launching ADL via Wine (render mode: ${RENDER_MODE:-descriptor default})..."
cd "$BUILD"
wine "$ADL" -profile extendedDesktop "Desktop-app.xml"

echo "=> ADL closed."
