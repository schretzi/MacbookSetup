#!/usr/bin/env bash
# ============================================================================
# Hand DNS over from unbound to AdGuard Home, for good.
# ============================================================================
# The trial phase ran both side by side (unbound on 127.0.0.2, AdGuard Home on
# 127.0.0.3). This ends it: unbound is stopped and durably disabled, and
# AdGuard Home takes over the wildcard bind so it answers everywhere unbound
# used to - including the vmnet gateway 192.168.64.1, which is what the kiac
# node VMs ask.
#
# Two unbound jobs get stopped, not one:
#
#   system/net.unbound              this repo's LaunchDaemon, the one actually
#                                   serving 127.0.0.2
#   gui/<uid>/homebrew.mxcl.unbound Homebrew's own LaunchAgent, which has been
#                                   sitting in a permanent respawn loop - it
#                                   runs unbound as your user, which cannot
#                                   bind port 53, so launchd retried forever
#
# `launchctl disable` is what makes it durable: unlike bootout, it survives a
# reboot. Ansible is the other half - set enable_unbound: false in
# group_vars/all.yml or the next site.yml run reinstalls and restarts it.
#
# Everything is verified before it is called done, and if AdGuard Home does not
# come back answering, unbound is restored automatically. The machine is never
# left without a resolver.
#
#   Scripts/MacOS/adguardhome-cutover.sh          hand over
#   Scripts/MacOS/adguardhome-cutover.sh --revert give DNS back to unbound
# ============================================================================

set -euo pipefail

AGH_PREFIX="/opt/adguardhome"
AGH_LABEL="com.schretzi.adguardhome"
AGH_CONF="${AGH_PREFIX}/AdGuardHome.yaml"
AGH_GENERATED="/etc/adguardhome"
UNBOUND_LABEL="net.unbound"
BREW_UNBOUND="homebrew.mxcl.unbound"
PROBE="example.com"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die() {
    printf '\033[1;31merror:\033[0m %s\n' "$*" >&2
    exit 1
}

uid="$(id -u)"

# --- sudo up front, with a message that names the problem ------------------
if ! sudo -n true 2>/dev/null; then
    [[ -t 0 ]] || die "this needs root and there is no terminal to ask on.
Run it from an interactive shell (in Claude Code, prefix with '!')."
    log "asking for sudo up front"
    sudo -v || die "could not obtain root"
fi

stop_unbound() {
    log "stopping and disabling ${UNBOUND_LABEL} (system)"
    sudo launchctl bootout "system/${UNBOUND_LABEL}" 2>/dev/null || true
    # disable survives a reboot; bootout alone does not.
    sudo launchctl disable "system/${UNBOUND_LABEL}" 2>/dev/null || true

    log "stopping and disabling ${BREW_UNBOUND} (user agent, was respawn-looping)"
    launchctl bootout "gui/${uid}/${BREW_UNBOUND}" 2>/dev/null || true
    launchctl disable "gui/${uid}/${BREW_UNBOUND}" 2>/dev/null || true
    # brew's own bookkeeping, so `brew services list` agrees with reality and
    # a later `brew upgrade` does not quietly reload it.
    if command -v brew >/dev/null 2>&1; then
        brew services stop unbound >/dev/null 2>&1 || true
    fi
}

start_unbound() {
    sudo launchctl enable "system/${UNBOUND_LABEL}" 2>/dev/null || true
    sudo launchctl bootstrap system "/Library/LaunchDaemons/${UNBOUND_LABEL}.plist" 2>/dev/null ||
        sudo launchctl kickstart -k "system/${UNBOUND_LABEL}" 2>/dev/null || true
}

# Rewrite dns.bind_hosts in place. Done in Python against the real YAML rather
# than with sed, because AdGuard Home rewrites this file itself and its
# formatting is not ours to predict.
set_bind_hosts() {
    local hosts_json="$1"
    sudo /usr/bin/env HOSTS="${hosts_json}" python3 - "${AGH_CONF}" <<'EOF'
import json, os, sys, yaml

path = sys.argv[1]
with open(path) as fh:
    conf = yaml.safe_load(fh)

conf.setdefault("dns", {})["bind_hosts"] = json.loads(os.environ["HOSTS"])

with open(path, "w") as fh:
    yaml.safe_dump(conf, fh, sort_keys=False)
EOF
}

