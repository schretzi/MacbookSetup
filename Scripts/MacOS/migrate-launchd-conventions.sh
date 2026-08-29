#!/usr/bin/env bash
#
# One-shot migration to the conventions in CONVENTIONS.md.
#
# Every background job was renamed to com.schretzi.<name> and every log moved
# to a flat ~/Library/Logs/<name>.log (or /Library/Logs for LaunchDaemons).
# The new identities are installed by the Ansible play; this script removes the
# *old* ones, which the play cannot do because it has never heard of them.
#
# What it does:
#   1. boots out and deletes the agents/daemons under their old labels
#   2. rewrites the daemon labels in ~/.config/macswitcher/config.yaml
#   3. archives the old log files and directories
#
# What it deliberately does NOT do: install anything. Run the Ansible play
# afterwards (it renders the new plists, installs /etc/newsyslog.d/*.conf and
# runs `<tool> service install` for the three Go CLIs).
#
# Dry run by default. Pass --apply to actually make the changes.
#
#   ./migrate-launchd-conventions.sh              # show what would happen
#   ./migrate-launchd-conventions.sh --apply      # do it
#
# Safe to re-run: every step checks whether it still applies.

set -euo pipefail

APPLY=false
[[ "${1:-}" == "--apply" ]] && APPLY=true

GUI="gui/$(id -u)"
STAMP="$(date +%Y%m%d-%H%M%S)"
ARCHIVE="$HOME/Library/Logs/pre-convention-migration-$STAMP"

# Old label -> the domain it lived in. The renamed jobs are reinstalled by
# Ansible, so here we only tear the old identity down.
USER_AGENTS=(
  org.schretzi.omt-daemon
  org.schretzi.offlineimap-sync
  com.macswitcher.proxy
  com.corp.vpn
)
SYSTEM_DAEMONS=(
  com.kiac.vmnet-nat-refresh
  org.localhost.alias
)

# Old log paths, flat files and directories alike.
OLD_LOGS=(
  "$HOME/Library/Logs/omt-daemon.log"
  "$HOME/Library/Logs/omt-refresh.log"
  "$HOME/Library/Logs/offlineimap-sync.log"
  "$HOME/Library/Logs/corp-vpn.out.log"
  "$HOME/Library/Logs/corp-vpn.err.log"
  "$HOME/Library/Logs/KerberosKeepAlive"
  "$HOME/Library/Logs/macswitcher"
)

say()  { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
run() {
  if $APPLY; then
    "$@"
  else
    printf '   would run: %s\n' "$*"
  fi
}

if ! $APPLY; then
  say "DRY RUN - nothing will be changed. Re-run with --apply to commit."
fi

# ---------------------------------------------------------------------------
step "1. Unload and remove the old-labelled LaunchAgents"

for label in "${USER_AGENTS[@]}"; do
  plist="$HOME/Library/LaunchAgents/$label.plist"
  loaded=false
  launchctl print "$GUI/$label" >/dev/null 2>&1 && loaded=true

  if ! $loaded && [[ ! -f "$plist" ]]; then
    say "   $label: already gone"
    continue
  fi

  if [[ "$label" == "com.corp.vpn" ]]; then
    say "   $label: NOTE - this drops the VPN connection until Ansible reinstalls it."
  fi

  if $loaded; then
    say "   $label: booting out"
    run launchctl bootout "$GUI/$label"
    # bootout is asynchronous; wait for the label to actually disappear so a
    # later bootstrap of the new label cannot race it.
    if $APPLY; then
      for _ in $(seq 1 100); do
        launchctl print "$GUI/$label" >/dev/null 2>&1 || break
        sleep 0.1
      done
    fi
  fi
  [[ -f "$plist" ]] && { say "   $label: removing $plist"; run rm -f "$plist"; }
done

# ---------------------------------------------------------------------------
step "2. Unload and remove the old-labelled LaunchDaemons (needs sudo)"

# A dry run must not sit waiting for a sudo password, so probe with `sudo -n`
# and fall back to "assume loaded if the plist is there" when we cannot ask.
sudo_probe() {
  if sudo -n true 2>/dev/null; then
    sudo -n launchctl print "system/$1" >/dev/null 2>&1
  else
    [[ -f "/Library/LaunchDaemons/$1.plist" ]]
  fi
}

for label in "${SYSTEM_DAEMONS[@]}"; do
  plist="/Library/LaunchDaemons/$label.plist"
  loaded=false
  sudo_probe "$label" && loaded=true

  if ! $loaded && [[ ! -f "$plist" ]]; then
    say "   $label: already gone"
    continue
  fi
  if $loaded; then
    say "   $label: booting out"
    run sudo launchctl bootout "system/$label"
    if $APPLY; then
      for _ in $(seq 1 100); do
        sudo launchctl print "system/$label" >/dev/null 2>&1 || break
        sleep 0.1
      done
    fi

  fi
  [[ -f "$plist" ]] && { say "   $label: removing $plist"; run sudo rm -f "$plist"; }
done

# ---------------------------------------------------------------------------
step "3. Update the daemon labels in ~/.config/macswitcher/config.yaml"

MSCONF="$HOME/.config/macswitcher/config.yaml"
if [[ -f "$MSCONF" ]]; then
  if grep -qE 'org\.schretzi\.omt-daemon|com\.corp\.vpn' "$MSCONF"; then
    say "   rewriting labels (backup: $MSCONF.pre-migration)"
    if $APPLY; then
      cp "$MSCONF" "$MSCONF.pre-migration"
      # `macswitcher observe` reads these; leaving them stale would show every
      # renamed job as "not loaded".
      sed -i '' \
        -e 's/org\.schretzi\.omt-daemon/com.schretzi.omt/' \
        -e 's/com\.corp\.vpn/com.schretzi.corp-vpn/' \
        "$MSCONF"
    else
      grep -nE 'org\.schretzi\.omt-daemon|com\.corp\.vpn' "$MSCONF" | sed 's/^/   would rewrite: /'
    fi
  else
    say "   already migrated"
  fi
else
  say "   no config at $MSCONF, skipping"
fi

# ---------------------------------------------------------------------------
step "4. Archive the old log files"

found=false
for path in "${OLD_LOGS[@]}"; do
  [[ -e "$path" ]] || continue
  found=true
  say "   $path -> $ARCHIVE/"
  run mkdir -p "$ARCHIVE"
  run mv "$path" "$ARCHIVE/"
done
$found || say "   nothing left to archive"

# ---------------------------------------------------------------------------
step "Done"
if $APPLY; then
  cat <<'EOF'

The old identities are gone. Nothing is running yet - now install the new ones:

    cd MacbookSetup/Ansible
    ansible-playbook site.yml --ask-become-pass

That renders the renamed plists, installs /etc/newsyslog.d/*.conf, and runs
`service install` for kerberoskeepalive, macswitcher and omt.

Then verify:

    launchctl list | grep com.schretzi
    kerberoskeepalive service status
    macswitcher service status
    omt service status
    ls -la ~/Library/Logs/*.log
EOF
else
  say ""
  say "Re-run with --apply to commit these changes."
fi
