#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"
# shellcheck source=lib.sh
. "$DIR/lib.sh"

resolve_air_env

# The upstream client lives in loader/. It is upstream's loader with exactly two
# additions: loader/src/ModBootstrap.as, and the single ModBootstrap.init(this)
# hook at the end of Pocket's constructor. Everything else in loader/ - including
# Desktop.swf / Mobile.swf - is upstream's, used as-is and never recompiled.
CLIENT="$DIR/loader"
BUILD="$DIR/build"
STAGING="$BUILD/staging"
# Gamefiles come from build/, never from loader/. build/gamefiles is wiped on every build, so the
# synced copies live in build/gamefiles-upstream; loader/gamefiles is only a fallback for a checkout
# that predates the relocation.
UPSTREAM_GAMEFILES="$BUILD/gamefiles-upstream"
LEGACY_GAMEFILES="$CLIENT/gamefiles"

HAXE_API_DIR="${HAXE_API_DIR:-$DIR/../aqw-haxe-api}"
HAXE_UI_DIR="${HAXE_UI_DIR:-$DIR/../aqw-haxe-ui}"

for required in "$CLIENT/src/Pocket.as" "$CLIENT/src/ModBootstrap.as" "$CLIENT/Desktop.swf" "$CLIENT/Mobile.swf"; do
    if [ ! -f "$required" ]; then
        echo "ERROR: '$required' is missing - the loader/ tree is incomplete." >&2
        exit 1
    fi
done

if [ "${1:-}" = "--clean" ] || [ "${2:-}" = "--clean" ]; then
    echo "=> Cleaning previous build artifacts..."
    rm -f "$BUILD/Desktop.swf" "$BUILD/Mobile.swf"
fi

mkdir -p "$BUILD"
rm -rf "$STAGING"
mkdir -p "$STAGING"
trap '' EXIT

# ---- Step 0a: Fetch the latest upstream gamefiles ----
# Runs before staging so a new upstream release is picked up automatically instead of silently
# building against whatever was synced last time. sync-gamefiles.sh verifies the APK against the
# release digest and caches by release tag, so this costs one API call and no download in the
# steady state. Set SKIP_SYNC=1 to build offline against the cached copies.
if [ "${SKIP_SYNC:-0}" = "1" ]; then
    echo "=> [0/6] SKIP_SYNC=1 - using cached gamefiles."
elif ! "$DIR/sync-gamefiles.sh" "$UPSTREAM_GAMEFILES"; then
    echo "ERROR: Could not sync upstream gamefiles." >&2
    echo "       Re-run with SKIP_SYNC=1 to build offline against the cached copies." >&2
    exit 1
fi

# ---- Step 0b: Stage the loader tree into the sandbox ----
echo "=> [0/6] Copying loader/ to sandbox (build/staging/)..."
mkdir -p "$STAGING/libs"
cp -r "$CLIENT/src" "$STAGING/src"
# Fixes for upstream bugs are applied to the staged copy only; loader/ stays pristine.
#python3 "$DIR/patches/apply.py" "$STAGING/src"
cp -r "$CLIENT/worker-src" "$STAGING/worker-src"
cp -r "$CLIENT/assets" "$STAGING/assets"
cp -r "$CLIENT/icons" "$STAGING/icons"
cp "$CLIENT/Desktop-app.xml" "$STAGING/Desktop-app.xml"
cp "$CLIENT/Mobile-app.xml" "$STAGING/Mobile-app.xml"
cp "$CLIENT/Desktop.swf" "$STAGING/Desktop.swf"
cp "$CLIENT/Mobile.swf" "$STAGING/Mobile.swf"
if [ -d "$CLIENT/libs" ]; then
    cp -r "$CLIENT/libs/." "$STAGING/libs/" 2>/dev/null || true
fi
if [ -d "$UPSTREAM_GAMEFILES" ] && [ -n "$(ls -A "$UPSTREAM_GAMEFILES" 2>/dev/null)" ]; then
    cp -r "$UPSTREAM_GAMEFILES" "$STAGING/gamefiles"
elif [ -d "$LEGACY_GAMEFILES" ]; then
    echo "   Notice: falling back to the legacy loader/gamefiles/ copy."
    cp -r "$LEGACY_GAMEFILES" "$STAGING/gamefiles"
else
    echo "   Notice: no gamefiles found. Run ./sync-gamefiles.sh to fetch the upstream"
    echo "   gamefiles before launching (the client downloads them otherwise)."
fi

