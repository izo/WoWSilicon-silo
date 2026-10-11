#!/bin/sh
# Xcode build phase: copies the Wine runtime and the Wine audio helper into the
# app bundle, mirroring the `bundle` target in the Makefile.
set -eu

RUNTIME_DIR="${WINE_RUNTIME_DIR:-$SRCROOT/.wine-runtime}"
RESOURCES="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"

if [ ! -d "$RUNTIME_DIR" ]; then
    if [ "$CONFIGURATION" = "Release" ]; then
        echo "error: Wine runtime not found at $RUNTIME_DIR. Restore it with: tools/wine-runtime/restore.sh --runtime .wine-runtime" >&2
        exit 1
    fi
    echo "warning: Wine runtime not found at $RUNTIME_DIR; this build cannot launch games." >&2
    exit 0
fi

"$SRCROOT/tools/wine-runtime/validate.sh" --runtime "$RUNTIME_DIR"

make -C "$SRCROOT" audio_helper

mkdir -p "$RESOURCES/Wine" "$RESOURCES/Audio"
cp -R "$RUNTIME_DIR/." "$RESOURCES/Wine/"
find "$RESOURCES/Wine" -name '.DS_Store' -delete
cp "$SRCROOT/.build/audio-helper/wowsilicon-audio.exe" "$RESOURCES/Audio/"
