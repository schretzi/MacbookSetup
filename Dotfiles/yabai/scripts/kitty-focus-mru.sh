#!/bin/bash
# Keep focus on a kitty session when another one quits.
#
# The problem, measured: kitty sessions are separate application instances
# (see Dotfiles/Keybindings/kitty.md), so quitting one is an application
# terminating, not a window closing. When that empties its space, macOS does
# not stay put - it switches to another space and focuses whatever it finds
# there. Observed 22ms after window_destroyed: focus on Zen, two spaces away.
# Finder is simply the version of this you get when nothing better is around.
#
# yabai cannot answer "the last active kitty" on its own - it exposes `recent`,
# but that is the previously focused *window*, which right after a destroy is
# as likely to be the corpse or whatever macOS just grabbed. So this records
# the order itself:
#
#   record    on window_focused - push that id onto an MRU list, if the
#             window belongs to a kitty process
#   restore   on window_destroyed - if the dead id was one we recorded, focus
#             the newest recorded id that is still alive
#
# The signals deliberately carry NO app= filter, and that is the whole trick.
# make-session-apps.sh gives every session its own .app bundle with a *copy* of
# kitty's launcher named after the session, so Cmd-Tab can show distinct
# entries - which means yabai reports the app as "Work Network", not "kitty",
# and the binary is called "Work Network" too. Filtering on app="^kitty$"
# therefore matched only a raw kitty instance and missed every real session.
# Ownership is decided here instead, from the executable path.
#
# State lives under ~/.local/state, which CONVENTIONS.md §2a defines as safe
# to delete: losing it costs one wrong focus, and the next focus rebuilds it.

set -uo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/yabai"
MRU="${STATE_DIR}/kitty-mru"
# Trace of what restore decided and whether it held. Signals run detached with
# no terminal, so this is the only way to see why a focus went where it did.
# Truncated on every restore, so it never grows.
LOG="${STATE_DIR}/kitty-focus.log"
# Enough to survive a few sessions closing back to back; the list is filtered
# against live windows on use, so a long tail of dead ids costs nothing.
KEEP=20

yabai_bin=$(command -v yabai || echo /opt/homebrew/bin/yabai)
jq_bin=$(command -v jq || echo /usr/bin/jq)

# Where make-session-apps.sh writes its per-session bundles. Both markers are
# needed: the real install for a plain `kitty`, the sessions directory for the
# wrappers, whose executable is named after the session rather than kitty.
SESSION_APPS="Applications/Kitty Sessions/"

# Focus a window and keep it focused against a late override by macOS.
# Verifies rather than assumes: re-issues the focus while something else holds
# it, up to a fixed budget, so a slow decision on the OS side cannot win.
focus_and_hold() {
  # Two attempts, not five. When macOS has decided to switch space it wins
  # regardless, and re-issuing five times only thrashes focus for a visible
  # second before losing anyway. Two catches the common late override without
  # turning a lost race into a light show.
  local target="${1:-}" attempt current
  for attempt in 1 2; do
    "$yabai_bin" -m window --focus "$target" 2>/dev/null
    sleep 0.12
    current=$("$yabai_bin" -m query --windows --window 2>/dev/null \
      | "$jq_bin" -r '.id // empty')
    echo "      try$attempt: wanted=$target got=$current" >> "${LOG:-/dev/null}"
    [[ "$current" == "$target" ]] || continue
    # Held through one further interval means the OS has settled.
    sleep 0.12
    current=$("$yabai_bin" -m query --windows --window 2>/dev/null \
      | "$jq_bin" -r '.id // empty')
    [[ "$current" == "$target" ]] && return 0
  done
  return 1
}

is_kitty_pid() {
  local pid="${1:-}" exe
  [[ -z "$pid" ]] && return 1
  exe=$(ps -p "$pid" -o comm= 2>/dev/null) || return 1
  [[ "$exe" == *"/kitty.app/Contents/MacOS/"* ]] && return 0
  [[ "$exe" == *"$SESSION_APPS"*".app/Contents/MacOS/"* ]] && return 0
  return 1
}

record() {
  local id="${YABAI_WINDOW_ID:-}"
  [[ -z "$id" ]] && return 0

