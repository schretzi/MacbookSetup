#!/usr/bin/env bash
# Verify that every cask the Brewfiles declare is actually present on disk.
#
# `brew bundle` only checks Homebrew's own receipts. That is not the same
# question as "is the software installed", and the gap is not theoretical:
#
#   * A **pkg cask** (Tailscale, for one) downloads an installer and then runs
#     it with sudo. If that step is skipped or cancelled, the Caskroom receipt
#     is written anyway - so `brew bundle` reports "Using tailscale-app" forever
#     while nothing is installed and no pkgutil receipt exists.
#   * An **app cask** whose .app was dragged to the Trash keeps its receipt too.
#
# So this checks the artifacts instead:
#   app artifacts -> the .app exists in /Applications or ~/Applications
#   pkg artifacts -> macOS has the pkgutil receipt the cask declares
#
# Exit status is non-zero when something is missing, so it can gate a run.

set -uo pipefail

BREW="${HOMEBREW_PREFIX:-/opt/homebrew}/bin/brew"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

command -v "$BREW" >/dev/null 2>&1 || { echo "brew not found at $BREW" >&2; exit 1; }

# Only Brewfiles, and only cask lines. Strip any tap prefix (user/tap/token).
grep -hE '^[[:space:]]*cask ' "$REPO"/Brewfiles/*.brew 2>/dev/null \
  | sed -E 's/.*cask "([^"]+)".*/\1/' | sed 's|.*/||' | sort -u > "$TMP/declared"
"$BREW" list --cask 2>/dev/null | sort -u > "$TMP/installed"

# Asking brew about a token it does not know aborts the whole JSON call, so
# only query the intersection; the difference is reported separately.
comm -12 "$TMP/installed" "$TMP/declared" > "$TMP/check"
comm -13 "$TMP/installed" "$TMP/declared" > "$TMP/absent"

if [ -s "$TMP/check" ]; then
    "$BREW" info --cask --json=v2 $(tr '\n' ' ' < "$TMP/check") > "$TMP/casks.json" 2>/dev/null
else
    echo '{"casks":[]}' > "$TMP/casks.json"
fi

python3 - "$TMP/casks.json" "$TMP/absent" <<'PY'
import json, os, subprocess, sys

casks = json.load(open(sys.argv[1])).get("casks", [])
absent = [l.strip() for l in open(sys.argv[2]) if l.strip()]
receipts = set(subprocess.run(["/usr/sbin/pkgutil", "--pkgs"],
                              capture_output=True, text=True).stdout.split())

broken, ok = [], 0
for c in casks:
    apps, pkgids = [], []
    for a in c.get("artifacts") or []:
        if not isinstance(a, dict):
            continue
        if "app" in a:
            apps += [x for x in a["app"] if isinstance(x, str)]
        for u in a.get("uninstall") or []:
            if isinstance(u, dict) and "pkgutil" in u:
                v = u["pkgutil"]
                pkgids += v if isinstance(v, list) else [v]
    if apps:
        if any(os.path.exists("/Applications/" + a)
               or os.path.exists(os.path.expanduser("~/Applications/" + a)) for a in apps):
            ok += 1
        else:
            broken.append((c["token"], "app missing from disk: " + ", ".join(apps)))
    elif pkgids:
        if any(p in receipts for p in pkgids):
            ok += 1
        else:
            broken.append((c["token"],
                           "pkg never installed, no receipt: " + ", ".join(pkgids)))
    else:
        ok += 1   # font/binary/other artifact - receipt is the best signal we have

print(f"  verified present : {ok}")
print(f"  not installed    : {len(absent)}" + (f"  ({', '.join(absent)})" if absent else ""))
if broken:
    print(f"\n  BROKEN ({len(broken)}) - brew reports these installed, the system disagrees:")
    for t, m in sorted(broken):
        print(f"    {t:<24} {m}")
    print("\n  Fix with: brew reinstall --cask <token>")
    print("  A pkg cask will ask for your password - that installer step is")
    print("  exactly what got skipped.")
sys.exit(1 if broken else 0)
PY
