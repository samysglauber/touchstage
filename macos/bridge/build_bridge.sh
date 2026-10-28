#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR"

echo "Building TouchStage Bridge (100% Pure Swift & SwiftUI)..."

swiftc -O \
    main.swift \
    BridgeState.swift \
    BridgeView.swift \
    BridgeServer.swift \
    -framework Cocoa \
    -framework CoreMIDI \
    -framework SwiftUI \
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

echo "TouchStage Bridge.app (Pure Swift) built successfully at: $DIR/$APP_DIR"
