#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Gamefiles live under build/, never in loader/. loader/ is the upstream client tree: vendored
# binaries written back into it are 3.7MB of untracked source-tree clutter that never shows up in
# `git status` but still gets copied around and can drift out of sync with upstream.
# `gamefiles-upstream` (not `gamefiles`) because build.sh wipes build/gamefiles on every run.
GAMEFILES_DIR="$DIR/build/gamefiles-upstream"
DESTINATION="${1:-$GAMEFILES_DIR}"
if [[ "$#" -gt 1 ]]; then
    echo "Usage: sync-gamefiles.sh [gamefiles-directory]" >&2
    exit 2
fi
CACHE_DIR="$DIR/build/upstream-apk-cache"
RELEASE_API="https://api.github.com/repos/anthony-hyo/aqw-mobile/releases/latest"
REQUIRED_FILES=(
    "gamefiles/game.swf"
    "gamefiles/book-of-lore.swf"
    "gamefiles/character-select.swf"
)
OPTIONAL_FILES=(
    "gamefiles/world-map.swf"
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

# Invalidate on a new release tag, not only on a changed digest.
#
# The digest alone is not enough: when a release ships without the `digest` field, APK_DIGEST is
# empty and the digest branch below is skipped entirely, so a cached `latest.apk` would be reused
# forever and "always fetch latest" would fail silently. Keying on the tag makes the cache correct
# whether or not a digest is published.
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

# List the archive once. Piping unzip into `grep -q` under `set -o pipefail` is
# unreliable: grep exits on the first match, unzip takes SIGPIPE, and the failed
# pipeline reads as "file missing" even when the entry is present.
APK_LISTING="$TMP_DIR/apk-listing.txt"
unzip -Z1 "$APK_PATH" > "$APK_LISTING"

SYNCED_FILES=()
for archive_path in "${REQUIRED_FILES[@]}" "${OPTIONAL_FILES[@]}"; do
    apk_path="$archive_path"
    if ! grep -Fqx -- "$apk_path" "$APK_LISTING"; then
        apk_path="assets/$archive_path"
    fi
    if ! grep -Fqx -- "$apk_path" "$APK_LISTING"; then
        if [[ " ${OPTIONAL_FILES[*]} " == *" $archive_path "* ]] \
            && [[ -s "$DESTINATION/${archive_path#gamefiles/}" ]]; then
            echo "=> Upstream APK omits '$archive_path'; keeping the existing bundled copy."
            continue
        fi
        echo "ERROR: Upstream APK is missing '$archive_path' (also checked assets/$archive_path)." >&2
        exit 1
    fi

    extracted_path="$TMP_DIR/${archive_path#gamefiles/}"
    mkdir -p "$(dirname "$extracted_path")"
    unzip -p "$APK_PATH" "$apk_path" > "$extracted_path"
    if [[ ! -s "$extracted_path" ]]; then
        echo "ERROR: Extracted '$archive_path' is empty." >&2
        exit 1
    fi
    SYNCED_FILES+=("$archive_path")
done

for archive_path in "${SYNCED_FILES[@]}"; do
    cp "$TMP_DIR/${archive_path#gamefiles/}" "$DESTINATION/${archive_path#gamefiles/}"
done

echo "=> Synced gamefiles from upstream release $RELEASE_TAG to $DESTINATION."
