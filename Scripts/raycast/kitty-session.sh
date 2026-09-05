#!/bin/bash
#
# Raycast Script Command - see Scripts/raycast/README.md.
#
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Kitty Session
# @raycast.mode silent
#
# Optional parameters:
# @raycast.icon 🐱
# @raycast.packageName kitty
# @raycast.argument1 { "type": "text", "placeholder": "session", "optional": true }
#
# Documentation:
# @raycast.description Focus a dedicated kitty session, launching it if it is not running.
# @raycast.author schretzi

# Launching the session app bundle directly (Raycast's or Spotlight's app
# search, the Dock) runs kitty's launcher with no arguments, so kitty falls
# back to `startup_session` from kitty.conf and you get a plain home shell -
# no nvim, no close-on-child-death. The session only materialises when kitty
# is started with `--session <file>` and the per-launch -o overrides, which
# is what kitty-focus-or-launch.sh does. This command is the Raycast-side
# entry point into that same script, so a session opened from the launcher
# behaves exactly like one opened from kanata's "^" + s/d/o/m.

set -uo pipefail

sessions_dir="$HOME/.config/kitty/sessions"
scripts_dir="$HOME/.config/kitty/scripts"
query="${1:-}"

shopt -s nullglob
names=()
for f in "$sessions_dir"/*.kitty-session; do
  names+=("$(basename "$f" .kitty-session)")
done
shopt -u nullglob

# The daily note is not a static session file: open-daily-note.sh generates
# today's under ~/.cache/kitty-sessions before delegating, so it is offered
# by name here and dispatched to that script rather than to a file in
# $sessions_dir (which is exactly why "always today's note" works).
names+=("daily-note")

list() { printf '%s' "${names[*]}"; }

if [[ -z "$query" ]]; then
  echo "Which session? $(list)"
  exit 1
fi

# Exact, then prefix, then substring - so "obs" and "obsidian" both land,
# and a typo falls through to a list rather than to the wrong session.
shopt -s nocasematch
matches=()
for n in "${names[@]}"; do [[ "$n" == "$query" ]] && matches=("$n"); done
if [[ ${#matches[@]} -eq 0 ]]; then
  for n in "${names[@]}"; do [[ "$n" == "$query"* ]] && matches+=("$n"); done
fi
if [[ ${#matches[@]} -eq 0 ]]; then
  for n in "${names[@]}"; do [[ "$n" == *"$query"* ]] && matches+=("$n"); done
fi
shopt -u nocasematch

if [[ ${#matches[@]} -eq 0 ]]; then
  echo "No session matching '$query' - have: $(list)"
  exit 1
fi
if [[ ${#matches[@]} -gt 1 ]]; then
  echo "'$query' is ambiguous: ${matches[*]}"
  exit 1
fi

session="${matches[0]}"

if [[ "$session" == "daily-note" ]]; then
  "$scripts_dir/open-daily-note.sh" || { echo "Could not open the daily note"; exit 1; }
else
  "$scripts_dir/kitty-focus-or-launch.sh" "$sessions_dir/$session.kitty-session" \
    || { echo "Could not open $session"; exit 1; }
fi

echo "$session"