# Upstream's desktop build links the Discord RPC ANE, so discord/DiscordRichPresence.as
# needs it resolvable at compile time. The same extension must also exist at runtime in
# build/META-INF, because Pocket instantiates DiscordRichPresence in a *field
# initializer* - AS3 runs those before the constructor body, so a missing extension
# raises VerifyError #1014 before check() is ever reached and the app hangs on loading.
# amxmlc needs a real SWC (a zip of catalog.xml + library.swf), not the bare SWF.
DISCORD_EXT="$CLIENT/META-INF/AIR/extensions/fi.joniaromaa.adobeair.discordrpc"
if [ -f "$DISCORD_EXT/catalog.xml" ] && [ -f "$DISCORD_EXT/library.swf" ]; then
    python3 - "$DISCORD_EXT" "$STAGING/libs/DiscordRpc.swc" <<'PY'
import os
import sys
import zipfile

ext_dir, out_path = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out_path, "w", zipfile.ZIP_DEFLATED) as swc:
    swc.write(os.path.join(ext_dir, "catalog.xml"), "catalog.xml")
    swc.write(os.path.join(ext_dir, "library.swf"), "library.swf")
PY
fi

# ---- Step 1: Compile the Haxe mod libraries into the sandbox ----
# Both SWCs are compiled from the sibling repositories and linked from the sandbox,
# so aqw-haxe-api and aqw-haxe-ui are the single source of truth for mod code.
# SKIP_HAXE=1 reuses whatever is already staged in loader/libs/ for offline builds.
if [ "${SKIP_HAXE:-}" != "1" ]; then
    if [ -d "$HAXE_API_DIR" ]; then
        echo "=> [1/6] Compiling AqwApi (aqw-haxe-api)..."
        run_haxe_build "$HAXE_API_DIR"
        cp "$HAXE_API_DIR/bin/AqwApi.swc" "$STAGING/libs/AqwApi.swc"
    fi
    if [ -d "$HAXE_UI_DIR" ]; then
        echo "=> [2/6] Compiling ModUI (aqw-haxe-ui)..."
        run_haxe_build "$HAXE_UI_DIR"
        cp "$HAXE_UI_DIR/bin/ModUI.swc" "$STAGING/libs/ModUI.swc"
    fi
fi

for required_swc in AqwApi.swc ModUI.swc; do
    if [ ! -f "$STAGING/libs/$required_swc" ]; then
        echo "ERROR: libs/$required_swc is missing." >&2
        if [ "$required_swc" = "ModUI.swc" ]; then
            echo "       aqw-haxe-ui did not produce it - run 'haxe build.hxml' in $HAXE_UI_DIR." >&2
        else
            echo "       aqw-haxe-api did not produce it - run 'haxe build.hxml' in $HAXE_API_DIR." >&2
        fi
        exit 1
    fi
done

# ---- Step 2: WorkerMain.swf ----
# WorkerMain.as is a background worker that strips SWF animation/filters. It is NOT shipped in
# upstream release assets, and recompiling it from loader/worker-src/ fails: SWFStripper.as
# imports com.codeazur.as3swf, which is neither vendored in the repo nor available as a SWC.
#
# The working prebuilt copy lives in the desktop release zip at
# gamefiles/embed/WorkerMain.swf (148477 bytes). sync-gamefiles.sh does not pull it because the
# current upstream release assets do not bundle it, so we vendor a copy at
# loader/libs/WorkerMain.swf and stage it from there. loader/worker-src/ is kept for reference
# but is NOT compiled.
#
# SWFWorkerClient embeds it at compile time via [Embed(source="../../gamefiles/embed/WorkerMain.swf")],
# which resolves relative to Pocket.as's source-path ($STAGING/src/), i.e. exactly that path — so
# the Embed class is emitted into the injected ABC and the runtime does not throw
# "Variable SWFWorkerClient_WorkerSWF is not defined".
if [ -f "$DIR/loader/libs/WorkerMain.swf" ]; then
    echo "=> [3/6] Staging WorkerMain.swf from loader/libs/WorkerMain.swf..."
    mkdir -p "$STAGING/gamefiles/embed"
    cp "$DIR/loader/libs/WorkerMain.swf" "$STAGING/gamefiles/embed/WorkerMain.swf"
else
    echo "ERROR: loader/libs/WorkerMain.swf is missing." >&2
    echo "       Obtain a prebuilt copy from a desktop release that bundles it and save it at" >&2
    echo "       loader/libs/WorkerMain.swf. Recompiling from loader/worker-src/ is not possible:" >&2
    echo "       SWFStripper.as needs com.codeazur.as3swf, which is neither vendored nor a SWC." >&2
    exit 1
