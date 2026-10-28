#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR"

echo "Building TouchStage Editor (Swift & Cocoa)..."

# 1. Compile Objective-C core components to object files
clang -c -O2 -fobjc-arc \
    LayoutModel.m \
    AirTabBarView.m \
    EditorCanvasView.m \
    InspectorView.m \
    EditorWindowController.m

# 2. Compile Swift entry point & link
swiftc -O \
    -import-objc-header Editor-Bridging-Header.h \
    main.swift \
    LayoutModel.o \
    AirTabBarView.o \
    EditorCanvasView.o \
    InspectorView.o \
    EditorWindowController.o \
    -framework Cocoa \
    -framework AppKit \
    -o "TouchStage_Editor_bin"

rm -f *.o

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

echo "TouchStage Editor.app (Swift) built successfully at: $DIR/$APP_DIR"
