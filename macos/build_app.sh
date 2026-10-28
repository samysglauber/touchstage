#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR"

echo "🔨 Compilando AirMIDI Studio para macOS (100% Nativo Cocoa & CoreMIDI)..."

clang -O2 -fobjc-arc \
    -framework Cocoa \
    -framework AppKit \
    -framework CoreMIDI \
    -x objective-c \
    src/LayoutModel.m \
    src/EditorCanvasView.m \
    src/InspectorView.m \
    src/EditorWindowController.m \
    src/AirMIDIServer.m \
    src/main.m \
    -o AirMIDI_bin

APP_DIR="AirMIDI.app"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp AirMIDI_bin "$APP_DIR/Contents/MacOS/AirMIDI"
chmod +x "$APP_DIR/Contents/MacOS/AirMIDI"
cp Info.plist "$APP_DIR/Contents/Info.plist"

echo "✅ AirMIDI Studio.app compilado com sucesso em: $DIR/AirMIDI.app"
