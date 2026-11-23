#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR"

echo "Building TouchStage Editor (100% Pure Swift & Cocoa)..."

swiftc -O \
    AirTheme.swift \
    LayoutModel.swift \
    EditorSyncServer.swift \
    AirTabBarView.swift \
    InspectorView.swift \
    EditorCanvasView.swift \
    EditorWindowController.swift \
    main.swift \
    -framework Cocoa \
    -framework AppKit \
    -o "TouchStage_Editor_bin"

APP_DIR="TouchStage Editor.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "TouchStage_Editor_bin" "$APP_DIR/Contents/MacOS/TouchStage Editor"
chmod +x "$APP_DIR/Contents/MacOS/TouchStage Editor"
cp Info.plist "$APP_DIR/Contents/Info.plist"

if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

echo "TouchStage Editor.app (Pure Swift) built successfully at: $DIR/$APP_DIR"
