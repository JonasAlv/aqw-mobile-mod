#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GAMEFILES_DIR="$DIR/build/gamefiles-upstream"
DESTINATION="${1:-$GAMEFILES_DIR}"
if [[ "$#" -gt 1 ]]; then
    echo "Usage: sync-gamefiles.sh [gamefiles-directory]" >&2
    exit 2
fi
CACHE_DIR="$DIR/build/upstream-apk-cache"
RELEASE_API="https://api.github.com/repos/anthony-hyo/aqw-mobile/releases/latest"
GAME_CDN_BASE="https://game.aq.com/game/"
REQUIRED_FILES=(
    "gamefiles/game.swf"
    "gamefiles/book-of-lore.swf"
    "gamefiles/character-select.swf"
)
OPTIONAL_FILES=(
    "gamefiles/world-map.swf"
)

# CDN URLs for files not included in the APK
# The upstream APK only bundles game.swf now; other gamefiles are loaded from the game CDN
declare -A CDN_URLS=(
    ["gamefiles/book-of-lore.swf"]="gamefiles/news/spiderbook3.swf"
    ["gamefiles/character-select.swf"]="gamefiles/interface/CharSelect/charselect.swf"
    ["gamefiles/world-map.swf"]="gamefiles/news/Map-UI_r38.swf"
)

for tool in curl python3 unzip sha256sum; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: Required tool '$tool' was not found." >&2
        exit 1
    fi
done

mkdir -p "$CACHE_DIR" "$DESTINATION"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aqw-gamefiles.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

curl --fail --silent --show-error --location \
    --retry 3 \
    --retry-delay 2 \
    --retry-max-time 60 \
    --max-time 30 \
    --connect-timeout 10 \
    --header "Accept: application/vnd.github+json" \
    --header "User-Agent: aqw-mobile-mod-gamefile-sync" \
    "$RELEASE_API" \
    --output "$TMP_DIR/release.json"

mapfile -t RELEASE_METADATA < <(python3 - "$TMP_DIR/release.json" <<'PY'
import json
import re
import sys

with open(sys.argv[1], encoding="utf-8") as release_file:
    release = json.load(release_file)

if release.get("draft") or release.get("prerelease"):
    raise SystemExit("Latest upstream release is not a stable release.")

assets = release.get("assets", [])
asset = next(
    (
        item
        for item in assets
        if re.search(r"-armv8\.apk$", item.get("name", ""), re.IGNORECASE)
    ),
    None,
)
if asset is None:
    asset = next(
        (
            item
            for item in assets
            if re.search(r"-armv7\.apk$", item.get("name", ""), re.IGNORECASE)
        ),
        None,
    )
if asset is None:
    raise SystemExit("Latest upstream release contains no ARM APK asset.")

digest = asset.get("digest", "")
if digest and not re.fullmatch(r"sha256:[a-fA-F0-9]{64}", digest):
    raise SystemExit("Latest APK has an unsupported release digest.")

print(release.get("tag_name", "latest"))
print(asset["browser_download_url"])
print(digest.removeprefix("sha256:").lower())
PY
)

if [[ "${#RELEASE_METADATA[@]}" -ne 3 ]]; then
    echo "ERROR: Could not resolve latest upstream APK metadata." >&2
    exit 1
fi

