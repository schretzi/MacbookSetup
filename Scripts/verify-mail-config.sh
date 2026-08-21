#!/usr/bin/env bash
# Verify the rendered mail configuration against a captured baseline.
#
# The five mail configs are generated from mail_accounts, so the question that
# matters after any change is "do the tools still resolve exactly what they did
# before?". This compares parsed/resolved state, not bytes, and finishes with
# live checks that the OAuth path actually works.
#
#   Scripts/verify-mail-config.sh baseline   capture the current state
#   Scripts/verify-mail-config.sh check      compare against it
#
# Everything is regenerated on every run - never compare against a stale file.

set -uo pipefail

DIR="${MAIL_VERIFY_DIR:-$HOME/.cache/macbooksetup/mail-verify}"
MODE="${1:-check}"
# Derived from the generated configs, never hardcoded - the account list is
# personal data and belongs in an overlay, not in this repository.
# (read loops rather than mapfile: macOS ships bash 3.2, which has no mapfile)
ACCOUNTS=()
while IFS= read -r a; do ACCOUNTS+=("$a"); done < <(
    sed -n 's/^account \([^ ]*\)$/\1/p' ~/.msmtprc 2>/dev/null)
ACCOUNTS+=(default)
OMT_LOGINS=()
while IFS= read -r a; do OMT_LOGINS+=("$a"); done < <(
    sed -n 's/^ *\([^ :]*\):$/\1/p' ~/.config/omt/config.yaml 2>/dev/null | grep '@')

capture() {
    local out=$1
    mkdir -p "$out"

    # offlineimap: raw INI, no interpolation (%(accountname)s is not a variable)
    python3 - "$out/offlineimap.json" <<'PY'
import configparser, json, os, sys
c = configparser.RawConfigParser(); c.optionxform = str
c.read(os.path.expanduser("~/.config/offlineimap/config"))
with open(sys.argv[1], "w") as fh:
    json.dump({s: dict(c[s]) for s in c.sections()}, fh, indent=1, sort_keys=True)
    fh.write("\n")
PY

    # omt: parsed YAML, so quoting style differences do not register as changes.
    # The system python has no pyyaml; fall back to uv rather than skipping,
    # because a silently absent artifact reads as "no change" and hides a break.
    local pyyaml='
import json, os, sys, yaml
with open(sys.argv[1], "w") as fh:
    json.dump(yaml.safe_load(open(os.path.expanduser("~/.config/omt/config.yaml"))),
              fh, indent=1, sort_keys=True)
    fh.write("\n")
'
    if ! python3 -c 'import yaml' 2>/dev/null; then
        if command -v uv >/dev/null 2>&1; then
            uv run --with pyyaml -q python -c "$pyyaml" "$out/omt.json"
        else
            echo "  WARNING: no pyyaml and no uv - omt config not compared" >&2
        fi
    else
        python3 -c "$pyyaml" "$out/omt.json"
    fi

    # Parsing proves structure; omt reading it proves it is actually usable.
    if ! omt token "${OMT_LOGINS[0]}" >/dev/null 2>&1; then
        echo "  WARNING: omt cannot load its config: $(omt token "${OMT_LOGINS[0]}" 2>&1 | head -1)" >&2
    fi

    # `msmtp -P` runs passwordeval, so omt's transient token-expiry warnings end
    # up interleaved here. Those describe keychain state, not configuration, and
    # change on their own every hour - drop them or every check reports a diff.
    : > "$out/msmtp.txt"
    for a in "${ACCOUNTS[@]}"; do
        echo "--- $a" >> "$out/msmtp.txt"
        msmtp -P -a "$a" 2>&1 \
            | grep -vE '^(loaded|ignoring|WARNING:|omt: )' >> "$out/msmtp.txt"
    done

    : > "$out/notmuch.txt"
    for k in database.path user.primary_email user.other_email user.name; do
        echo "$k = $(notmuch config get "$k" 2>/dev/null | tr '\n' ';')" >> "$out/notmuch.txt"
    done

    neomutt -F ~/.config/mutt/muttrc \
        -Q folder -Q from -Q sendmail -Q real_name -Q spool_file -Q record \
        > "$out/mutt.txt" 2>/dev/null
}

if [ "$MODE" = baseline ]; then
    capture "$DIR/baseline"
    echo "baseline captured in $DIR/baseline"
    exit 0
fi

if [ ! -d "$DIR/baseline" ]; then
    echo "no baseline in $DIR/baseline - run: $0 baseline" >&2
    exit 1
fi

rm -rf "$DIR/current"
capture "$DIR/current"

rc=0
for f in offlineimap.json omt.json msmtp.txt notmuch.txt mutt.txt; do
    [ -e "$DIR/baseline/$f" ] || continue
    if diff -q "$DIR/baseline/$f" "$DIR/current/$f" >/dev/null 2>&1; then
        printf '  %-16s identical\n' "${f%.*}"
    else
        printf '  %-16s DIFFERS\n' "${f%.*}"
        diff "$DIR/baseline/$f" "$DIR/current/$f" | head -20
        rc=1
    fi
done

# A config can parse and still be unusable - exercise the real OAuth path.
echo "  --- live checks ---"
for a in "${OMT_LOGINS[@]}"; do
    if omt token "$a" >/dev/null 2>&1; then
        printf '  %-32s token OK\n' "$a"
    else
        printf '  %-32s TOKEN FAILED: %s\n' "$a" "$(omt token "$a" 2>&1 | head -1)"
        rc=1
    fi
done

exit $rc