fi

# ---- Step 3: Compile our code, then inject it into the pristine upstream SWF ----
# The original FLA artwork exists only inside the upstream Desktop.swf / Mobile.swf.
# Neither repository ships the FLA, so the artwork cannot be recompiled. Instead we
# swap the *code* and leave the timeline untouched:
#   1. compile <label>_code.swf from our loader/src/Pocket.as (upstream's, plus the
#      single ModBootstrap.init(this) hook) with the Haxe SWCs linked in
#   2. abcexport  -> lift that SWF's ABC block out
#   3. abcreplace -> drop it into the upstream SWF in place of ABC block 0
# Only the ABC changes, so every DefineShape/DefineSprite/DefineButton2 and the whole
# SymbolClass table survive, and the FLA instance names (versionTxt, buttonTxt,
# contentMenu, ...) still resolve. That is what makes the original artstyle usable.
#
# Only src/Pocket.as is passed to amxmlc on purpose: that is the only way it emits the
# whole program into a single ABC block, which is what abcreplace expects. Passing every
# .as file splits the program across several blocks and replacing block 0 then leaves a
# 1 KB stub in place of the real code.
resolve_flex_tools
echo "=> Toolchain: $(basename "$AMXMLC"), java ${JAVA_HOME##*/}, flex tools in ${FLEX_TOOLS}"

inject_code_into_shell() {
    local is_desktop="$1" is_mobile="$2" label="$3"

    echo "   -> ${label}: compiling ${label}_code.swf (upstream AS3 + Haxe SWCs)..."
    "$AMXMLC" \
        +configname=air \
        -strict=false \
        -debug=true \
        -default-size 960 550 \
        -default-frame-rate 120 \
        -default-background-color 0x000000 \
        -define+=POCKET::IS_DESKTOP,"$is_desktop" \
        -define+=POCKET::IS_MOBILE,"$is_mobile" \
        -library-path+="$STAGING/libs" \
        -source-path+="$STAGING/src" \
        -output "$STAGING/${label}_code.swf" \
        "$STAGING/src/Pocket.as"

    echo "   -> ${label}: injecting mod code (artwork preserved)..."
    (
        cd "$STAGING"
        abcexport "${label}_code.swf"
        abcreplace "${label}.swf" 0 "${label}_code-0.abc"
        cp "${label}_code.swf" /tmp/inspect_${label}_code.swf; rm -f "${label}_code-0.abc" "${label}"-*.abc
    )
    cp "$STAGING/${label}.swf" "$BUILD/${label}.swf"
}

# ---- Step 4: Inject into both shells ----
echo "=> [4/6] Injecting mod code into the pristine upstream shells..."
inject_code_into_shell true false Desktop
inject_code_into_shell false true Mobile

# ---- Step 5: Assemble the runnable directory ----
echo "=> [5/6] Assembling build/ ..."
rm -rf "$BUILD/assets" "$BUILD/icons" "$BUILD/gamefiles" "$BUILD/META-INF"
cp -r "$STAGING/assets" "$BUILD/assets"
cp -r "$STAGING/icons" "$BUILD/icons"
if [ -d "$STAGING/gamefiles" ]; then
    cp -r "$STAGING/gamefiles" "$BUILD/gamefiles"
fi

# Upstream's Desktop-app.xml declares <extensionID>fi.joniaromaa.adobeair.discordrpc
# </extensionID>. The bare loader/libs/DiscordRPC.ane is enough for amxmlc to resolve the
# DiscordRpc type at compile time, but it is not a loadable runtime extension descriptor,
# so adl aborts with "Requested extension ... could not be found" before the app starts.
# Strip the <extensions> block from the descriptors we generate; loader/ stays untouched.
# DiscordRichPresence.enable() already returns early unless the user opts in.
# adl resolves native extension descriptors relative to the build directory.
if [ -d "$CLIENT/META-INF" ]; then
    cp -r "$CLIENT/META-INF" "$BUILD/META-INF"
fi

write_descriptor "$CLIENT/Desktop-app.xml" "$BUILD/Desktop-app.xml"
sed "s|<renderMode>.*</renderMode>|<renderMode>gpu</renderMode>|" \
    "$BUILD/Desktop-app.xml" > "$BUILD/Desktop-app-gpu.xml"

echo "=> Build complete. Upstream loader/ untouched; artifacts in build/:"
ls -la "$BUILD/Desktop.swf" "$BUILD/Mobile.swf" 2>/dev/null || true
echo "=> Launch with: ./run.sh [--auto|--direct|--gpu]"
