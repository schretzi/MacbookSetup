#!/bin/bash
# Frontmost app name. Mirrors the stock sketchybar example's front_app.sh:
# sketchybar passes the new app name in $INFO when the front_app_switched
# event fires, so no yabai/osascript query is needed here.
set -uo pipefail

if [ "$SENDER" = "front_app_switched" ]; then
  sketchybar --set "$NAME" label="$INFO"
fi
