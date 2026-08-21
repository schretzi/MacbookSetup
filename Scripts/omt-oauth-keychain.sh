#!/usr/bin/env bash
# Store / show the OAuth *application* credentials omt needs, in the macOS
# keychain instead of in a file.
#
# These are Thunderbird's published client_id/client_secret pairs - not
# personal secrets, every Thunderbird install ships them. They are kept out of
# git anyway because GitHub's push protection blocks "Google OAuth Client ID"
# and "Google OAuth Client Secret" patterns outright, and because a repo that
# is meant to become public should carry no credential literals at all.
#
# One keychain item per provider; the password is a JSON object so a single
# lookup returns both halves.
#
#   Scripts/omt-oauth-keychain.sh store <provider> <client_id> <client_secret>
#   Scripts/omt-oauth-keychain.sh show  <provider>
#   Scripts/omt-oauth-keychain.sh list
#
# Providers match the keys of mail_omt_providers: google, o365, o365-consumers.
# Values come from Thunderbird's source (comm-central, OAuth2Providers.sys.mjs).

set -euo pipefail

SERVICE="${OMT_OAUTH_KEYCHAIN_SERVICE:-MacbookSetup omt oauth}"
PROVIDERS=(google o365 o365-consumers)

usage() { sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 64; }

case "${1:-}" in
  store)
    [ $# -eq 4 ] || usage
    provider=$2 id=$3 secret=$4
    payload=$(printf '{"client_id":"%s","client_secret":"%s"}' "$id" "$secret")
    # -U updates in place, so re-running never creates duplicate items
    security add-generic-password -U -s "$SERVICE" -a "$provider" -w "$payload"
    echo "stored $provider in keychain service '$SERVICE'"
    ;;
  show)
    [ $# -eq 2 ] || usage
    security find-generic-password -w -s "$SERVICE" -a "$2"
    ;;
  list)
    for p in "${PROVIDERS[@]}"; do
      if security find-generic-password -s "$SERVICE" -a "$p" >/dev/null 2>&1; then
        echo "  $p: present"
      else
        echo "  $p: MISSING"
      fi
    done
    ;;
  *)
    usage
    ;;
esac
