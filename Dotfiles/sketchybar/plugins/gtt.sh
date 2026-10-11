#!/bin/bash
# Shows the currently running gtt time entry: client · project/task · elapsed.
#
# `gtt current --json` only carries IDs (client_id, project_id, task_id), not
# names - printTimeEntryRowsTable resolves those with extra API calls purely
# for the human-readable table, same as this script does. Polled every 5s
# (sketchybarrc), that's 1-3 HTTP round trips/s forever if done naively, so
# names are cached in state (see CONVENTIONS.md §2a) keyed by ID and only
# refetched on a cache miss; only the "is anything running, since when"
# lookup happens on every poll.
set -uo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/sketchybar-gtt"
CACHE="$STATE_DIR/names.json"
mkdir -p "$STATE_DIR"

IDLE_COLOR=0xff88909f
RUNNING_COLOR=0xffa3be8c

cache_get() { # key
  [[ -f "$CACHE" ]] && jq -r --arg k "$1" '.[$k] // empty' "$CACHE"
}

cache_set() { # key value
  [[ -f "$CACHE" ]] || echo '{}' >"$CACHE"
  local tmp
  tmp="$(mktemp "$STATE_DIR/names.XXXXXX")"
  jq --arg k "$1" --arg v "$2" '.[$k] = $v' "$CACHE" >"$tmp" && mv -f "$tmp" "$CACHE"
}

current_json="$(gtt current --json 2>/dev/null)"
if [[ -z "$current_json" ]]; then
  sketchybar --set "$NAME" label="no timer" icon.color="$IDLE_COLOR" label.color="$IDLE_COLOR"
  exit 0
fi

client_id="$(jq -r '.client_id' <<<"$current_json")"
project_id="$(jq -r '.project_id // empty' <<<"$current_json")"
task_id="$(jq -r '.task_id // empty' <<<"$current_json")"
start_time="$(jq -r '.start_time' <<<"$current_json")"

client_name="$(cache_get "client:$client_id")"
if [[ -z "$client_name" ]]; then
  client_name="$(gtt client get "$client_id" --json 2>/dev/null | jq -r '.name // "?"')"
  cache_set "client:$client_id" "$client_name"
fi

project_name="—"
task_name=""
if [[ -n "$task_id" ]]; then
  cached="$(cache_get "task:$task_id")"
  if [[ -n "$cached" ]]; then
    task_name="${cached%%|*}"
    task_project_id="${cached#*|}"
  else
    task_json="$(gtt task get "$task_id" --json 2>/dev/null)"
    task_name="$(jq -r '.name // "?"' <<<"$task_json")"
    task_project_id="$(jq -r '.project_id // empty' <<<"$task_json")"
    cache_set "task:$task_id" "${task_name}|${task_project_id}"
  fi
  if [[ -n "${task_project_id:-}" ]]; then
    project_id="$task_project_id"
  fi
fi

if [[ -n "$project_id" ]]; then
  project_name="$(cache_get "project:$project_id")"
  if [[ -z "$project_name" ]]; then
    project_name="$(gtt project get "$project_id" --json 2>/dev/null | jq -r '.name // "?"')"
    cache_set "project:$project_id" "$project_name"
  fi
fi

# RFC3339Nano -> epoch: BSD date needs a fixed-width format, so the
# fractional seconds (and the trailing Z) are stripped before parsing, and
# the parse is forced to UTC to match it.
start_epoch="$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "${start_time%%.*}" "+%s" 2>/dev/null || echo 0)"
now_epoch="$(date -u +%s)"
elapsed=$((now_epoch - start_epoch))
((elapsed < 0)) && elapsed=0
elapsed_fmt="$(printf '%02d:%02d:%02d' $((elapsed / 3600)) $(((elapsed % 3600) / 60)) $((elapsed % 60)))"

label="$client_name · $project_name"
[[ -n "$task_name" ]] && label="$label · $task_name"
label="$label  ($elapsed_fmt)"

sketchybar --set "$NAME" label="$label" icon.color="$RUNNING_COLOR" label.color=0xffd8dee9
