#!/bin/sh
# Re-grabs the keyboard for kanata after the Mac wakes from sleep.
#
# Why this exists: kanata's macOS backend (via the Karabiner VirtualHIDDevice
# driver) only enumerates and grabs keyboard devices once, at startup. It has
# no hotplug/rescan of its own, so a keyboard that was not present when
# com.kanata.daemon last started - e.g. the external Bluetooth keyboard, gone
# while working elsewhere without it - is never grabbed once it reconnects.
# Cable <-> Bluetooth switches on the same keyboard hit the same gap. The only
# fix is restarting the daemon; see `kanata_restart` in
# ~/.zsh/aliases/general for the manual equivalent of what this automates, and
# Dotfiles/Keybindings/kanata.md for the CLI to inspect state
# (`kanata --list`, `launchctl print system/com.kanata.daemon`, the
# /Library/Logs/kanata.*.log files).
#
# This script is load-bearing beyond device re-grabbing, in two ways that are
# easy to undo by accident:
#   - The kickstart hands kanata fresh log fds, which is what bounds the
#     newsyslog rename trap described in etc/newsyslog.d/kanata.conf.
#   - The guard below asks `launchctl print`, i.e. "is the job LOADED", not
#     "is it running". That is deliberate: `macswitcher observe` stops kanata
#     with `launchctl bootout`, which unloads it, so a deliberate stop is
#     respected here. Loosening the guard to also revive a merely stopped job
#     would make that stop silently undo itself at the next wake.
#
# Invoked by sleepwatcher (`-w` callback) from the com.schretzi.kanata-wake
# LaunchDaemon on every system wake. Runs as root - same user as
# com.kanata.daemon - so no sudo is needed here, unlike the interactive alias.
#
# The delay gives Bluetooth time to actually reconnect after wake; kickstarting
# kanata before that would just repeat the exact failure this exists to fix.
# Harmless to run on every wake even when nothing changed: kanata's own
# startup delay (kanata.kbd's -n is not set) briefly drops key events, cheap
# compared to a keyboard staying unmapped for the rest of the session.
set -eu

LABEL=com.kanata.daemon
DELAY=5

if ! /bin/launchctl print "system/${LABEL}" >/dev/null 2>&1; then
    # Not installed/loaded on this machine - nothing to refresh.
    exit 0
fi

sleep "$DELAY"

echo "$(date '+%Y-%m-%d %H:%M:%S') kanata_wake_refresh: kickstarting ${LABEL} after wake"
/bin/launchctl kickstart -k "system/${LABEL}"
