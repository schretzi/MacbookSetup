#!/usr/bin/env bash
# picker.sh — fzf-Picker über SSH-Hosts, Container und Repos
# Aufruf aus kitty: map ctrl+shift+alt+super+p launch --type=overlay --hold .../picker.sh
# Manuell im Shell: pk() { local d; d=$(...); [[ -d "$d" ]] && cd "$d"; }
#
# Quellen (Tab-getrennt, # = Kommentar):
#   ~/.config/picker/ssh.txt         ssh-ziel<TAB>Anzeigename<TAB>Beschreibung
#                                    (ssh-ziel = IP oder ~/.ssh/config-Host)
#   ~/.config/picker/containers.txt  kompletter Befehl<TAB>Anzeigename<TAB>Beschreibung
#   ~/.config/picker/repos.txt       Pfad<TAB>Anzeigename<TAB>Beschreibung
#   zusätzlich: laufende Docker-Container (docker ps) und — falls vorhanden —
#   der dev-pods-Picker (LocalKubernetes) als Quellen für Ad-hoc-Container.
#
# Ausgabe-Verhalten:
#   ssh / container  -> exec (das Overlay-Fenster wird zur Session)
#   repo            -> gibt den Pfad auf stdout aus; als Shell-Funktion "pk"
#                      aufgerufen, wertet diese den Pfad mit cd aus. Aus kitty
#                      gestartet macht cd wenig Sinn — deshalb öffnet kitty hier
#                      stattdessen ein neues Fenster im Repo (siehe map unten).

set -euo pipefail

# kitty (GUI) startet uns ohne Benutzer-Shell: PATH ergänzen, sonst fehlen
# fzf/docker. (Gleiche Falle wie in dev-pods/pick.sh.)
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:${PATH}"

DIR="${PICKER_DIR:-$HOME/.config/picker}"
DEV_PODS="$HOME/Workspace/Schretzi/LocalKubernetes/dev-pods"

SEP=$'\t'
entries=()

add() { # add <art> <anzeige> <ziel> <text>
  entries+=("$1${SEP}$2${SEP}$3${SEP}$4")
}

# --- SSH-Hosts ---
if [[ -f "$DIR/ssh.txt" ]]; then
  while IFS=$'\t' read -r target name desc; do
    [[ -z "${target:-}" || "$target" == \#* ]] && continue
    add ssh "${name:-$target}" "$target" "${desc:-}"
  done < "$DIR/ssh.txt"
fi

# --- Vorkonfigurierte Ad-hoc-Container (Zeile = kompletter Befehl) ---
if [[ -f "$DIR/containers.txt" ]]; then
  while IFS=$'\t' read -r cmd name desc; do
    [[ -z "${cmd:-}" || "$cmd" == \#* ]] && continue
    add cadhoc "${name:-$cmd}" "$cmd" "${desc:-}"
  done < "$DIR/containers.txt"
fi

# --- Ad-hoc-Container aus dev-pods (jedes dev-pods/<name>/run.sh) ---
if [[ -d "$DEV_PODS" ]]; then
  for run in "$DEV_PODS"/*/run.sh; do
    [[ -f "$run" ]] || continue
    name=$(basename "$(dirname "$run")")
    add cadhoc "pod: ${name}" "$run" "dev-pods ad-hoc Container"
  done
fi

# --- Laufende Docker-Container ---
if command -v docker >/dev/null 2>&1; then
  while IFS=$'\t' read -r name image; do
    [[ -z "${name:-}" ]] && continue
    add cdocker "${name}" "docker exec -it ${name} bash" "Image: ${image}"
  done < <(docker ps --format '{{.Names}}\t{{.Image}}' 2>/dev/null || true)
fi

# --- Repos ---
if [[ -f "$DIR/repos.txt" ]]; then
  while IFS=$'\t' read -r path name desc; do
    [[ -z "${path:-}" || "$path" == \#* ]] && continue
    add repo "${name:-$(basename "$path")}" "$path" "${desc:-}"
  done < "$DIR/repos.txt"
fi

if [[ ${#entries[@]} -eq 0 ]]; then
  echo "Picker: keine Einträge — fülle $DIR/{ssh,containers,repos}.txt" >&2
  exit 1
fi

# --- fzf: Zeile = art<TAB>anzeige<TAB>ziel<TAB>text; Suche über Anzeige+Text ---
choice=$(printf '%s\n' "${entries[@]}" | fzf \
  --prompt='➜ ' \
  --delimiter='\t' \
  --with-nth=1,2,4 \
  --height=100% \
  --header='ssh: Enter | container: Enter | repo: Enter (cd)' \
  --preview='
    IFS=$'"'"'\t'"'"' read -r kind disp target text <<< "{}"
    case "$kind" in
      ssh)     echo "ssh $target"; grep -A5 -i "^Host ${target}\$" ~/.ssh/config 2>/dev/null || true;;
      repo)    if [[ -d "$target" ]]; then
                 echo "cd $target"; echo; ls -la "$target" | head -25
               else
                 echo "!! $target existiert nicht"
               fi;;
      cdocker) echo "docker exec -it $target"; docker inspect "$target" --format "Image: {{.Config.Image}}" 2>/dev/null || true;;
      cadhoc)  echo "Befehl: $target"; [[ -f "$target" ]] && head -20 "$target";;
    esac' \
  --preview-window=right:40%) || exit 0

IFS=$'\t' read -r kind disp target text <<< "$choice"

case "$kind" in
  ssh)
    exec ssh "$target"
    ;;
  cdocker)
    exec bash -c "$target"
    ;;
  cadhoc)
    if [[ -x "$target" ]]; then exec "$target"; else exec bash -lc "$target"; fi
    ;;
  repo)
    if [[ -t 1 && -n "${KITTY_PID:-}" ]]; then
      # Aus kitty heraus: neues Fenster im Repo öffnen
      kitten @ launch --type=overlay --cwd "$target" 2>/dev/null || true
    else
      # Als Shell-Funktion aufgerufen: Pfad für "cd" ausgeben
      echo "$target"
    fi
    ;;
esac
