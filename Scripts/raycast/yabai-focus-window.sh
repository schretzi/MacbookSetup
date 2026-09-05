#!/bin/bash
#
# Raycast Script Command - see Scripts/raycast/README.md.
#
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Focus Window
# @raycast.mode silent
#
# Optional parameters:
# @raycast.icon 🪟
# @raycast.packageName yabai
# @raycast.argument1 { "type": "text", "placeholder": "app or title" }
#
# Documentation:
# @raycast.description Jump to any window across all spaces, by app name or window title.
# @raycast.author schretzi

set -uo pipefail

YABAI=${YABAI:-/opt/homebrew/bin/yabai}
JQ=${JQ:-/usr/bin/jq}
query="${1:-}"

if [[ -z "$query" ]]; then
  echo "Give part of an app name or window title"
  exit 1
fi

# id \t space \t app \t title, skipping yabai's own zero-id placeholders.
windows=$("$YABAI" -m query --windows 2>/dev/null \
  | "$JQ" -r '.[] | select(.id != null) | [.id, .space, .app, .title] | @tsv') || {
  echo "yabai is not responding"
  exit 1
}
[[ -z "$windows" ]] && { echo "No windows"; exit 1; }

# App matches rank above title matches: typing "kit" should land on kitty, not
# on some browser tab that happens to mention it in its title.
shopt -s nocasematch
best_id=""
best_label=""
matches=0
while IFS=$'\t' read -r id space app title; do
  rank=0
  [[ "$app" == *"$query"* ]] && rank=2
  [[ $rank -eq 0 && "$title" == *"$query"* ]] && rank=1
  [[ $rank -eq 0 ]] && continue
  matches=$((matches + 1))
  if [[ -z "$best_id" || $rank -gt ${best_rank:-0} ]]; then
    best_id="$id"
    best_rank=$rank
    best_label="$app - ${title:0:50} (space $space)"
  fi
done <<<"$windows"
shopt -u nocasematch

if [[ -z "$best_id" ]]; then
  echo "No window matching '$query'"
  exit 1
fi

# --focus follows the window to its space, so this crosses spaces on its own.
if "$YABAI" -m window --focus "$best_id" 2>/dev/null; then
  if [[ $matches -gt 1 ]]; then
    echo "$best_label (+$((matches - 1)) more)"
  else
    echo "$best_label"
  fi
else
  echo "Could not focus $best_label"
  exit 1
fi
