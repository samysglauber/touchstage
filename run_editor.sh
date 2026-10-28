#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
if [ -d "$DIR/TouchStage Editor.app" ]; then
    open "$DIR/TouchStage Editor.app"
else
    open "$DIR/macos/editor/TouchStage Editor.app"
fi
echo "TouchStage Editor opened."
