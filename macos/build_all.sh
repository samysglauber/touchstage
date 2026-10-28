#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR="$( cd "$DIR/.." >/dev/null 2>&1 && pwd )"

echo "Building TouchStage Suite for macOS..."

cd "$DIR/bridge"
./build_bridge.sh

cd "$DIR/editor"
./build_editor.sh

echo "Deploying executables to root directory..."
rm -rf "$ROOT_DIR/TouchStage Bridge.app" "$ROOT_DIR/TouchStage Editor.app" "$ROOT_DIR/TouchStage Studio.app"
rm -rf "$ROOT_DIR/AirMIDI Bridge.app" "$ROOT_DIR/AirMIDI Studio.app"
cp -R "$DIR/bridge/TouchStage Bridge.app" "$ROOT_DIR/TouchStage Bridge.app"
cp -R "$DIR/editor/TouchStage Editor.app" "$ROOT_DIR/TouchStage Editor.app"

# Clean quarantine and sign
xattr -cr "$ROOT_DIR/TouchStage Bridge.app" "$ROOT_DIR/TouchStage Editor.app"
codesign --force --deep --sign - "$ROOT_DIR/TouchStage Bridge.app"
codesign --force --deep --sign - "$ROOT_DIR/TouchStage Editor.app"

echo "Ready to run from Finder:"
echo "  👉 $ROOT_DIR/TouchStage Bridge.app"
echo "  👉 $ROOT_DIR/TouchStage Editor.app"
