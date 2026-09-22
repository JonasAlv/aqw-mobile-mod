#!/bin/bash
# setup.sh - First-time local dev setup
# Downloads gamefiles from Anthony's latest APK release.
# Run this once after cloning, or whenever Anthony releases a new version.
# Usage: ./setup.sh [version] (e.g. ./setup.sh v3.5.0)

set -e

VERSION=${1:-v3.5.1}
ANTHONY_APK_URL="https://github.com/anthony-hyo/aqw-mobile/releases/download/${VERSION}/AQWPocket-${VERSION}-armv8.apk"
APK_FILE="/tmp/anthony-aqw.apk"
GAMEFILES_DIR="loader/gamefiles"

echo "=> Downloading Anthony's APK (${VERSION})..."
wget -q --show-progress "$ANTHONY_APK_URL" -O "$APK_FILE"

echo "=> Extracting gamefiles..."
mkdir -p "$GAMEFILES_DIR"
unzip -q -o "$APK_FILE" "assets/gamefiles/*" -d /tmp/anthony-aqw-extracted
cp -r /tmp/anthony-aqw-extracted/assets/gamefiles/* "$GAMEFILES_DIR/"

echo "=> Cleaning up..."
rm -f "$APK_FILE"
rm -rf /tmp/anthony-aqw-extracted

echo ""
echo "=> Gamefiles ready:"
ls -lh "$GAMEFILES_DIR/"

# Create skills_custom.json in loader/ for ADL local testing (applicationDirectory)
if [ ! -f "loader/skills_custom.json" ]; then
  echo "=> Creating local skills_custom.json for ADL..."
  cp "loader/assets/skills.json" "loader/skills_custom.json"
fi

echo ""
echo "=> Done! You can now run ./run.sh to test locally."