  # Fires for every window focus now that there is no app filter, so establish
  # ownership before touching state.
  local pid
  pid=$("$yabai_bin" -m query --windows --window "$id" 2>/dev/null \
    | "$jq_bin" -r '.pid // empty')
  is_kitty_pid "$pid" || return 0

  mkdir -p "$STATE_DIR"
  # Newest first, with the previous entry for this id removed so re-focusing a
  # window moves it up rather than adding a duplicate.
  local existing=""
  [[ -f "$MRU" ]] && existing=$(grep -vxF "$id" "$MRU" 2>/dev/null || true)
  # `awk NF && !seen` drops blank lines and any duplicate that slipped in: an
  # empty `remaining` in restore used to write a bare newline, and those
  # accumulate into a file of blanks that the restore loop then walks past.
  { echo "$id"; [[ -n "$existing" ]] && echo "$existing"; } \
    | awk 'NF && !seen[$0]++' | head -n "$KEEP" > "${MRU}.tmp"
  mv -f "${MRU}.tmp" "$MRU"
}

restore() {
  local dead="${YABAI_WINDOW_ID:-}"
  [[ -f "$MRU" ]] || return 0

  # The process is already gone, so it cannot be inspected - but if we recorded
  # the id then it was one of ours, which is the same answer. Windows we never
  # recorded are left entirely alone.
  grep -qxF "$dead" "$MRU" 2>/dev/null || return 0

  {
    echo "=== $(date +%T) restore dead=$dead"
    echo "    mru: $(tr '\n' ' ' < "$MRU")"
    echo "    (candidates are snapshotted before the sleep)"
  } > "$LOG"

  # Drop it now so a rapid second close does not chase a corpse.
  local remaining
  remaining=$(grep -vxF "$dead" "$MRU" 2>/dev/null | awk 'NF && !seen[$0]++' || true)
  # An empty list must truncate the file, not write a blank line into it.
  if [[ -n "$remaining" ]]; then
    printf '%s\n' "$remaining" > "${MRU}.tmp"
  else
    : > "${MRU}.tmp"
  fi
  mv -f "${MRU}.tmp" "$MRU"

  # Take the candidate order NOW, and iterate this snapshot rather than the
  # file. Measured failure: during the sleep below, macOS focuses its own
  # choice, that fires window_focused, record promotes it to the top of the
  # MRU, and a restore that re-read the file then "restored" focus to exactly
  # the window it was supposed to be overriding. The list has to be the one
  # from before the window died.
  local candidates="$remaining"

  # macOS makes its own focus decision after the destroy - usually within
  # ~20ms, but measured as late as several hundred ms, after a correction had
  # already been applied and was then overridden. So this does not fire once
  # and hope: it picks a target, then holds it (see focus_and_hold), re-issuing
  # the focus until it sticks or the budget runs out.
  sleep 0.15

  # Every id in the MRU is already known to be a kitty window - record put it
  # there - so liveness is the only question, and it must NOT be re-tested with
  # .app=="kitty": a session bundle reports its own name, so that filter would
  # declare every real session dead and fall through to the raw instance.
  local live
  live=$("$yabai_bin" -m query --windows 2>/dev/null \
    | "$jq_bin" -r '.[].id') || return 0
  [[ -z "$live" ]] && return 0

  local id
  while read -r id; do
    [[ -z "$id" || "$id" == "$dead" ]] && continue
    if grep -qxF "$id" <<<"$live"; then
      echo "    target=$id ($("$yabai_bin" -m query --windows --window "$id" 2>/dev/null | "$jq_bin" -r '.app // "?"'))" >> "$LOG"
      if focus_and_hold "$id"; then
        echo "    HELD $id" >> "$LOG"
        return 0
      fi
      echo "    lost $id" >> "$LOG"
    fi
  done <<<"$candidates"

  echo "    gave up; focus left to macOS" >> "$LOG"
  # Nothing recorded survived. Leave macOS alone rather than yanking focus to
  # an unrelated window: with no sessions left there is no "last session" to
  # return to, and guessing would be worse than the default.
  return 0
}

case "${1:-}" in
  record)  record ;;
  restore) restore ;;
  *) echo "usage: ${0##*/} record|restore" >&2; exit 64 ;;
esac
