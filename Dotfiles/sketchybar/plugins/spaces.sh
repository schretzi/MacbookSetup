#!/bin/bash
# Rebuilds every space.desk<N> item from two yabai queries. Runs once at
# startup (sketchybarrc) and again on every "space_windows_change" trigger,
# which yabairc fires on window/space/display signals - see the
# "yabai -m signal --add ... space_windows_change" lines there.
#
# One process for the whole bar, not one per space: querying yabai and
# sourcing the (1877-line) icon map once per refresh is materially cheaper
# than doing it ten times, and avoids ten near-simultaneous yabai queries
# racing each other when several signals fire back to back.
set -uo pipefail

source "$CONFIG_DIR/helpers/icon_map.sh"

FOCUSED_BG=0xff5e81ac
FOCUSED_ICON=0xff2e3440
IDLE_ICON=0xff88909f

spaces_json="$(yabai -m query --spaces 2>/dev/null)" || exit 0
windows_json="$(yabai -m query --windows 2>/dev/null)" || exit 0

for label in desk1 desk2 desk3 desk4 desk5 desk6 desk7 desk8 desk9 desk10; do
  space="$(jq -c --arg l "$label" '.[] | select(.label == $l)' <<<"$spaces_json")"
  if [[ -z "$space" ]]; then
    # Space got removed/relabeled in Mission Control; make that visible
    # instead of silently showing stale state.
    sketchybar --set "space.$label" icon="$label" icon.color=0xffbf616a \
               background.color=0x00ffffff label.drawing=off
    continue
  fi

  index="$(jq -r '.index' <<<"$space")"
  focused="$(jq -r '."has-focus"' <<<"$space")"

  # One glyph per distinct app on this space, in the order yabai reports
  # windows (most-recently-interacted first), deduplicated.
  apps="$(jq -r --argjson i "$index" '[.[] | select(.space == $i) | .app] | unique | .[]' <<<"$windows_json")"
  label_text=""
  if [[ -n "$apps" ]]; then
    while IFS= read -r app; do
      __icon_map "$app"
      label_text+="${icon_result} "
    done <<<"$apps"
    label_text="${label_text% }"
  fi

  number="${label#desk}"
  if [[ "$focused" == "true" ]]; then
    sketchybar --set "space.$label" \
               icon="$number" icon.color="$FOCUSED_ICON" \
               background.color="$FOCUSED_BG" \
               label.drawing=on label="$label_text"
  else
    sketchybar --set "space.$label" \
               icon="$number" icon.color="$IDLE_ICON" \
               background.color=0x00ffffff \
               label.drawing=on label="$label_text"
  fi
done
