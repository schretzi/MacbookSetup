#!/bin/sh
# Make AdGuard Home pick up a changed zone file, and prove that it did.
#
# Zone files under /etc/adguardhome/zones are written by whoever owns the zone:
# the `adguardhome` Ansible role installs the ones that come from a repository,
# and LocalKubernetes' host_dns re-renders kiac.txt whenever the vmnet hands
# out new addresses. Writing the file is not the hard part - making AdGuard
# Home serve it is, and that is what this script exists for.
#
#   host_dns  ->  /etc/adguardhome/zones/kiac.txt  ->  [this]
#
# Deployed to /usr/local/bin/adguardhome_zones_refresh (root:wheel 0755) by the
# Ansible role "adguardhome".
#   sudo -n /usr/local/bin/adguardhome_zones_refresh
#
# ---------------------------------------------------------------------------
# Restarting AdGuard Home is NOT enough, which is the trap this script exists
# to close.
# ---------------------------------------------------------------------------
# A filter list whose URL is an absolute path is still a *filter list*: AdGuard
# Home keeps its own copy under data/filters/<id>.txt and that copy - not the
# path in the config - is what it loads. It does not read the path at startup
# at all. So after a zone change the sequence "write the file, kickstart the
# daemon" leaves it serving the previous addresses, with nothing in any log to
# say so.
#
# Measured: gitea moved from 192.168.64.2 to .10, the zone file on disk said
# .10, AdGuard Home was restarted 12 seconds after the file was written - and
# `dig @127.0.0.3 gitea.kiac` still answered .2, with blocked_response_ttl as
# the TTL, i.e. straight out of a stale rewrite rule. Eleven of nineteen names
# were wrong that way.
#
# The supported way out is the API: POST /control/filtering/refresh makes
# AdGuard Home re-read the local path and rewrite its cached copy, live, with
# no restart and no cache loss. Measured - source file changed, refresh posted,
# nothing restarted:
#
#   {"updated":1}                       exactly the one list that changed
#   data/filters/1001.txt               rewritten, new mtime, new content
#   gitea.kiac  192.168.64.10 -> 10.99.99.99   without a restart
#
# That needs a credential, so there is a fallback for when it is not there:
# write the cached copy directly and restart. See sync_cache below.
#
# And because "did it pick the file up" is exactly the thing that failed
# silently, the answers are verified against the rules afterwards.

set -eu

OUT_DIR=/etc/adguardhome
FILTER_CACHE=/opt/adguardhome/data/filters
LABEL=com.schretzi.adguardhome
CONF=/opt/adguardhome/AdGuardHome.yaml
RESOLVER=127.0.0.3

# AdGuard Home has no permission model - every account in `users:` is a full
# admin - so this is credential isolation, not privilege isolation: the script
# does not carry the human's password and can be rotated on its own.
# Created once, by hand; see Setup.md -> DNS.
API_USER=zonesync
API_KEYCHAIN_SERVICE="adguardhome api"

# Readable by an unprivileged process on purpose: `macswitcher observe` reads
# upstreams.conf as the user to report what is being forwarded.
chmod 0644 "$OUT_DIR/upstreams.conf" 2>/dev/null || true
chmod 0644 "$OUT_DIR"/zones/*.txt 2>/dev/null || true

zone="$OUT_DIR/zones/kiac.txt"

# Copy the generated zones over AdGuard Home's cached copies, then restart it.
#
# This took three wrong guesses to pin down, so the measurement is written out
# here rather than the theory. With data/filters/1001.txt moved aside and the
# daemon restarted:
#
#   gitea.kiac      -> (no answer)      the file was NOT recreated
#   registry.kiac   -> (no answer)      and nothing was read from
#                                       /etc/adguardhome/zones/kiac.txt
#
# So AdGuard Home does not re-read a local rule list's path at startup at all.
# data/filters/<id>.txt *is* the source it loads; the `url` in the config is
# only where a *refresh* would go looking, and a refresh happens on the update
# interval or through the HTTP API, neither of which is reachable from a
# non-interactive root script (the API needs the admin password).
#
# Hence: write the file AdGuard Home actually reads. The generated zone is
# copied over the cached copy verbatim - `!` comment lines are valid in a rule
# list, so nothing has to be stripped - and the source file under
# /etc/adguardhome/zones stays current too, so a real refresh on the update
# interval reads the same content rather than reverting.
#
# The id -> source mapping comes out of AdGuard Home's own config: the cached
# copy of the filter with id N is data/filters/N.txt. The filters block is
# machine-written and has a stable shape; url and id are buffered per list item
# so their order within an item does not matter. A mis-parse costs nothing
# worse than not updating a file, which verify() then reports.
#
# The previous copy is kept until the zone verifies, and put back if it does
# not - never leaving the machine with a broken .kiac zone.
SUFFIX=".aside-$$"

local_filters() {
    awk -v prefix="^${OUT_DIR}/zones/" '
        function flush() { if (id != "" && url ~ prefix) print id "\t" url; url = ""; id = "" }
        /^filters:/                   { inblock = 1; next }
        /^[^[:space:]]/               { if (inblock) { flush(); inblock = 0 } }
        inblock && /^[[:space:]]*-[[:space:]]/ { flush() }
        inblock && /[[:space:]]url:[[:space:]]/ { line = $0; sub(/^[^:]*:[[:space:]]*/, "", line); url = line }
        inblock && /[[:space:]]id:[[:space:]]/  { line = $0; sub(/^[^:]*:[[:space:]]*/, "", line); id = line }
        END                           { if (inblock) flush() }
    ' "$CONF"
}

