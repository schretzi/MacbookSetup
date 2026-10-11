#!/usr/bin/env bash
# Two-way sync of the notes vault between a local folder and Nextcloud, with
# rclone bisync over WebDAV. Meant for the travel Air: a real local copy that
# works offline, synced every few minutes by the com.schretzi.notes-sync
# LaunchAgent - slower than the M5's WebDAV mount, but nothing stays resident.
#
#   Scripts/notes-sync.sh            one sync run
#   Scripts/notes-sync.sh --resync   first run / after an error rclone cannot
#                                    recover from: rebuilds bisync's state as
#                                    the union of both sides, deletes nothing
#
# The remote is defined entirely through RCLONE_CONFIG_* variables, so there
# is no rclone.conf. The app password is read from the login keychain on
# every run and never written to disk; rclone gets it obscured, in the
# environment, not in argv where `ps` would show it.
#
# Settings (environment, defaults below - the LaunchAgent sets them all):
#   NOTES_SYNC_URL       WebDAV root of the user, .../remote.php/dav/files/<user>
#   NOTES_SYNC_USER      Nextcloud user
#   NOTES_SYNC_REMOTE    folder below the WebDAV root
#   NOTES_SYNC_LOCAL     local folder
#   NOTES_SYNC_KEYCHAIN  name (service or label) of the app password item
#   NOTES_SYNC_KEYCHAIN_ACCOUNT  its account, optional
set -euo pipefail

url="${NOTES_SYNC_URL:?NOTES_SYNC_URL is not set}"
user="${NOTES_SYNC_USER:?NOTES_SYNC_USER is not set}"
remote="${NOTES_SYNC_REMOTE:?NOTES_SYNC_REMOTE is not set}"
local_dir="${NOTES_SYNC_LOCAL:?NOTES_SYNC_LOCAL is not set}"
keychain="${NOTES_SYNC_KEYCHAIN:?NOTES_SYNC_KEYCHAIN is not set}"
keychain_account="${NOTES_SYNC_KEYCHAIN_ACCOUNT:-}"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

# Offline (plane, hotel without WLAN) is the normal case on this machine, not
# an error: skip quietly instead of letting bisync record a failed run.
host="${url#*://}"; host="${host%%/*}"
if ! /usr/bin/curl -sS -o /dev/null --max-time 10 "https://$host/status.php"; then
  log "skip: $host not reachable"
  exit 0
fi

# Keychain Access shows one "Name" that can be either the service or the
# label of the item - try both. The account narrows the match when given.
account_args=()
[ -n "$keychain_account" ] && account_args=(-a "$keychain_account")
if ! pass="$(/usr/bin/security find-generic-password -s "$keychain" ${account_args[@]+"${account_args[@]}"} -w 2>/dev/null)" &&
   ! pass="$(/usr/bin/security find-generic-password -l "$keychain" ${account_args[@]+"${account_args[@]}"} -w 2>/dev/null)"; then
  log "error: no keychain item named '$keychain'${keychain_account:+ with account $keychain_account}"
  exit 1
fi

export RCLONE_CONFIG_NEXTCLOUD_TYPE=webdav
export RCLONE_CONFIG_NEXTCLOUD_URL="$url"
export RCLONE_CONFIG_NEXTCLOUD_VENDOR=nextcloud
export RCLONE_CONFIG_NEXTCLOUD_USER="$user"
RCLONE_CONFIG_NEXTCLOUD_PASS="$(printf '%s' "$pass" | rclone obscure -)"
export RCLONE_CONFIG_NEXTCLOUD_PASS
unset pass

mkdir -p "$local_dir"

# shellcheck disable=SC2054  # "size,modtime" is one value, not two elements
args=(
  bisync "$local_dir" "nextcloud:$remote"
  --create-empty-src-dirs
  --compare size,modtime
  # Nextcloud's WebDAV keeps modtimes at one-second precision
  --modify-window 1s
  # an edit on both sides keeps both files, the older one as .conflictN
  --conflict-resolve newer
  --conflict-loser num
  # a run that dies halfway (lid closed, network gone) is retried next time
  # instead of demanding a manual --resync
  --resilient --recover --max-lock 5m
  # guard against an emptied side wiping the other: bisync aborts if a run
  # would delete more than this share of the files
  --max-delete 20
  # per-device UI state, rewritten on every click in Obsidian
  --exclude ".obsidian/workspace*.json"
  --exclude ".DS_Store"
  --exclude ".Trash/**"
  # AppleDouble files: macOS writes one next to every file it saves onto a
  # WebDAV volume, so the M5's mount leaves them on the server
  --exclude "._*"
  --verbose
)
[ "${1:-}" = "--resync" ] && args+=(--resync)

log "sync $local_dir <-> $host:$remote${1:+ ($1)}"
rclone "${args[@]}"
log "done"
