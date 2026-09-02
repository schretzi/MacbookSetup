#!/bin/sh
# Keeps Firefox-family browsers trusting the System keychain's roots, by
# setting the preference the ImportEnterpriseRoots policy sets:
#
#   Certificates -> ImportEnterpriseRoots
#   Preferences Affected: security.enterprise_roots.enabled
#   https://mozilla.github.io/policy-templates/
#
# The Ansible role writes that policy into each browser's .app bundle, which is
# the documented mechanism and is what a fresh profile picks up. This script
# exists for what happens *after* the role runs, and deliberately does not
# touch a bundle itself.
#
# Why not: since macOS 13, App Management protects application bundles, and it
# is enforced by TCC rather than by file permissions. A process only gets to
# write inside /Applications if it holds that grant - being root is not
# sufficient. `ansible-playbook` inherits the grant from the terminal you run
# it in, so the role works; a launchd job has no such parent and is refused
# with EPERM:
#
#   .../Zen.app/.../policies.json: Operation not permitted
#
# The grant cannot be scripted either (TCC's database is SIP-protected), and
# for a shell script TCC attributes access to the interpreter - so buying the
# permission would mean granting Full Disk Access to /bin/sh, i.e. to every
# shell script on the machine.
#
# The profile is the way out. user.js lives in the user's own Application
# Support directory, needs no privileges and no TCC, is re-read on every
# startup, and survives a browser update by construction: an updater replaces
# the bundle and never touches profiles. That inverts the original problem -
# the bundle copy is the one that needs repairing after an update, and the
# profile copy is the one that cannot be lost.
#
# Runs as the user, from a LaunchAgent. A LaunchDaemon would be wrong twice
# over: profiles are per-user, and root buys nothing here.
set -eu

pref='user_pref("security.enterprise_roots.enabled", true);'

# Profile parents, not bundles. Firefox, Developer Edition and Nightly share
# the Firefox directory and are distinguished by profile, so this cannot be
# derived one-to-one from the list of installed .app bundles.
for support in \
    "$HOME/Library/Application Support/Firefox" \
    "$HOME/Library/Application Support/zen" \
    "$HOME/Library/Application Support/LibreWolf" \
    "$HOME/Library/Application Support/Waterfox" \
    "$HOME/Library/Application Support/Floorp"
do
    [ -d "$support/Profiles" ] || continue

    for profile in "$support/Profiles"/*/
    do
        [ -d "$profile" ] || continue
        userjs="${profile}user.js"

        # Rebuild rather than append, so a stale line setting the pref to
        # false is corrected instead of being shadowed by a second one. Any
        # unrelated user.js content is preserved.
        tmp=$(mktemp "${TMPDIR:-/tmp}/user.js.XXXXXX")
        if [ -f "$userjs" ]; then
            grep -Fv 'security.enterprise_roots.enabled' "$userjs" >"$tmp" || true
        fi
        printf '%s\n' "$pref" >>"$tmp"

        if [ -f "$userjs" ] && cmp -s "$tmp" "$userjs"; then
            rm -f "$tmp"
            continue
        fi

        # Atomic, so a browser reading user.js during startup never sees a
        # half-written file.
        chmod 600 "$tmp"
        mv "$tmp" "$userjs"
        printf 'set enterprise roots pref: %s\n' "$userjs"
    done
done
