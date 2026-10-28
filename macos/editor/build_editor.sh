#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR"

echo "Building TouchStage Editor (macOS Layout Editor)..."

clang -O2 -fobjc-arc \
    -framework Cocoa \
    -framework AppKit \
    -x objective-c \
    LayoutModel.m \
    AirTabBarView.m \
    EditorCanvasView.m \
    InspectorView.m \
    EditorWindowController.m \
    main.m \
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

echo "TouchStage Editor.app built successfully at: $DIR/$APP_DIR"
