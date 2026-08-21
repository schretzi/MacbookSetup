#!/bin/bash
# Claude Code status line derived from this Mac's starship prompt.
#
# No ~/.config/starship.toml exists on this machine (checked STARSHIP_CONFIG,
# the default location, and the MacbookSetup dotfiles repo's symlink/merge
# maps and zsh rc snippets - starship isn't linked anywhere), so starship is
# running its built-in default configuration. This mirrors starship's
# default `directory`, `git_branch` and `git_status` modules - the segments
# that are always meaningful in a project directory - using their default
# symbols, ordering and colors. The Claude Code model name is prepended
# since that's the one thing a shell prompt can't show and it's the main
# reason this status line exists.
#
# Deliberately dropped: the many other modules starship enables by default
# (per-language/toolchain version segments, cloud context, battery, memory,
# cmd_duration, background jobs, the success/error `character` prompt, ...).
# Most either don't map onto a non-interactive status line (character and
# cmd_duration react to a shell command that doesn't exist here) or would
# need a lot of extra filesystem probing every render just to stay silent
# most of the time. `starship prompt` itself is never shelled out to, so
# this doesn't depend on starship's runtime/session state and stays fast.

input=$(cat)

model=$(printf '%s' "$input" | jq -r '.model.display_name')
cwd=$(printf '%s' "$input" | jq -r '.workspace.current_dir')

# --- directory (starship "directory" module defaults: cyan bold, "~" for
# $HOME, truncated to the last 3 path components with a leading "...") ---
dir="$cwd"
case "$dir" in
  "$HOME") dir="~" ;;
  "$HOME"/*) dir="~${dir#"$HOME"}" ;;
esac

IFS='/' read -r -a parts <<< "$dir"
count=${#parts[@]}
if [ "$count" -gt 3 ]; then
  start=$((count - 3))
  trimmed=""
  i=0
  for p in "${parts[@]}"; do
    if [ "$i" -ge "$start" ]; then
      trimmed="${trimmed}/${p}"
    fi
    i=$((i + 1))
  done
  dir="...${trimmed}"
fi

# --- git_branch + git_status (starship defaults: branch in bold purple with
# a " " symbol; dirty-state flags in bold red: "=" conflicted, "!" modified,
# "+" staged, "?" untracked, "⇡"/"⇣"/"⇕" ahead/behind/diverged). Uses
# --no-optional-locks throughout so this never contends with a running git
# command for the index lock. ---
git_segment=""
if git -C "$cwd" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
  [ -z "$branch" ] && branch=$(git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)

  status=$(git -C "$cwd" --no-optional-locks status --porcelain=v2 --branch 2>/dev/null)

  ahead=$(printf '%s\n' "$status" | awk '/^# branch\.ab/ {gsub("\\+","",$3); print $3}')
  behind=$(printf '%s\n' "$status" | awk '/^# branch\.ab/ {gsub("-","",$4); print $4}')

  conflicted=0; staged=0; modified=0; untracked=0
  while IFS= read -r line; do
    case "$line" in
      "1 "*|"2 "*)
        xy=${line:2:2}
        [ "${xy:0:1}" != "." ] && staged=$((staged + 1))
        [ "${xy:1:1}" != "." ] && modified=$((modified + 1))
        ;;
      "u "*) conflicted=$((conflicted + 1)) ;;
      "? "*) untracked=$((untracked + 1)) ;;
    esac
  done <<< "$status"

  dirty=""
  [ "$conflicted" -gt 0 ] && dirty="${dirty}="
  [ "$modified" -gt 0 ] && dirty="${dirty}!"
  [ "$staged" -gt 0 ] && dirty="${dirty}+"
  [ "$untracked" -gt 0 ] && dirty="${dirty}?"
  if [ -n "$ahead" ] && [ "$ahead" != "0" ] && [ -n "$behind" ] && [ "$behind" != "0" ]; then
    dirty="${dirty}⇕"
  elif [ -n "$ahead" ] && [ "$ahead" != "0" ]; then
    dirty="${dirty}⇡"
  elif [ -n "$behind" ] && [ "$behind" != "0" ]; then
    dirty="${dirty}⇣"
  fi

  git_segment=" \033[1;35m \033[0m\033[1;35m${branch}\033[0m"
  [ -n "$dirty" ] && git_segment="${git_segment} \033[1;31m[${dirty}]\033[0m"
fi

printf "\033[2m[%s]\033[0m \033[1;36m%s\033[0m%b\n" "$model" "$dir" "$git_segment"
