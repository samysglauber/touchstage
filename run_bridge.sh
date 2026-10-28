#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
killall "TouchStage Bridge" 2>/dev/null || true
killall "AirMIDI Bridge" 2>/dev/null || true
if [ -d "$DIR/TouchStage Bridge.app" ]; then
    open "$DIR/TouchStage Bridge.app"
else
    open "$DIR/macos/bridge/TouchStage Bridge.app"
fi
echo "TouchStage Bridge running in macOS menu bar."
