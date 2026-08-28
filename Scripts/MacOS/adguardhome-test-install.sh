#!/usr/bin/env bash
# ============================================================================
# Install AdGuard Home locally, next to the running unbound, for evaluation.
# ============================================================================
# This is deliberately a script and not an Ansible role. AdGuard Home is on
# trial: if it wins, the install moves into a Homebrew tap of its own (with a
# GitHub workflow tracking upstream releases) and the wiring becomes a role
# like every other daemon here. Until then nothing in site.yml knows about it,
# so a normal `ansible-playbook site.yml` neither installs nor removes it.
#
# There is no Homebrew formula for AdGuard Home - `brew search adguard` only
# finds the unrelated content-blocker cask - so the release zip is fetched from
# GitHub and pinned by version and SHA-256 here.
#
# What it does:
#   1. download + checksum the pinned release into /opt/adguardhome
#   2. seed AdGuardHome.yaml from Dotfiles/adguardhome/ (once - never again)
#   3. generate upstreams.conf and zones/*.txt from unbound's live conf.d
#   4. install and load com.schretzi.adguardhome + its newsyslog conf
#   5. prove it answers on 127.0.0.3:53 and compare it against unbound
#
# Re-running is safe: the binary is replaced, the generated files are
# regenerated, and the config file is left alone once it exists.
#
#   Scripts/MacOS/adguardhome-test-install.sh              install/update
#   Scripts/MacOS/adguardhome-test-install.sh --uninstall  remove it again
#
# Rolling back is total: nothing about unbound is touched at any point.
# ============================================================================

set -euo pipefail

AGH_VERSION="v0.107.79"
AGH_PREFIX="/opt/adguardhome"
AGH_LABEL="com.schretzi.adguardhome"
AGH_ADDR="127.0.0.3"
AGH_WEB_PORT="3000"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# SHA-256 of the official release zips, per arch, copied from the release's
# published checksums.txt. Verified before anything is unpacked as root, so
# bumping AGH_VERSION means bumping these two lines as well.
case "$(uname -m)" in
arm64)
    AGH_ARCH="darwin_arm64"
    AGH_SHA256="916f50bcc16b452c63ab8289f523a3c637e84933460a0ae7525fec03e31de867"
    ;;
x86_64)
    AGH_ARCH="darwin_amd64"
    AGH_SHA256="a28e30605c306c9002a496e705cffbe8828ef300ba5e85121e9308e623335ffa"
    ;;
*)
    echo "unsupported architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die() {
    printf '\033[1;31merror:\033[0m %s\n' "$*" >&2
    exit 1
}

uninstall() {
    log "unloading ${AGH_LABEL}"
    sudo launchctl bootout "system/${AGH_LABEL}" 2>/dev/null || true
    sudo rm -f "/Library/LaunchDaemons/${AGH_LABEL}.plist"
    sudo rm -f /etc/newsyslog.d/adguardhome.conf
    log "removing ${AGH_PREFIX}"
    sudo rm -rf "${AGH_PREFIX}"
    log "done - unbound was never touched; nothing else to undo"
    exit 0
}

[[ ${1:-} == "--uninstall" ]] && uninstall

# ---------------------------------------------------------------------------
# 0. Preconditions
# ---------------------------------------------------------------------------
[[ $(uname -s) == Darwin ]] || die "macOS only"

# The alias AdGuard Home binds is created at boot by com.schretzi.localhost-alias
# (installed by the unbound role). Without it the daemon cannot bind and
# launchd would just respawn it for ever.
ifconfig lo0 | grep -q "inet ${AGH_ADDR} " ||
    die "${AGH_ADDR} is not on lo0 - run: sudo /usr/local/bin/localhost_alias 2-12 100"

# unbound binds 0.0.0.0:53, so it already holds every loopback alias. A
# specific bind on top of a wildcard bind is exactly what has to work for the
# two to run in parallel; find out now rather than from a crash loop later.
if ! sudo python3 - "$AGH_ADDR" <<'EOF'
import socket, sys
addr = sys.argv[1]
for typ in (socket.SOCK_DGRAM, socket.SOCK_STREAM):
    s = socket.socket(socket.AF_INET, typ)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        s.bind((addr, 53))
    except OSError as e:
        print(f"cannot bind {addr}:53 ({e})", file=sys.stderr)
        sys.exit(1)
    finally:
        s.close()
EOF
then
    die "${AGH_ADDR}:53 is not bindable while unbound holds the wildcard.
Options: point unbound at an explicit interface (interface: 127.0.0.2 in
Dotfiles/unbound/unbound.conf) and restart it, or stop unbound for the test."
fi

# ---------------------------------------------------------------------------
# 1. Binary
# ---------------------------------------------------------------------------
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

url="https://github.com/AdguardTeam/AdGuardHome/releases/download/${AGH_VERSION}/AdGuardHome_${AGH_ARCH}.zip"
log "downloading AdGuard Home ${AGH_VERSION} (${AGH_ARCH})"
curl -fsSL -o "${tmp}/agh.zip" "${url}" || die "download failed: ${url}"

actual="$(shasum -a 256 "${tmp}/agh.zip" | cut -d' ' -f1)"
if [[ -z ${AGH_SHA256} ]]; then
    die "no pinned checksum for ${AGH_ARCH}; this release hashes to ${actual}"
fi
[[ ${actual} == "${AGH_SHA256}" ]] ||
    die "checksum mismatch for ${url}
  expected ${AGH_SHA256}
  actual   ${actual}"
log "checksum ok"

