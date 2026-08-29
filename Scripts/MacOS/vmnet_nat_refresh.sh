#!/bin/sh
# Keep the kiac vmnet subnet's pf NAT rule pointed at whichever interface
# currently has the default route.
#
# Background: LocalKubernetes' cluster node VMs (and, transitively, their
# pods via Cilium masquerade) get internet egress through a pf nat-anchor
# ("com.kiac.vmnet-nat") that translates 192.168.64.0/24 out one specific
# host interface. That interface is not stable — switching between Wi-Fi
# and wired Ethernet (or VPN) changes which one owns the default route —
# so a hardcoded interface silently breaks egress for every pod behind it
# until this script re-runs.
#
# Deployed to /usr/local/bin/vmnet_nat_refresh (root:wheel 0755) by the
# Ansible role "pf_vmnet_nat" and invoked automatically by
# /Library/LaunchDaemons/com.schretzi.vmnet-nat-refresh.plist, which watches
# for network reconfiguration events (see the plist's WatchPaths on
# com.apple.networkextension's preference store) and re-runs this on
# every network change. Safe to re-run manually at any time, e.g. right
# after switching networks if you don't want to wait for the watcher:
#   sudo /usr/local/bin/vmnet_nat_refresh

set -eu

ANCHOR_FILE=/etc/pf.anchors/com.kiac.vmnet-nat
EXT_IF=$(route get default 2>/dev/null | awk '/interface: /{print $2}')

if [ -z "$EXT_IF" ]; then
    echo "vmnet_nat_refresh: no default route found, nothing to do" >&2
    exit 0
fi

CURRENT_IF=""
if [ -f "$ANCHOR_FILE" ]; then
    CURRENT_IF=$(awk -F'"' '/^ext_if = /{print $2}' "$ANCHOR_FILE" 2>/dev/null || true)
fi

if [ "$CURRENT_IF" = "$EXT_IF" ]; then
    # Already correct - still reload in case pf itself was reset/disabled,
    # but no need to rewrite the file.
    pfctl -f /etc/pf.conf >/dev/null 2>&1 || true
    pfctl -e >/dev/null 2>&1 || true
    exit 0
fi

cat > "$ANCHOR_FILE" << EOF
ext_if = "${EXT_IF}"
# NAT the vmnet subnet out whichever interface currently has the default
# route. Managed by vmnet_nat_refresh (roles/pf_vmnet_nat) - do not edit
# by hand, it is rewritten automatically on network changes.
nat on \$ext_if from 192.168.64.0/24 to any -> (\$ext_if)
EOF

pfctl -f /etc/pf.conf
pfctl -e >/dev/null 2>&1 || true

echo "vmnet_nat_refresh: NAT now via ${EXT_IF} (was: ${CURRENT_IF:-none})"