answers() {
    dig +short +time=2 +tries=1 "@$1" "${PROBE}" A >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# --revert: give DNS back to unbound
# ---------------------------------------------------------------------------
if [[ ${1:-} == "--revert" ]]; then
    log "putting AdGuard Home back on the loopback alias only"
    set_bind_hosts '["127.0.0.3"]'
    sudo launchctl kickstart -k "system/${AGH_LABEL}" || true
    log "re-enabling unbound"
    start_unbound
    for _ in $(seq 1 30); do
        answers 127.0.0.2 && break
        sleep 0.5
    done
    answers 127.0.0.2 && log "unbound answers on 127.0.0.2 again" ||
        warn "unbound is not answering yet - check /Library/Logs/unbound.err.log"
    cat <<EOF

Remember to point the machine back at it:
  networksetup -setdnsservers Wi-Fi 127.0.0.2
and set enable_unbound back to true in Ansible/group_vars/all.yml.
EOF
    exit 0
fi

# ---------------------------------------------------------------------------
# 1. Preconditions
# ---------------------------------------------------------------------------
# `sudo test`, not `[[ -f ]]`: AdGuard Home forces its work directory to 0700
# at startup, so an unprivileged existence check reports "missing" for a file
# that is plainly there - the directory cannot even be traversed.
sudo test -f "${AGH_CONF}" ||
    die "${AGH_CONF} not found - run adguardhome-test-install.sh first"

sudo launchctl print "system/${AGH_LABEL}" >/dev/null 2>&1 ||
    die "${AGH_LABEL} is not loaded - run adguardhome-test-install.sh first"

answers 127.0.0.3 ||
    die "AdGuard Home is not answering on 127.0.0.3 - fix that before handing DNS to it"
log "AdGuard Home is healthy on 127.0.0.3"

# ---------------------------------------------------------------------------
# 1b. Put the generated inputs somewhere readable
# ---------------------------------------------------------------------------
# AdGuard Home chmods its own work directory to 0700 at startup, so anything
# under /opt/adguardhome is unreadable to a non-root process - and `macswitcher
# observe` reads the upstream file as your user to show what is being
# forwarded. The generated inputs therefore live in /etc/adguardhome.
#
# Written unconditionally rather than guarded on the old files still existing:
# regenerating is cheap and idempotent, and a guard on file presence gets this
# wrong the moment the files were created by hand or a previous run was
# interrupted half way.
log "generating upstreams and zones into ${AGH_GENERATED}"
sudo mkdir -p "${AGH_GENERATED}/zones"
sudo chmod 0755 "${AGH_GENERATED}" "${AGH_GENERATED}/zones"
sudo "${REPO_ROOT}/Scripts/MacOS/unbound_to_adguard.py" --out-dir "${AGH_GENERATED}"
sudo chmod 0644 "${AGH_GENERATED}/upstreams.conf" 2>/dev/null || true
sudo chmod 0644 "${AGH_GENERATED}"/zones/*.txt 2>/dev/null || true

# Repoint AdGuard Home only if its config still names the old location. Driven
# by the config rather than by which files happen to exist, so that generating
# the new files first (or re-running this script) cannot skip the rewrite and
# leave AdGuard Home reading a directory that is about to be deleted.
if sudo grep -qE "${AGH_PREFIX}/(upstreams\.conf|zones/)" "${AGH_CONF}"; then
    log "repointing AdGuard Home from ${AGH_PREFIX} to ${AGH_GENERATED}"
    sudo python3 - "${AGH_CONF}" "${AGH_PREFIX}" "${AGH_GENERATED}" <<'PYEOF'
import sys, yaml

path, old_root, new_root = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as fh:
    conf = yaml.safe_load(fh)

dns = conf.setdefault("dns", {})
if isinstance(dns.get("upstream_dns_file"), str):
    dns["upstream_dns_file"] = dns["upstream_dns_file"].replace(
        old_root + "/upstreams.conf", new_root + "/upstreams.conf"
    )

for flt in conf.get("filters") or []:
    url = flt.get("url")
    if isinstance(url, str) and url.startswith(old_root + "/zones/"):
        flt["url"] = url.replace(old_root + "/zones/", new_root + "/zones/")

flt_conf = conf.setdefault("filtering", {})
flt_conf["safe_fs_patterns"] = [
    p.replace(old_root + "/zones/", new_root + "/zones/") if isinstance(p, str) else p
    for p in (flt_conf.get("safe_fs_patterns") or [])
]

with open(path, "w") as fh:
    yaml.safe_dump(conf, fh, sort_keys=False)
PYEOF
    sudo rm -rf "${AGH_PREFIX}/zones" "${AGH_PREFIX}/upstreams.conf"
fi

# ---------------------------------------------------------------------------
# 2. Stop unbound, then take the wildcard
# ---------------------------------------------------------------------------
stop_unbound

# unbound has to be gone before AdGuard Home can take 0.0.0.0:53, and launchctl
# bootout is asynchronous.
for _ in $(seq 1 40); do
    pgrep -qf "sbin/unbound -d" || break
    sleep 0.25
done
if pgrep -qf "sbin/unbound -d"; then
    warn "an unbound process is still alive; AdGuard Home may fail to take the wildcard"
fi

# 0.0.0.0 mirrors unbound's `interface: 0.0.0.0`. It is not as open as it looks:
# dns.allowed_clients still restricts answers to loopback and the kiac vmnet,
# exactly like unbound's access-control did. Binding the wildcard rather than
# naming addresses is deliberate - 192.168.64.1 only exists while the vmnet is
# up, and naming an address that is missing is what makes a resolver refuse to
# start at boot.
log "binding AdGuard Home to 0.0.0.0 (allowed_clients still restricts who is answered)"
set_bind_hosts '["0.0.0.0"]'

sudo launchctl kickstart -k "system/${AGH_LABEL}"

# ---------------------------------------------------------------------------
# 3. Verify, or put unbound back
# ---------------------------------------------------------------------------
ok=false
for _ in $(seq 1 40); do
    if answers 127.0.0.3 && answers 127.0.0.2; then
        ok=true
        break
    fi
    sleep 0.5
done

if [[ ${ok} != true ]]; then
    warn "AdGuard Home did not come back on the wildcard - rolling back to unbound"
    set_bind_hosts '["127.0.0.3"]'
    sudo launchctl kickstart -k "system/${AGH_LABEL}" || true
    start_unbound
    sudo tail -n 20 /Library/Logs/adguardhome.log 2>/dev/null || true
    die "cutover aborted, unbound restored. Nothing else was changed."
fi

log "AdGuard Home answers on 127.0.0.3 and on 127.0.0.2 (the old unbound address)"

# The vmnet gateway only exists while kiac is up. When it is, prove the VMs
# have a resolver; when it is not, say so rather than implying it was checked.
if ifconfig 2>/dev/null | grep -q "inet 192.168.64.1 "; then
    if answers 192.168.64.1; then
        log "AdGuard Home answers on the vmnet gateway 192.168.64.1 - kiac VMs are covered"
    else
        warn "192.168.64.1 exists but AdGuard Home does not answer there"
    fi
else
    log "vmnet is down, so 192.168.64.1 could not be checked - it is covered by the wildcard once kiac starts"
fi

sudo -n /usr/bin/dscacheutil -flushcache 2>/dev/null || true
sudo -n /usr/bin/killall -HUP mDNSResponder 2>/dev/null || true

cat <<EOF

$(log "done - AdGuard Home now serves every address unbound used to")

Still to do, and not done here on purpose:

  Ansible   set enable_unbound: false in Ansible/group_vars/all.yml, or the
            next site.yml run reinstalls and restarts unbound.
            Careful: that role also installs com.schretzi.localhost-alias,
            which creates the 127.0.0.2-.12 aliases AdGuard Home's web UI and
            resolver addresses rely on. It stays loaded, but stops being
            managed. See BACKLOG.md.

  Rollback  Scripts/MacOS/adguardhome-cutover.sh --revert
EOF
