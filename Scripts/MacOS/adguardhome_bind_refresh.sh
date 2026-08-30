#!/bin/sh
# Keep AdGuard Home's dns.bind_hosts on explicit addresses, following the kiac
# vmnet gateway as it comes and goes.
#
# Why this exists: AdGuard Home cannot serve the kiac VMs from a wildcard bind.
# `bind_hosts: [0.0.0.0]` makes Go open a single AF_INET6 dual-stack socket
# (`lsof` shows "IPv6 UDP *:53"). TCP is fine over that socket, but for UDP
# dnsproxy sets the reply's source address from the control message it read
# with the query - and for an IPv4-mapped client that is not on loopback, the
# reply never leaves the host. Measured on this machine, AdGuard Home v0.107.79:
#
#   container (192.168.64.2) -> 192.168.64.1:53  TCP   full answer
#   container (192.168.64.2) -> 192.168.64.1:53  UDP   silence
#   host                     -> 127.0.0.3:53     UDP   answers
#
# Every container and every kiac node VM takes `nameserver 192.168.64.1` from
# the runtime and asks over UDP, so the whole vmnet had no working resolver.
# Naming the addresses explicitly gives each one its own AF_INET socket, and
# the reply source is then the address the socket is bound to.
#
# The catch that made the wildcard attractive in the first place: 192.168.64.1
# only exists while the vmnet bridge is up, i.e. while at least one container
# runs - and AdGuard Home refuses to start on an address it cannot bind. So the
# bind list is not static. This script is the thing that keeps it correct:
#
#   vmnet up    ->  127.0.0.1 127.0.0.2 127.0.0.3 192.168.64.1
#   vmnet down  ->  127.0.0.1 127.0.0.2 127.0.0.3
#
# and it restarts AdGuard Home only when the list actually changes. Loopback
# always comes first so that a boot with no containers still has a resolver.
# 127.0.0.1/.2 are in the list because the wildcard used to cover them:
# .2 is the address the previous resolver served for years and things still
# point at it.
#
# Deployed to /usr/local/bin/adguardhome_bind_refresh (root:wheel 0755) by the
# Ansible role "adguardhome" and run by
# /Library/LaunchDaemons/com.schretzi.adguardhome-bind.plist. Safe to re-run at
# any time; it is a no-op unless the bind list is wrong. Run it by hand right
# after starting the first container if you do not want to wait for the timer:
#   sudo -n /usr/local/bin/adguardhome_bind_refresh

set -eu

CONF=/opt/adguardhome/AdGuardHome.yaml
BACKUP=/opt/adguardhome/AdGuardHome.yaml.bind-backup
EDITOR_PY=/usr/local/libexec/adguardhome_bind_hosts.py
LABEL=com.schretzi.adguardhome
GATEWAY=192.168.64.1
LOOPBACK="127.0.0.1 127.0.0.2 127.0.0.3"
PROBE=example.com

if [ ! -f "$CONF" ]; then
    # AdGuard Home is not installed - nothing to keep in sync. Not an error:
    # the daemon may simply have been uninstalled while this job stayed loaded.
    exit 0
fi

[ -f "$EDITOR_PY" ] || {
    echo "adguardhome_bind_refresh: $EDITOR_PY is missing" >&2
    exit 1
}

# Any python3 will do - the editor deliberately imports nothing outside the
# standard library. The first cut of this used PyYAML and died under Ansible's
# become with ModuleNotFoundError: PyYAML is installed in
# ~/Library/Python/*/site-packages, i.e. in *my* user site-packages, which root
# cannot see. A daemon that runs as root at boot must not depend on a module
# that only exists for one login account.
PYTHON=""
for candidate in /usr/bin/python3 /opt/homebrew/bin/python3 /usr/local/bin/python3; do
    [ -x "$candidate" ] && { PYTHON="$candidate"; break; }
done
[ -n "$PYTHON" ] || {
    echo "adguardhome_bind_refresh: no python3 found" >&2
    exit 1
}

desired="$LOOPBACK"
if ifconfig 2>/dev/null | grep -q "inet ${GATEWAY} "; then
    desired="$desired $GATEWAY"
fi

# Exit 10 means "changed", 0 means "already correct", anything else is an error.
apply() {
    "$PYTHON" "$EDITOR_PY" "$CONF" "$BACKUP" $1
}

answers() {
    /usr/bin/dig +short +time=2 +tries=1 "@$1" "$PROBE" A >/dev/null 2>&1
}

rc=0
apply "$desired" || rc=$?
[ "$rc" = 0 ] && exit 0
[ "$rc" = 10 ] || exit "$rc"

launchctl kickstart -k "system/${LABEL}"

# Prove it came back. The interesting failure is the vmnet disappearing between
# the ifconfig check above and the bind below - AdGuard Home then cannot bind
# 192.168.64.1, exits, and launchd respawn-loops it with no resolver anywhere
# on the machine. Restore the byte-exact backup rather than leave that standing;
# editing our way back out would be one more chance to get the file wrong.
i=0
while [ "$i" -lt 40 ]; do
    answers 127.0.0.3 && exit 0
    i=$((i + 1))
    sleep 0.5
done

echo "adguardhome_bind_refresh: no answer after binding [$desired] - restoring" >&2
[ -f "$BACKUP" ] && cp "$BACKUP" "$CONF"
launchctl kickstart -k "system/${LABEL}"
exit 1
