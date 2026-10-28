#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR"

echo "Building TouchStage Bridge (macOS Menu Bar)..."

clang -O2 -fobjc-arc \
    -framework Cocoa \
    -framework CoreMIDI \
    -x objective-c \
    AirMIDIBridgeServer.m \
    main.m \
    -o "TouchStage_Bridge_bin"

APP_DIR="TouchStage Bridge.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "TouchStage_Bridge_bin" "$APP_DIR/Contents/MacOS/TouchStage Bridge"
chmod +x "$APP_DIR/Contents/MacOS/TouchStage Bridge"
cp Info.plist "$APP_DIR/Contents/Info.plist"

if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

echo "TouchStage Bridge.app built successfully at: $DIR/$APP_DIR"
