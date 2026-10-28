#!/bin/bash
set -e

echo "Building TouchStage for Android..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Locate Java from Android Studio or system if not set
if [ -z "$JAVA_HOME" ]; then
    if [ -d "/Applications/Android Studio.app/Contents/jbr/Contents/Home" ]; then
        export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
    fi
fi

cd "$SCRIPT_DIR/android"
./gradlew assembleDebug

cp "$SCRIPT_DIR/android/app/build/outputs/apk/debug/app-debug.apk" "$SCRIPT_DIR/TouchStage.apk"
echo "✅ TouchStage.apk generated successfully at:"
echo "   👉 $SCRIPT_DIR/TouchStage.apk"