sync_cache() {
    [ -d "$FILTER_CACHE" ] || {
        echo "adguardhome_zones_refresh: $FILTER_CACHE does not exist" >&2
        return 1
    }
    local_filters | while IFS="$(printf '\t')" read -r id src; do
        [ -f "$src" ] || continue
        cached="$FILTER_CACHE/${id}.txt"
        if [ -f "$cached" ]; then
            cmp -s "$src" "$cached" && continue
            mv "$cached" "${cached}${SUFFIX}"
        fi
        echo "adguardhome_zones_refresh: writing $src into $cached"
        cp "$src" "$cached"
        # Match what AdGuard Home writes there itself.
        chmod 0600 "$cached"
    done
}

# The web UI's address, so moving it (as happened when gitea needed :3000
# back) does not silently break this. Falls back to the current value.
api_base() {
    addr=$(awk '
        /^http:/     { inblock = 1; next }
        /^[^[:space:]]/ { inblock = 0 }
        inblock && /^[[:space:]]*address:[[:space:]]/ {
            line = $0; sub(/^[^:]*:[[:space:]]*/, "", line); print line; exit
        }
    ' "$CONF" 2>/dev/null)
    echo "http://${addr:-127.0.0.3:3053}"
}

# Ask AdGuard Home to re-read its lists. This is the good path: no restart, so
# the DNS cache survives. Returns non-zero if the credential is missing or the
# call does not come back 2xx, and the caller then falls back to sync_cache.
refresh_via_api() {
    pass=$(security find-generic-password -s "$API_KEYCHAIN_SERVICE" \
        -a "$API_USER" -w /Library/Keychains/System.keychain 2>/dev/null || true)
    if [ -z "$pass" ]; then
        echo "adguardhome_zones_refresh: no API credential in the System keychain" >&2
        return 1
    fi

    code=$(curl -s -o /dev/null -w '%{http_code}' -m 30 \
        -u "${API_USER}:${pass}" -X POST -H 'Content-Type: application/json' \
        -d '{"whitelist":false}' "$(api_base)/control/filtering/refresh" || true)
    if [ "$code" != "200" ]; then
        echo "adguardhome_zones_refresh: filtering/refresh returned ${code:-nothing}" >&2
        return 1
    fi

    echo "adguardhome_zones_refresh: refreshed through the API, no restart"
    # The rewrite of the cached copy is not instantaneous.
    sleep 2
    return 0
}

restore() {
    for f in "$FILTER_CACHE"/*"$SUFFIX"; do
        [ -f "$f" ] || continue
        mv "$f" "${f%$SUFFIX}"
    done
}

discard() {
    rm -f "$FILTER_CACHE"/*"$SUFFIX" 2>/dev/null || true
}

reload() {
    sync_cache || return 1

    launchctl kickstart -k "system/${LABEL}"

    # Wait for the resolver to come back before asking it anything.
    i=0
    while [ "$i" -lt 40 ]; do
        /usr/bin/dig +short +time=2 +tries=1 "@${RESOLVER}" example.com A >/dev/null 2>&1 && return 0
        i=$((i + 1))
        sleep 0.5
    done
    echo "adguardhome_zones_refresh: ${LABEL} did not come back after the restart" >&2
    return 1
}

# Every `||name^$dnsrewrite=NOERROR;A;addr` rule in the kiac zone has to come
# back out of the resolver as that address. Prints the disagreements and
# returns non-zero. Only the kiac zone is checked - it is the one whose
# addresses move; the overlays' zones are hand-written and static.
#
# A file, not a variable: the loop body runs in a subshell because it is the
# right-hand side of a pipe, so anything it assigns is gone by the time the
# pipeline ends.
verify() {
    [ -f "$zone" ] || return 0

    bad=$(mktemp)
    sed -n 's/^||\([^^]*\)\^\$dnsrewrite=NOERROR;A;\(.*\)$/\1 \2/p' "$zone" |
        while read -r name want; do
            got=$(/usr/bin/dig +short +time=2 +tries=1 "@${RESOLVER}" "$name" A 2>/dev/null | head -1)
            [ "$got" = "$want" ] ||
                printf '%s answers %s, the zone says %s\n' "$name" "${got:-nothing}" "$want" >>"$bad"
        done

    if [ -s "$bad" ]; then
        sed 's/^/adguardhome_zones_refresh: /' "$bad" >&2
        rm -f "$bad"
        return 1
    fi
    rm -f "$bad"
    return 0
}

# Verification is the main event, not an afterthought, and it runs
# unconditionally. Checking only when the zone file had changed would have
# missed exactly the bug this guards against: the file can be current on disk
# while AdGuard Home serves the previous one out of its filter cache, and
# nothing says so. Escalate only as far as needed:
#
#   1. API refresh    no restart, cache kept - the normal path
#   2. write + restart the fallback when there is no credential or the API is
#                     unreachable; costs the DNS cache
#
# Anything still disagreeing after both is a real failure: put the previous
# cached lists back rather than leave a half-applied zone.
if verify; then
    discard
    exit 0
fi

echo "adguardhome_zones_refresh: the served zone is stale - refreshing" >&2
if refresh_via_api && verify; then
    discard
    echo "adguardhome_zones_refresh: zone verified"
    exit 0
fi

echo "adguardhome_zones_refresh: falling back to rewriting the cached lists" >&2
reload || true
if verify; then
    discard
    echo "adguardhome_zones_refresh: restarted ${LABEL}, zone verified"
    exit 0
fi

echo "adguardhome_zones_refresh: AdGuard Home is still not serving the current zone" >&2
echo "adguardhome_zones_refresh: putting the cached lists back and restarting" >&2
restore
launchctl kickstart -k "system/${LABEL}"
exit 1
