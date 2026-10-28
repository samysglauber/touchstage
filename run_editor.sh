#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
if [ -d "$DIR/TouchStage Studio.app" ]; then
    open "$DIR/TouchStage Studio.app"
else
    open "$DIR/macos/editor/TouchStage Studio.app"
fi
echo "TouchStage Studio Editor opened."
