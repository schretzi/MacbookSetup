#!/usr/bin/env bash
# Focuses a dedicated kitty instance showing TODAY's Obsidian daily note,
# creating the note (from Templates/daily.md) if it doesn't exist yet.
#
# Each day gets its own generated session file
# (~/.cache/kitty-sessions/daily-note-YYYY-MM-DD.kitty-session, not tracked
# in git - it's fully derived, regenerated fresh each run). That's what
# makes "always today's note" work correctly: kitty-focus-or-launch.sh
# detects an existing dedicated instance by matching the exact session
# file path, so a window left open from a previous day (a different
# filename) is never mistaken for today's - it's just left alone in the
# background, and a new dedicated instance opens for today instead.
set -euo pipefail

# Hardcoded rather than $HOME: this is also invoked by kanata's root
# LaunchDaemon via `cmd`, which does not set HOME for its children - with
# `set -u` above, an unset $HOME aborts the script on this very line and
# "^" + d silently does nothing. See the same note in
# kitty-focus-or-launch.sh for why a ${HOME:-fallback} isn't the answer.
home="/Users/schretzi"

# Defaults to the Work vault, same as notes.lua's M.root(): daily notes
# should land in Work unless something explicitly asks for Private, so a
# work-context note never leaks into the personal vault by accident.
vault_dir="$home/Brain/Work"
daily_dir="$vault_dir/10-Daily"
template="$vault_dir/60-Meta/Templates/daily.md"
# Layout must stay in sync with neobean's lua/config/modules/notes.lua and with
# `format` in the vault's .obsidian/daily-notes.json:
#   10-Daily/YYYY/MM-Mon/YYYY-MM-DD-Weekday.md
# The weekday in the filename is what makes a work week easy to scan.
today="$(date +%Y-%m-%d)"
year="$(date +%Y)"
month="$(date +%m)"
month_abbr="$(date +%b)"
weekday="$(date +%A)"
note_dir="$daily_dir/$year/$month-$month_abbr"
note="$note_dir/$today-$weekday.md"

session_dir="$home/.cache/kitty-sessions"
session_file="$session_dir/daily-note-$today.kitty-session"

mkdir -p "$note_dir" "$session_dir"

if [[ ! -f "$note" ]]; then
  # Render to a temporary file and only install it once it has content.
  # Invoked from kanata's root LaunchDaemon, `-f "$template"` can pass while
  # the read is still denied on the iCloud-backed vault, and redirecting
  # straight into "$note" then left behind an empty note that the user could
  # not fix without deleting it first.
  tmp_note="$(mktemp "$note_dir/.daily-note.XXXXXX")"
  trap 'rm -f "${tmp_note:-}" "${tmp_session:-}"' EXIT

  if [[ -r "$template" ]] && sed "s/{{date}}/$today/g" "$template" > "$tmp_note" && [[ -s "$tmp_note" ]]; then
    mv "$tmp_note" "$note"
  else
    printf '# %s\n' "$today" > "$note"
  fi

  # Same reason: a note created by the root daemon would otherwise be owned by
  # root and read-only for the account that actually edits it
  if [[ "$(id -u)" -eq 0 ]]; then
    chown schretzi:staff "$note"
  fi
fi

# Regenerated on every run, never reused: the file is fully derived from
# "$note", so a session file left over from an earlier run would keep pointing
# at whatever path that run computed. Writing through a temporary file and
# renaming also lets a user run replace one the root daemon created earlier.
#
# Auto-revealing the note's directory in Neo-tree at startup (via nvim's
# -c flag) was tried and dropped: it consistently rendered a truncated
# sidebar (title + path + one item) no matter how its timing was tweaked,
# in a way that never reproduced when triggered interactively afterwards.
# Use <leader>R (neotree.lua) to open it on demand instead.
tmp_session="$(mktemp "$session_dir/.daily-note.XXXXXX")"
trap 'rm -f "${tmp_note:-}" "${tmp_session:-}"' EXIT

cat > "$tmp_session" <<EOF
cd $vault_dir
launch --title "Daily Note" /bin/zsh -c "~/.config/neobean/bin/neobean '$note'"
focus
focus_os_window
EOF

mv "$tmp_session" "$session_file"
if [[ "$(id -u)" -eq 0 ]]; then
  chown schretzi:staff "$session_file"
fi

"$home/.config/kitty/scripts/kitty-focus-or-launch.sh" "$session_file"
