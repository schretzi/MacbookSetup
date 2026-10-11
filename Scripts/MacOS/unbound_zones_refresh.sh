#!/bin/sh
# Make unbound pick up a changed conf.d file, and prove that it did.
#
# Conf files under /opt/homebrew/etc/unbound/conf.d are written by whoever
# owns the zone: the `unbound` Ansible role installs the ones that come from
# a repository, and LocalKubernetes' host_dns re-renders kiac.conf whenever
# its compose services change.
#
#   host_dns  ->  conf.d/kiac.conf  ->  [this]
#
# Deployed to /usr/local/bin/unbound_zones_refresh (root:wheel 0755) by the
# Ansible role "unbound".
#   sudo -n /usr/local/bin/unbound_zones_refresh
#
# ---------------------------------------------------------------------------
# Why this is simpler than AdGuard Home's equivalent script
# ---------------------------------------------------------------------------
# AdGuard Home keeps its own copy of every "zone" (filter list) under
# data/filters/<id>.txt and never re-reads the configured path except
# through its HTTP API or a restart that also discards the DNS cache - so
# that script had to translate a changed file into that cache by hand before
# it could even consider restarting.
#
# unbound has no such cache: conf.d/*.conf IS what it reads, every time it
# (re)starts. There is nothing to translate and nothing to put back on
# failure - a restart either comes up serving the file on disk, or it
# doesn't. So this script only has three steps: validate, restart, verify.

set -eu

CONFD=/opt/homebrew/etc/unbound/conf.d
UNBOUND_CONF=/opt/homebrew/etc/unbound/unbound.conf
LABEL=sh.brew.unbound
RESOLVER=127.0.0.2
CHECKCONF=/opt/homebrew/sbin/unbound-checkconf

# Fail loudly before touching the running daemon: a typo in a rendered zone
# must not crash-loop a resolver every machine depends on.
if ! "$CHECKCONF" "$UNBOUND_CONF" >/tmp/unbound_checkconf.out 2>&1; then
    echo "unbound_zones_refresh: unbound.conf does not parse, not restarting:" >&2
    sed 's/^/unbound_zones_refresh: /' /tmp/unbound_checkconf.out >&2
    rm -f /tmp/unbound_checkconf.out
    exit 1
fi
rm -f /tmp/unbound_checkconf.out

launchctl kickstart -k "system/${LABEL}"

# Wait for the resolver to come back before asking it anything.
i=0
while [ "$i" -lt 40 ]; do
    /usr/bin/dig +short +time=2 +tries=1 "@${RESOLVER}" example.com A >/dev/null 2>&1 && break
    i=$((i + 1))
    sleep 0.5
done
if [ "$i" -ge 40 ]; then
    echo "unbound_zones_refresh: ${LABEL} did not come back after the restart" >&2
    exit 1
fi

# Every `local-data: "name [ttl] [class] A addr"` line across conf.d/ has to
# come back out of the resolver as that address. The record's RR type always
# sits directly before its rdata regardless of whether ttl/class are present,
# so arr[NF-1]=="A" with arr[NF] the address picks out A records only -
# rather than assuming a fixed field count. Printed as disagreements rather
# than asserted one at a time, so a single bad line doesn't hide the rest.
bad=$(mktemp)
grep -hoE 'local-data:[[:space:]]*"[^"]+"' "$CONFD"/*.conf 2>/dev/null |
    sed -E 's/^local-data:[[:space:]]*"(.*)"$/\1/' |
    awk '$(NF-1) == "A" { print $1, $NF }' |
    while read -r name addr; do
        got=$(/usr/bin/dig +short +time=2 +tries=1 "@${RESOLVER}" "$name" A 2>/dev/null | tail -1)
        [ "$got" = "$addr" ] ||
            printf '%s answers %s, the zone says %s\n' "$name" "${got:-nothing}" "$addr" >>"$bad"
    done

if [ -s "$bad" ]; then
    echo "unbound_zones_refresh: ${LABEL} restarted but is not serving every local-data line:" >&2
    sed 's/^/unbound_zones_refresh: /' "$bad" >&2
    rm -f "$bad"
    exit 1
fi
rm -f "$bad"

echo "unbound_zones_refresh: restarted ${LABEL}, zones verified"
exit 0
