#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GAMEFILES_DIR="$DIR/build/gamefiles-upstream"
DESTINATION="${1:-$GAMEFILES_DIR}"
if [[ "$#" -gt 1 ]]; then
    echo "Usage: sync-gamefiles.sh [gamefiles-directory]" >&2
    exit 2
fi
CACHE_DIR="$DIR/build/upstream-windows-cache"
RELEASE_API="https://api.github.com/repos/anthony-hyo/aqw-mobile/releases/latest"

for tool in curl python3 unzip sha256sum; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: Required tool '$tool' was not found." >&2
        exit 1
    fi
done

mkdir -p "$CACHE_DIR"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aqw-gamefiles.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

curl --fail --silent --show-error --location \
    --retry 3 --retry-delay 2 --retry-max-time 60 \
    --max-time 30 --connect-timeout 10 \
    --header "Accept: application/vnd.github+json" \
    --header "User-Agent: aqw-mobile-mod-gamefile-sync" \
    "$RELEASE_API" --output "$TMP_DIR/release.json"

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
    (item for item in assets
     if re.search(r"-windows-x64\.zip$", item.get("name", ""), re.IGNORECASE)),
    None,
)
if asset is None:
    raise SystemExit("Latest stable upstream release has no Windows x64 ZIP asset.")

digest = asset.get("digest", "")
if digest and not re.fullmatch(r"sha256:[a-fA-F0-9]{64}", digest):
    raise SystemExit("Windows ZIP has an unsupported release digest.")

print(release.get("tag_name", "latest"))
print(asset["browser_download_url"])
print(digest.removeprefix("sha256:").lower())
PY
)

if [[ "${#RELEASE_METADATA[@]}" -ne 3 ]]; then
    echo "ERROR: Could not resolve latest upstream Windows release metadata." >&2
    exit 1
fi

RELEASE_TAG="${RELEASE_METADATA[0]}"
ZIP_URL="${RELEASE_METADATA[1]}"
ZIP_DIGEST="${RELEASE_METADATA[2]}"
if [[ ! "$RELEASE_TAG" =~ ^[a-zA-Z0-9._-]+$ || "$ZIP_URL" != https://github.com/anthony-hyo/aqw-mobile/releases/download/* ]]; then
    echo "ERROR: Upstream release returned an invalid tag or ZIP URL." >&2
    exit 1
fi

ZIP_PATH="$CACHE_DIR/latest-windows-x64.zip"
TAG_PATH="$CACHE_DIR/latest.tag"

if [[ -f "$TAG_PATH" ]] && [[ "$(cat "$TAG_PATH")" != "$RELEASE_TAG" ]]; then
    rm -f "$ZIP_PATH"
fi
if [[ -n "$ZIP_DIGEST" && -f "$ZIP_PATH" ]]; then
    CACHED_DIGEST="$(sha256sum "$ZIP_PATH" | cut -d ' ' -f 1)"
    if [[ "$CACHED_DIGEST" != "$ZIP_DIGEST" ]]; then
        rm -f "$ZIP_PATH"
    fi
fi

if [[ ! -s "$ZIP_PATH" ]]; then
    echo "=> Downloading upstream AQW Mobile Windows x64 release $RELEASE_TAG..."
    curl --fail --silent --show-error --location \
        --retry 3 --retry-delay 2 --retry-max-time 120 \
        --max-time 600 --connect-timeout 30 \
        --header "User-Agent: aqw-mobile-mod-gamefile-sync" \
        "$ZIP_URL" --output "$TMP_DIR/latest-windows-x64.zip"

    if [[ -n "$ZIP_DIGEST" ]]; then
        DOWNLOADED_DIGEST="$(sha256sum "$TMP_DIR/latest-windows-x64.zip" | cut -d ' ' -f 1)"
        if [[ "$DOWNLOADED_DIGEST" != "$ZIP_DIGEST" ]]; then
            echo "ERROR: Downloaded Windows ZIP SHA-256 does not match the GitHub release digest." >&2
            exit 1
        fi
    fi
    mv "$TMP_DIR/latest-windows-x64.zip" "$ZIP_PATH"
    printf '%s' "$RELEASE_TAG" > "$TAG_PATH"
fi

# Find the gamefiles directory inside the Windows bundle and extract every file
# beneath it, preserving subdirectories. Never extract unrelated archive entries.
python3 - "$ZIP_PATH" "$TMP_DIR/extracted-gamefiles" <<'PY'
import os
import sys
import zipfile
from pathlib import PurePosixPath

archive_path, output_dir = sys.argv[1:3]
with zipfile.ZipFile(archive_path) as archive:
    entries = archive.infolist()
    candidates = []
    for entry in entries:
        normalized = entry.filename.replace("\\", "/").lstrip("./")
        parts = PurePosixPath(normalized).parts
        for index, part in enumerate(parts):
            if part.lower() == "gamefiles" and index < len(parts) - 1:
                prefix = "/".join(parts[:index + 1]) + "/"
                candidates.append(prefix)
                break

    prefixes = sorted(set(candidates), key=lambda prefix: (prefix.count("/"), len(prefix)))
    selected = None
    for prefix in prefixes:
        names = [
            item.filename.replace("\\", "/").lstrip("./")
            for item in entries
            if not item.is_dir()
            and item.filename.replace("\\", "/").lstrip("./").startswith(prefix)
        ]
        if any(name[len(prefix):].lower() == "game.swf" for name in names):
            selected = prefix
            break

    if selected is None:
        raise SystemExit(
            "ERROR: Windows release ZIP does not contain a gamefiles/ directory with game.swf. "
            "Cannot guarantee a complete gamefiles sync."
        )

    count = 0
    os.makedirs(output_dir, exist_ok=True)
    for entry in entries:
        normalized = entry.filename.replace("\\", "/").lstrip("./")
        if entry.is_dir() or not normalized.startswith(selected):
            continue
        relative = normalized[len(selected):]
        target = os.path.realpath(os.path.join(output_dir, *PurePosixPath(relative).parts))
        if os.path.commonpath([os.path.realpath(output_dir), target]) != os.path.realpath(output_dir):
            raise SystemExit("ERROR: Unsafe path found in upstream Windows ZIP.")
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with archive.open(entry) as source, open(target, "wb") as destination:
            while True:
                chunk = source.read(1024 * 1024)
                if not chunk:
                    break
                destination.write(chunk)
        count += 1

    game_swf = os.path.join(output_dir, "game.swf")
    if not os.path.isfile(game_swf) or os.path.getsize(game_swf) == 0:
        raise SystemExit("ERROR: Extracted gamefiles/game.swf is missing or empty.")
    if count == 0:
        raise SystemExit("ERROR: No files were extracted from the upstream gamefiles directory.")
    print(f"Extracted {count} file(s) from {selected}")
PY

# Replace the destination completely so files removed upstream do not linger locally.
rm -rf "$DESTINATION"
mkdir -p "$(dirname "$DESTINATION")"
mv "$TMP_DIR/extracted-gamefiles" "$DESTINATION"

FILE_COUNT="$(find "$DESTINATION" -type f | wc -l | tr -d '[:space:]')"
echo "=> Synced all $FILE_COUNT gamefiles from upstream Windows release $RELEASE_TAG to $DESTINATION."