unzip -q -o "${tmp}/agh.zip" -d "${tmp}"

sudo mkdir -p "${AGH_PREFIX}/zones" "${AGH_PREFIX}/data"
sudo install -m 0755 -o root -g wheel "${tmp}/AdGuardHome/AdGuardHome" "${AGH_PREFIX}/AdGuardHome"
log "installed ${AGH_PREFIX}/AdGuardHome"

# ---------------------------------------------------------------------------
# 2. Configuration - seeded once, owned by the runtime from then on
# ---------------------------------------------------------------------------
# AdGuard Home rewrites this file on every change made through the web UI, so
# it is copied rather than linked and never overwritten again. Same reasoning
# as unbound's forwarders.conf and macswitcher's config.yaml.
if [[ -f ${AGH_PREFIX}/AdGuardHome.yaml ]]; then
    log "AdGuardHome.yaml exists - left alone (delete it to re-seed)"
else
    sudo install -m 0640 -o root -g wheel \
        "${REPO_ROOT}/Dotfiles/adguardhome/AdGuardHome.yaml.seed" \
        "${AGH_PREFIX}/AdGuardHome.yaml"
    log "seeded ${AGH_PREFIX}/AdGuardHome.yaml"

    # A config with no users sends the web UI into its first-run wizard, and
    # completing that wizard rewrites the whole file - throwing away everything
    # seeded above. So set the login here instead and never see the wizard.
    #
    # AdGuard Home stores a bcrypt hash; macOS ships htpasswd, which produces
    # exactly that.
    [[ -x /usr/sbin/htpasswd ]] || die "/usr/sbin/htpasswd not found - cannot hash the password"
    printf 'web UI password for user "admin": '
    read -rs password
    echo
    [[ -n ${password} ]] || die "empty password"
    hash="$(/usr/sbin/htpasswd -nbB admin "${password}" | cut -d: -f2)"
    unset password

    sudo /usr/bin/env AGH_HASH="${hash}" python3 - "${AGH_PREFIX}/AdGuardHome.yaml" <<'EOF'
import os, sys, yaml
path = sys.argv[1]
with open(path) as fh:
    conf = yaml.safe_load(fh)
conf["users"] = [{"name": "admin", "password": os.environ["AGH_HASH"]}]
with open(path, "w") as fh:
    yaml.safe_dump(conf, fh, sort_keys=False)
EOF
    log "web UI user 'admin' configured"
fi

# ---------------------------------------------------------------------------
# 3. Zones and upstreams, generated from unbound
# ---------------------------------------------------------------------------
log "translating unbound's conf.d"
sudo "${REPO_ROOT}/Scripts/MacOS/unbound_to_adguard.py" --out-dir "${AGH_PREFIX}"

# ---------------------------------------------------------------------------
# 4. launchd + rotation
# ---------------------------------------------------------------------------
sudo install -m 0644 -o root -g wheel \
    "${REPO_ROOT}/plists/LaunchDaemon/${AGH_LABEL}.plist" \
    "/Library/LaunchDaemons/${AGH_LABEL}.plist"
sudo install -m 0644 -o root -g wheel \
    "${REPO_ROOT}/etc/newsyslog.d/adguardhome.conf" \
    /etc/newsyslog.d/adguardhome.conf
sudo newsyslog -n -f /etc/newsyslog.d/adguardhome.conf >/dev/null ||
    warn "newsyslog refused adguardhome.conf - rotation is not active"

# bootout is asynchronous and KeepAlive keeps respawning the job while it is
# being removed, so wait for the label to disappear before bootstrapping - the
# same dance as Ansible/roles/launchd/tasks/daemon.yml.
if sudo launchctl print "system/${AGH_LABEL}" >/dev/null 2>&1; then
    sudo launchctl bootout "system/${AGH_LABEL}" 2>/dev/null || true
    for _ in $(seq 1 100); do
        sudo launchctl print "system/${AGH_LABEL}" >/dev/null 2>&1 || break
        sleep 0.1
    done
fi
sudo launchctl bootstrap system "/Library/LaunchDaemons/${AGH_LABEL}.plist"
log "loaded ${AGH_LABEL}"

# ---------------------------------------------------------------------------
# 5. Prove it works, and that it agrees with unbound
# ---------------------------------------------------------------------------
for _ in $(seq 1 30); do
    dig +short +time=1 +tries=1 "@${AGH_ADDR}" example.com A >/dev/null 2>&1 && break
    sleep 0.5
done

if ! dig +short +time=2 +tries=1 "@${AGH_ADDR}" example.com A >/dev/null 2>&1; then
    warn "no answer from ${AGH_ADDR}:53 - last lines of the log:"
    sudo tail -n 20 /Library/Logs/adguardhome.err.log 2>/dev/null || true
    sudo tail -n 20 /Library/Logs/adguardhome.log 2>/dev/null || true
    die "AdGuard Home is not answering"
fi

log "AdGuard Home answers on ${AGH_ADDR}:53"
echo
"${REPO_ROOT}/Scripts/MacOS/adguardhome-compare.sh" || true

cat <<EOF

Next steps
  web UI       http://${AGH_ADDR}:${AGH_WEB_PORT}   (user: admin)
  compare      Scripts/MacOS/adguardhome-compare.sh
  point at it  networksetup -setdnsservers Wi-Fi ${AGH_ADDR}
  back to unbound
               networksetup -setdnsservers Wi-Fi 127.0.0.2
  remove       Scripts/MacOS/adguardhome-test-install.sh --uninstall

unbound is untouched and still answering on 127.0.0.2.
EOF
