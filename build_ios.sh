#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR"

echo "=========================================================="
echo "  Building TouchStage for iOS (iPhone & iPad)"
echo "=========================================================="

BUILD_DIR="$DIR/ios/build"
mkdir -p "$BUILD_DIR"

# 1. Build using xcodebuild for iOS Simulator (Universal arm64 / x86_64)
xcodebuild -project "$DIR/ios/TouchStage.xcodeproj" \
           -scheme "TouchStage" \
           -configuration "Release" \
           -sdk "iphonesimulator" \
           -derivedDataPath "$BUILD_DIR/DerivedData" \
           CODE_SIGNING_ALLOWED=NO \
           build | xcbeautify 2>/dev/null || xcodebuild -project "$DIR/ios/TouchStage.xcodeproj" \
                                                        -scheme "TouchStage" \
                                                        -configuration "Release" \
                                                        -sdk "iphonesimulator" \
                                                        -derivedDataPath "$BUILD_DIR/DerivedData" \
                                                        CODE_SIGNING_ALLOWED=NO \
                                                        build

# 2. Extract built .app
BUILT_APP="$BUILD_DIR/DerivedData/Build/Products/Release-iphonesimulator/TouchStage.app"

if [ -d "$BUILT_APP" ]; then
    rm -rf "$BUILD_DIR/TouchStage.app" "$DIR/TouchStage-iOS.app"
    cp -R "$BUILT_APP" "$BUILD_DIR/TouchStage.app"
    cp -R "$BUILT_APP" "$DIR/TouchStage-iOS.app"
    echo ""
    echo "✅ TouchStage iOS App built successfully!"
    echo "   👉 Simulator App: $BUILD_DIR/TouchStage.app"
    echo "   👉 Root App:      $DIR/TouchStage-iOS.app"
    echo "   👉 Xcode Project: $DIR/ios/TouchStage.xcodeproj"
else
    echo "❌ Build output not found."
    exit 1
fi

# 3. Optional Simulator Launch
if [[ "$1" == "--run" || "$1" == "--sim" ]]; then
    echo ""
    echo "📱 Launching in iOS Simulator..."
    BOOTED_DEVICE=$(xcrun simctl list devices | grep "(Booted)" | head -n 1 | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/')
    
    if [ -z "$BOOTED_DEVICE" ]; then
        # Pick an iPad or iPhone simulator
        SIM_ID=$(xcrun simctl list devices available | grep -E "iPad Pro|iPhone 17" | head -n 1 | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/')
        if [ -n "$SIM_ID" ]; then
            echo "   Booting simulator: $SIM_ID..."
            xcrun simctl boot "$SIM_ID" || true
            open -a Simulator
            sleep 3
            BOOTED_DEVICE="$SIM_ID"
        fi
    else
        open -a Simulator
    fi

    if [ -n "$BOOTED_DEVICE" ]; then
        echo "   Installing TouchStage.app..."
        xcrun simctl install "$BOOTED_DEVICE" "$BUILD_DIR/TouchStage.app"
        echo "   Launching TouchStage..."
        xcrun simctl launch "$BOOTED_DEVICE" "com.airmidi.touchstage.ios"
        echo "🎉 TouchStage is now running in the Simulator!"
    fi
else
    echo ""
    echo "💡 Tips:"
    echo "   - To run directly on Simulator:  ./build_ios.sh --run"
    echo "   - To open and run in Xcode:      open ios/TouchStage.xcodeproj"
fi
