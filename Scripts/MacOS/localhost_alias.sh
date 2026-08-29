#!/bin/sh
# Add extra loopback addresses to lo0.
#
# macOS ships lo0 with 127.0.0.1 only, and mDNSResponder already owns port 53
# on it. unbound therefore listens on 127.0.0.2, and the k3d/cluster.local
# zones in Dotfiles/unbound/ resolve to 127.0.0.3 ... 127.0.0.12 and
# 127.0.0.100. Those addresses have to exist before anything can bind them.
#
# Deployed to /usr/local/bin/localhost_alias (root:wheel 0755) by the Ansible
# role "unbound" and started by /Library/LaunchDaemons/com.schretzi.localhost-alias.plist.
#
# Usage: localhost_alias <octet|from-to> [...]
#   localhost_alias 2-12 100   -> 127.0.0.2 .. 127.0.0.12 and 127.0.0.100

set -eu

if [ "$#" -eq 0 ]; then
    echo "usage: $0 <octet|from-to> [...]" >&2
    exit 64
fi

add_alias() {
    # ifconfig fails if the alias already exists; that is not an error for us
    ifconfig lo0 alias "127.0.0.$1" up 2>/dev/null || true
}

for arg in "$@"; do
    case "$arg" in
        *-*)
            from=${arg%-*}
            to=${arg#*-}
            i=$from
            while [ "$i" -le "$to" ]; do
                add_alias "$i"
                i=$((i + 1))
            done
            ;;
        *)
            add_alias "$arg"
            ;;
    esac
done
