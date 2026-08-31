#!/usr/bin/env bash
# Opens a URL directly in kitty using w3m, instead of the system default
# browser. Wired up as `open_url_with` in kitty.conf, so both clicked links
# and the URL-hints kitten (kitty_mod+e) route through here - and also
# callable directly, e.g. bound to a shortcut with the URL on the clipboard.
#
# A new kitty OS window is used (not a tab/overlay in the current window):
# w3m takes over the whole terminal (its own keybindings, scrollback,
# rendering), so reusing the calling window would clobber whatever was
# already open there. No extra "close on exit" handling is needed - that's
# kitty's default for any window whose foreground process exits, so the
# window disappears the moment w3m quits (`q`) on its own. This instance
# stays the singleton kitty process (unlike kitty-focus-or-launch.sh, which
# targets a SEPARATE dedicated instance and so needs -o overrides passed to
# a freshly spawned `kitty` process instead - not available on `kitty @ launch`,
# which only ever talks to an already-running instance).
set -euo pipefail

kitty_bin="/Applications/kitty.app/Contents/MacOS/kitty"

url="${1:-}"
if [[ -z "$url" ]]; then
  # No URL passed (e.g. invoked via a bare keybinding): fall back to
  # whatever is on the clipboard, since that's the common case for a
  # manual "open this in w3m" shortcut.
  url="$(pbpaste)"
fi

if [[ -z "$url" ]]; then
  echo "open-in-w3m.sh: no URL given and clipboard is empty" >&2
  exit 1
fi

# `kitty @` targets the CURRENT kitty instance automatically via
# $KITTY_LISTEN_ON, set in the environment of every child process once
# `listen_on`/`allow_remote_control` are enabled globally in kitty.conf -
# no --to/socket path needed here, unlike kitty-focus-or-launch.sh which
# calls into a DIFFERENT (dedicated) instance and has to look its socket up.
"$kitty_bin" @ launch \
  --type=os-window \
  --title "w3m: $url" \
  w3m "$url"