RELEASE_TAG="${RELEASE_METADATA[0]}"
APK_URL="${RELEASE_METADATA[1]}"
APK_DIGEST="${RELEASE_METADATA[2]}"
if [[ ! "$RELEASE_TAG" =~ ^[a-zA-Z0-9._-]+$ || "$APK_URL" != https://github.com/anthony-hyo/aqw-mobile/releases/download/* ]]; then
    echo "ERROR: Upstream release returned an invalid tag or APK URL." >&2
    exit 1
fi

APK_PATH="$CACHE_DIR/latest.apk"
TAG_PATH="$CACHE_DIR/latest.tag"

if [[ -f "$TAG_PATH" ]]; then
    CACHED_TAG="$(cat "$TAG_PATH")"
    if [[ "$CACHED_TAG" != "$RELEASE_TAG" ]]; then
        rm -f "$APK_PATH"
    fi
else
    rm -f "$APK_PATH"
fi

if [[ -n "$APK_DIGEST" ]] && [[ -f "$APK_PATH" ]]; then
    CACHED_DIGEST="$(sha256sum "$APK_PATH" | cut -d ' ' -f 1)"
    if [[ "$CACHED_DIGEST" != "$APK_DIGEST" ]]; then
        rm -f "$APK_PATH"
    fi
fi

if [[ ! -s "$APK_PATH" ]]; then
    echo "=> Downloading upstream AQW Mobile $RELEASE_TAG APK..."
    curl --fail --silent --show-error --location \
        --retry 3 \
        --retry-delay 2 \
        --retry-max-time 120 \
        --max-time 300 \
        --connect-timeout 30 \
        --header "User-Agent: aqw-mobile-mod-gamefile-sync" \
        "$APK_URL" \
        --output "$TMP_DIR/latest.apk"

    if [[ -n "$APK_DIGEST" ]]; then
        DOWNLOADED_DIGEST="$(sha256sum "$TMP_DIR/latest.apk" | cut -d ' ' -f 1)"
        if [[ "$DOWNLOADED_DIGEST" != "$APK_DIGEST" ]]; then
            echo "ERROR: Downloaded APK SHA-256 does not match the GitHub release digest." >&2
            exit 1
        fi
    fi
    mv "$TMP_DIR/latest.apk" "$APK_PATH"
    printf '%s' "$RELEASE_TAG" > "$TAG_PATH"
fi


APK_LISTING="$TMP_DIR/apk-listing.txt"
unzip -Z1 "$APK_PATH" > "$APK_LISTING"

# Function to download a file from the game CDN
download_from_cdn() {
    local archive_path="$1"
    local dest_path="$2"
    local cdn_relative="${CDN_URLS[$archive_path]:-}"
    
    if [[ -z "$cdn_relative" ]]; then
        # Fallback: try the standard path
        cdn_relative="$archive_path"
    fi
    
    local cdn_url="${GAME_CDN_BASE}${cdn_relative}"
    
    echo "=> Attempting to download '$archive_path' from game CDN: $cdn_url"
    curl --fail --silent --show-error --location \
        --retry 3 \
        --retry-delay 2 \
        --retry-max-time 60 \
        --max-time 120 \
        --connect-timeout 30 \
        --header "User-Agent: aqw-mobile-mod-gamefile-sync" \
        "$cdn_url" \
        --output "$dest_path"
    
    if [[ -s "$dest_path" ]]; then
        echo "=> Successfully downloaded '$archive_path' from CDN"
        return 0
    else
        echo "=> CDN download failed or empty for '$archive_path'"
        rm -f "$dest_path"
        return 1
    fi
}

SYNCED_FILES=()
for archive_path in "${REQUIRED_FILES[@]}" "${OPTIONAL_FILES[@]}"; do
    apk_path="$archive_path"
    if ! grep -Fqx -- "$apk_path" "$APK_LISTING"; then
        apk_path="assets/$archive_path"
    fi
    
    extracted_path="$TMP_DIR/${archive_path#gamefiles/}"
    mkdir -p "$(dirname "$extracted_path")"
    
    file_synced=false
    
    # Try extracting from APK first
    if grep -Fqx -- "$apk_path" "$APK_LISTING"; then
        unzip -p "$APK_PATH" "$apk_path" > "$extracted_path"
        if [[ -s "$extracted_path" ]]; then
            echo "=> Extracted '$archive_path' from upstream APK"
            file_synced=true
        else
            echo "=> WARNING: Extracted '$archive_path' from APK is empty"
        fi
    fi
    
    # If not in APK or empty, try downloading from CDN
    if [[ "$file_synced" = false ]]; then
        if download_from_cdn "$archive_path" "$extracted_path"; then
            file_synced=true
        fi
    fi
    
    # If still not synced, check if it's optional and we have a cached copy
    if [[ "$file_synced" = false ]]; then
        if [[ " ${OPTIONAL_FILES[*]} " == *" $archive_path "* ]] \
            && [[ -s "$DESTINATION/${archive_path#gamefiles/}" ]]; then
            echo "=> '$archive_path' not in APK or CDN; keeping existing bundled copy."
            file_synced=true
        fi
    fi
    
    # Final check
    if [[ "$file_synced" = false ]]; then
        echo "ERROR: Could not obtain '$archive_path' from APK or CDN." >&2
        exit 1
    fi
    
    SYNCED_FILES+=("$archive_path")
done

for archive_path in "${SYNCED_FILES[@]}"; do
    cp "$TMP_DIR/${archive_path#gamefiles/}" "$DESTINATION/${archive_path#gamefiles/}"
done

echo "=> Synced gamefiles from upstream release $RELEASE_TAG to $DESTINATION."
