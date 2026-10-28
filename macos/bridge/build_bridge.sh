#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR"

echo "Building TouchStage Bridge (Swift & SwiftUI)..."

# 1. Compile CoreMIDI / Wi-Fi backend (Objective-C)
clang -c -O2 -fobjc-arc \
    AirMIDIBridgeServer.m \
    -o AirMIDIBridgeServer.o

# 2. Compile Swift Frontend & Link
swiftc -O \
    -import-objc-header Bridge-Bridging-Header.h \
    main.swift \
    BridgeState.swift \
    BridgeView.swift \
    AirMIDIBridgeServer.o \
    -framework Cocoa \
    -framework CoreMIDI \
    -framework SwiftUI \
    -o "TouchStage_Bridge_bin"

rm -f AirMIDIBridgeServer.o

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

echo "TouchStage Bridge.app (Swift) built successfully at: $DIR/$APP_DIR"
