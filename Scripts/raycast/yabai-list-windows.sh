#!/bin/bash
#
# Raycast Script Command - see Scripts/raycast/README.md.
#
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title List Windows
# @raycast.mode fullOutput
#
# Optional parameters:
# @raycast.icon 🗂
# @raycast.packageName yabai
#
# Documentation:
# @raycast.description Every window yabai knows about, grouped by space.
# @raycast.author schretzi

set -uo pipefail

YABAI=${YABAI:-/opt/homebrew/bin/yabai}
JQ=${JQ:-/usr/bin/jq}

"$YABAI" -m query --windows 2>/dev/null | "$JQ" -r '
  group_by(.space)
  | .[]
  | "space \(.[0].space)",
    (.[] | "  \(.app) - \(.title[0:60])"),
    ""
' || { echo "yabai is not responding"; exit 1; }
