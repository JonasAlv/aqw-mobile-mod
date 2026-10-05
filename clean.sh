#!/usr/bin/env bash
# clean.sh - remove regenerable build and IDE scratch from the repo folders.
#
# Default is deliberately conservative: it drops staging and scratch but keeps the compiled
# artifacts and the download caches, so a clean does not force a re-download or a full rebuild.
# Pass --all to wipe build/ completely.
#
# Usage: ./clean.sh [--all] [--drop-legacy-gamefiles]

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

BUILD="$DIR/build"
STAGING="$BUILD/staging"
LEGACY_GAMEFILES="$DIR/loader/gamefiles"
HAVE_ALL=0
DROP_LEGACY=0
for arg in "$@"; do
    case "$arg" in
        --all) HAVE_ALL=1 ;;
        --drop-legacy-gamefiles) DROP_LEGACY=1 ;;
        --help|-h)
            echo "Usage: ./clean.sh [--all] [--drop-legacy-gamefiles]"
            echo "  --all                  wipe build/ entirely (re-sync, re-download, rebuild)"
            echo "  --drop-legacy-gamefiles  delete the dead loader/gamefiles/ fallback copies"
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option '$arg'." >&2
            echo "Usage: ./clean.sh [--all] [--drop-legacy-gamefiles]" >&2
            exit 2
            ;;
    esac
done

freed() {
    du -sh "$1" 2>/dev/null | cut -f1 || true
}

remove_path() {
    local path="$1" label="$2"
    if [ -e "$path" ]; then
        local size
        size="$(freed "$path")"
        rm -rf "$path"
        echo "   removed $label${size:+ ($size)}"
    fi
}

if [ "$HAVE_ALL" -eq 1 ]; then
    echo "=> Full wipe: build/ (forces re-sync, re-download and rebuild)..."
    remove_path "$BUILD" "build/"
else
    echo "=> Removing regenerable scratch (keeping artifacts and caches)..."
    remove_path "$STAGING" "build/staging/"

    # Staged copies of assets/icons/gamefiles/META-INF. build.sh recreates all of these.
    remove_path "$BUILD/assets" "build/assets/"
    remove_path "$BUILD/icons" "build/icons/"
    remove_path "$BUILD/gamefiles" "build/gamefiles/"
    remove_path "$BUILD/META-INF" "build/META-INF/"
    remove_path "$BUILD/Desktop-app-gpu.xml" "build/Desktop-app-gpu.xml"
fi

# Haxe language-server scratch: target/debug + target/flycheck0, with a CMake CACHEDIR.TAG.
# Unrelated to the build, ~250MB, and safe to delete at any time - it regenerates on the next
# language-server run. Ignored via `/target` in .gitignore.
for repo in "$DIR" "$DIR/../aqw-haxe-api" "$DIR/../aqw-haxe-ui"; do
    remove_path "$repo/target" "${repo#$DIR/}/target (language-server scratch)"
done

# Legacy, dead since gamefiles moved to build/gamefiles-upstream. Nothing writes it any more; it is
# only a read fallback in build.sh for checkouts predating that move.
if [ "$DROP_LEGACY" -eq 1 ]; then
    remove_path "$LEGACY_GAMEFILES" "loader/gamefiles/ (legacy fallback)"
elif [ -d "$LEGACY_GAMEFILES" ]; then
    echo "   note: loader/gamefiles/ is legacy and unused. Remove it with --drop-legacy-gamefiles."
fi

echo "=> Done. Build with ./build.sh"