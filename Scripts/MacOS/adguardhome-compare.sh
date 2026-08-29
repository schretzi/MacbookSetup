#!/usr/bin/env bash
# ============================================================================
# Ask unbound and AdGuard Home the same questions and diff the answers.
# ============================================================================
# The whole point of running both resolvers at once is to find out where they
# disagree before committing to the switch. This queries every name the local
# zones define - plus a few that exercise upstream, DNSSEC and ad-blocking -
# against 127.0.0.2 (unbound) and 127.0.0.3 (AdGuard Home).
#
# The names come from unbound's own conf.d, so a zone added there is covered
# here automatically rather than needing this list maintained by hand.
#
#   Scripts/MacOS/adguardhome-compare.sh           every local name + the probes
#   Scripts/MacOS/adguardhome-compare.sh --upstream only the probes: plain
#                                                  resolution, DNSSEC, ad
#                                                  blocking, and latency
#   Scripts/MacOS/adguardhome-compare.sh foo.kiac  just these names
#
# Exit status is non-zero if any name disagreed, so it can gate the cutover.
# ============================================================================

set -uo pipefail

UNBOUND="127.0.0.2"
ADGUARD="127.0.0.3"
CONF_D="${CONF_D:-/opt/homebrew/etc/unbound/conf.d}"

green() { printf '\033[32m%s\033[0m' "$1"; }
red() { printf '\033[31m%s\033[0m' "$1"; }
yellow() { printf '\033[33m%s\033[0m' "$1"; }

# `dig +short` prints nothing for both NXDOMAIN and NODATA, which are very
# different answers - the first is what a `static` zone should give for an
# undefined name and the second is what it gives for a defined name with no
# record of that type. So report the rcode alongside the data.
answer() {
    local server="$1" name="$2" out rcode data
    out="$(dig +time=2 +tries=1 "@${server}" "${name}" A 2>/dev/null)" || {
        echo "UNREACHABLE"
        return
    }
    rcode="$(printf '%s' "${out}" | sed -n 's/.*status: \([A-Z]*\).*/\1/p' | head -1)"
    data="$(printf '%s' "${out}" | awk '/^;; ANSWER SECTION:/{f=1;next} /^$/{f=0} f' |
        awk '{print $NF}' | sort | paste -sd, -)"
    echo "${rcode:-?}${data:+ ${data}}"
}

# Every owner name unbound answers locally, straight out of conf.d.
local_names() {
    [[ -d ${CONF_D} ]] || return 0
    # shellcheck disable=SC2016
    awk '
        /^[[:space:]]*local-data:/ {
            line = $0
            sub(/^[^"]*"/, "", line)
            sub(/".*$/, "", line)
            split(line, parts, /[[:space:]]+/)
            if (parts[1] != "") print parts[1]
        }
    ' "${CONF_D}"/*.conf 2>/dev/null | sed 's/\.$//' | sort -u
}

# macOS still ships bash 3.2 as /bin/bash, which is what `env bash` finds
# here. That rules out `mapfile`, and makes "${arr[@]}" on an empty array a
# fatal "unbound variable" under `set -u`. Both are worked around below rather
# than by demanding a newer bash: this script has to run on a machine whose DNS
# is currently broken, which is a bad moment to discover a missing dependency.
names=()
probes=()

upstream_only=false
if [[ ${1:-} == "--upstream" ]]; then
    upstream_only=true
    shift
fi

if [[ ${upstream_only} == true ]]; then
    # Evaluating AdGuard Home as a plain resolver, before caring about the
    # local zones. Skips every local name, which is also what you want while
    # unbound has not reloaded its conf.d - those would all be false
    # differences.
    probes=(
        "example.com"      # plain upstream resolution
        "cloudflare.com"   # DNSSEC-signed, should carry AD
        "dnssec-failed.org" # bogus signature, should be SERVFAIL
        "doubleclick.net"  # ad domain - the whole point of AdGuard
        "google.com"
        "github.com"
    )
elif [[ $# -gt 0 ]]; then
    names=("$@")
else
    while IFS= read -r discovered; do
        [[ -n ${discovered} ]] && names+=("${discovered}")
    done < <(local_names)
    # Names that are not local data, chosen to exercise one behaviour each.
    probes=(
        "example.com"                # plain upstream resolution
        "cloudflare.com"             # DNSSEC-signed, should carry AD
        "dnssec-failed.org"          # bogus signature, should be SERVFAIL
        "doubleclick.net"            # ad domain - the whole point of AdGuard
        "nonexistent-zzz.kiac"       # undefined under a `static` zone -> NXDOMAIN
    )
fi

printf '%-46s  %-26s  %-26s\n' "NAME" "unbound (${UNBOUND})" "adguard (${ADGUARD})"
printf '%-46s  %-26s  %-26s\n' "$(printf '%.0s-' {1..46})" \
    "$(printf '%.0s-' {1..26})" "$(printf '%.0s-' {1..26})"

differences=0
check() {
    local name="$1" note="${2:-}" a b mark
    a="$(answer "${UNBOUND}" "${name}")"
    b="$(answer "${ADGUARD}" "${name}")"
    if [[ ${a} == "${b}" ]]; then
        mark="$(green ok)"
    else
        mark="$(red DIFFERS)"
        differences=$((differences + 1))
    fi
    printf '%-46s  %-26s  %-26s  %s %s\n' "${name}" "${a}" "${b}" "${mark}" "${note}"
}

if [[ ${#names[@]} -gt 0 ]]; then
    for name in "${names[@]}"; do
        [[ -n ${name} ]] && check "${name}"
    done
fi

if [[ ${#probes[@]} -gt 0 ]]; then
    echo
    for name in "${probes[@]}"; do
        case "${name}" in
        doubleclick.net) check "${name}" "$(yellow '(a difference here is AdGuard blocking it - expected)')" ;;
        *) check "${name}" ;;
        esac
    done

    # DNSSEC is the one place the two are genuinely not equivalent, so check it
    # explicitly rather than inferring it from the A records above. unbound
    # validates locally; AdGuard Home only forwards the DO bit and relays the
    # upstream's verdict.
    echo
    for server in "${UNBOUND}" "${ADGUARD}"; do
        flags="$(dig +dnssec +time=2 +tries=1 "@${server}" cloudflare.com A 2>/dev/null |
            sed -n 's/.*flags: \([a-z ]*\);.*/\1/p' | head -1)"
        if [[ ${flags} == *" ad"* || ${flags} == "ad "* ]]; then
            printf 'DNSSEC @%-12s %s\n' "${server}" "$(green 'AD flag set')"
        else
            printf 'DNSSEC @%-12s %s\n' "${server}" "$(red "no AD flag (flags: ${flags:-none})")"
        fi
    done
fi

# Latency, because "is it fast enough day to day" is most of what a resolver
# swap actually feels like. Cold cache first (a name neither has seen), then
# the same name again warm.
if [[ ${upstream_only} == true ]]; then
    echo
    probe="$(printf 'x%s.example.com' "$RANDOM")"
    for server in "${UNBOUND}" "${ADGUARD}"; do
        cold="$(dig +time=2 +tries=1 "@${server}" "${probe}" A 2>/dev/null |
            sed -n 's/;; Query time: \([0-9]*\).*/\1/p' | head -1)"
        warm="$(dig +time=2 +tries=1 "@${server}" example.com A >/dev/null 2>&1
        dig +time=2 +tries=1 "@${server}" example.com A 2>/dev/null |
            sed -n 's/;; Query time: \([0-9]*\).*/\1/p' | head -1)"
        printf 'latency @%-12s cold %sms, cached %sms\n' "${server}" "${cold:-?}" "${warm:-?}"
    done
fi

echo
if [[ ${differences} -eq 0 ]]; then
    echo "$(green 'no differences')"
else
    echo "$(red "${differences} name(s) differ") - see above"
fi
exit $((differences > 0))
