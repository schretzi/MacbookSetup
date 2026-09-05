#!/usr/bin/env bash
# Import a model I already have in LM Studio into Ollama, with a context window
# I choose rather than the 4096 Ollama defaults to.
#
# Two things make this less trivial than "point Ollama at the file", and both
# are the reason this script exists instead of a line in my notes:
#
#   * **LM Studio holds two incompatible formats.** Anything under
#     `mlx-community/` (and most `lmstudio-community/*-MLX-*`) is MLX: Apple-
#     silicon-only `.safetensors` quantised with MLX's own affine scheme.
#     Ollama runs llama.cpp and reads GGUF. It cannot load MLX at all - not
#     slowly, not with a flag. Its `FROM <safetensors dir>` path only accepts
#     *unquantised* fp16/bf16 weights for a handful of architectures, so a
#     4-bit MLX directory fails there too. There is no local conversion worth
#     doing either: de-quantising 4-bit MLX back to fp16 and re-quantising to
#     GGUF loses more than re-downloading a GGUF built from the original
#     weights. So for MLX models the honest move is to fetch the GGUF, and
#     `--pull` does exactly that from the same build of the same model.
#   * **num_ctx has to be set in two places or it silently does not apply.**
#     A `PARAMETER num_ctx` baked into the model is only a *default*. Any
#     client that sends its own `num_ctx` in the request options overrides it,
#     and one that sends nothing gets whatever `OLLAMA_CONTEXT_LENGTH` says.
#     This script owns the model-side half; the client-side half for aider
#     lives in ~/.aider.model.settings.yml.
#
#   ollama-import-model.sh [options] <model>
#
#   <model>   an LM Studio model as `publisher/name`, or any unique substring
#             of one, or a path to a .gguf file or a directory holding one
#
#   -c, --ctx N       context window in tokens (default 32768)
#   -n, --name NAME   name to create in Ollama (default: derived, tagged <N>k)
#   -q, --quant Q     quant to fetch when falling back to GGUF (default Q4_K_M)
#   -p, --pull        allow downloading a GGUF when the local copy is MLX
#   -f, --force       replace an existing Ollama model of the same name
#   -l, --list        list LM Studio models with the format each one is in
#   -h, --help
#
# Examples:
#   ollama-import-model.sh --list
#   ollama-import-model.sh --pull --name devstral:32k Devstral-Small-2
#   ollama-import-model.sh --ctx 16384 some-publisher/Model-GGUF
#
# Exit status is non-zero when the model does not end up in Ollama, so this can
# gate an Ansible task or a Makefile step.

set -uo pipefail

LMS_MODELS="${LMSTUDIO_MODELS_DIR:-$HOME/.lmstudio/models}"
CTX=32768
NAME=""
QUANT="Q4_K_M"
ALLOW_PULL=0
FORCE=0

die() { printf '%s\n' "$*" >&2; exit 1; }
note() { printf '%s\n' "$*" >&2; }
usage() { sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

command -v ollama >/dev/null 2>&1 || die "ollama not found in PATH"

# --- model format detection -------------------------------------------------
#
# Asked of a directory. GGUF wins if both are somehow present, since that is
# the one Ollama can actually load. mmproj-*.gguf is a vision projector, not a
# model, so a directory holding only that is not importable on its own.
model_format() {
	local dir="$1"
	if find "$dir" -maxdepth 1 -name '*.gguf' ! -name 'mmproj-*' -print -quit 2>/dev/null | grep -q .; then
		echo gguf
	elif find "$dir" -maxdepth 1 -name '*.safetensors' -print -quit 2>/dev/null | grep -q .; then
		# MLX and plain HF weights are both .safetensors; the quantization key
		# in config.json is what separates "Ollama might read this" from "no".
		if grep -q '"quantization"' "$dir/config.json" 2>/dev/null; then
			echo mlx
		else
			echo safetensors
		fi
	else
		echo unknown
	fi
}

first_gguf() {
	find "$1" -maxdepth 1 -name '*.gguf' ! -name 'mmproj-*' | sort | head -1
}

list_models() {
	[ -d "$LMS_MODELS" ] || die "no LM Studio model directory at $LMS_MODELS"
	local dir rel fmt
	printf '%-12s %-10s %s\n' FORMAT SIZE MODEL
	while IFS= read -r dir; do
		rel="${dir#"$LMS_MODELS"/}"
		fmt="$(model_format "$dir")"
		printf '%-12s %-10s %s\n' "$fmt" "$(du -sh "$dir" 2>/dev/null | cut -f1)" "$rel"
	done < <(find "$LMS_MODELS" -mindepth 2 -maxdepth 2 -type d | sort)
}

# --- resolve the argument to a directory ------------------------------------
resolve_model() {
	local want="$1"
	if [ -f "$want" ]; then printf '%s\n' "$(cd "$(dirname "$want")" && pwd)"; return 0; fi
	if [ -d "$want" ]; then printf '%s\n' "$(cd "$want" && pwd)"; return 0; fi
	if [ -d "$LMS_MODELS/$want" ]; then printf '%s\n' "$LMS_MODELS/$want"; return 0; fi

	local matches
	matches="$(find "$LMS_MODELS" -mindepth 2 -maxdepth 2 -type d 2>/dev/null \
		| grep -i -- "$want")"
	[ -n "$matches" ] || return 1
	if [ "$(printf '%s\n' "$matches" | wc -l)" -gt 1 ]; then
		note "'$want' matches more than one model:"
		printf '%s\n' "$matches" | sed "s|$LMS_MODELS/|  |" >&2
		return 2
	fi
	printf '%s\n' "$matches"
}

# --- MLX -> GGUF repo mapping -----------------------------------------------
#
# The MLX directory name carries the exact build (…-2512-4bit), so the matching
# GGUF is the same base name under a publisher that ships GGUF. Tried in order
# of how closely their builds track the original release. Each candidate is
# checked against the HF API before Ollama is asked to pull it, so a miss costs
# a request rather than a failed 14GB download.
gguf_repo_for() {
	local base="$1" repo
	base="$(printf '%s' "$base" | sed -E 's/-(MLX-)?[0-9]+bit$//; s/-(mlx|MLX)$//; s/-(bf16|fp16)$//')"
	for repo in \
		"lmstudio-community/${base}-GGUF" \
		"unsloth/${base}-GGUF" \
		"bartowski/${base}-GGUF" \
		"ggml-org/${base}-GGUF"; do
		if curl -fsS -m 15 "https://huggingface.co/api/models/$repo" 2>/dev/null \
			| grep -q '"rfilename"'; then
			printf '%s\n' "$repo"; return 0
		fi
	done
	return 1
}

# --- argument parsing -------------------------------------------------------
while [ $# -gt 0 ]; do
	case "$1" in
		-c|--ctx)   CTX="${2:-}"; shift 2 ;;
		-n|--name)  NAME="${2:-}"; shift 2 ;;
		-q|--quant) QUANT="${2:-}"; shift 2 ;;
		-p|--pull)  ALLOW_PULL=1; shift ;;
		-f|--force) FORCE=1; shift ;;
		-l|--list)  list_models; exit 0 ;;
		-h|--help)  usage ;;
		-*)         die "unknown option: $1" ;;
		*)          break ;;
	esac
done

[ $# -eq 1 ] || usage
TARGET="$1"

case "$CTX" in ''|*[!0-9]*) die "--ctx must be a number of tokens, got '$CTX'" ;; esac
[ "$CTX" -ge 512 ] || die "--ctx $CTX is too small to be useful"

DIR="$(resolve_model "$TARGET")" || die "no LM Studio model matching '$TARGET' (try --list)"
BASE="$(basename "$DIR")"
FORMAT="$(model_format "$DIR")"

if [ -z "$NAME" ]; then
	NAME="$(printf '%s' "$BASE" | tr '[:upper:]' '[:lower:]' | sed -E 's/-(mlx-)?[0-9]+bit$//; s/-gguf$//')"
	NAME="$NAME:$((CTX / 1024))k"
fi
case "$NAME" in *:*) ;; *) NAME="$NAME:$((CTX / 1024))k" ;; esac

note "model:  $DIR"
note "format: $FORMAT"
note "target: $NAME  (num_ctx $CTX)"

if [ "$FORCE" -eq 0 ] && ollama list 2>/dev/null | awk '{print $1}' | grep -qx "$NAME"; then
	die "$NAME already exists in Ollama - pass --force to replace it"
fi

# --- work out what FROM should point at -------------------------------------
case "$FORMAT" in
	gguf)
		SOURCE="$(first_gguf "$DIR")"
		[ -n "$SOURCE" ] || die "no importable .gguf in $DIR"
		note "source: $SOURCE"
		note "note:   Ollama copies the weights into ~/.ollama, so this needs"
		note "        roughly $(du -sh "$SOURCE" | cut -f1) of free disk on top of the LM Studio copy."
		;;
	mlx)
		note ""
		note "$BASE is MLX (4-bit safetensors, Apple-silicon only)."
		note "Ollama runs llama.cpp and cannot load MLX weights in any form."
		if [ "$ALLOW_PULL" -eq 0 ]; then
			die "Re-run with --pull to fetch the equivalent GGUF build instead."
		fi
		note "Looking for a GGUF build of the same model..."
		REPO="$(gguf_repo_for "$BASE")" || die "no GGUF repo found for $BASE - pull one manually"
		SOURCE="hf.co/$REPO:$QUANT"
		note "source: $SOURCE"
		ollama pull "$SOURCE" || die "pull failed - check that $REPO publishes a $QUANT file"
		;;
	safetensors)
		# Unquantised weights: Ollama can convert these itself, but only for the
		# architectures it knows. Let it try and report its own error.
		SOURCE="$DIR"
		note "source: $DIR (unquantised - Ollama will convert if it knows this architecture)"
		;;
	*)
		die "$DIR holds neither GGUF nor safetensors weights"
		;;
esac

# --- create the model -------------------------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

{
	printf 'FROM %s\n' "$SOURCE"
	printf 'PARAMETER num_ctx %s\n' "$CTX"
} > "$TMP/Modelfile"

note ""
note "creating $NAME ..."
ollama create "$NAME" -f "$TMP/Modelfile" || die "ollama create failed"

# Verify rather than trust: a Modelfile that was accepted is not proof the
# parameter survived, and a wrong num_ctx shows up much later as truncated
# context instead of an error.
if ollama show "$NAME" --modelfile 2>/dev/null | grep -q "num_ctx $CTX"; then
	note ""
	note "$NAME created with num_ctx $CTX"
	note "Clients that send their own num_ctx still override this - for aider,"
	note "set it in ~/.aider.model.settings.yml as well."
else
	die "$NAME was created but num_ctx $CTX is not in its Modelfile"
fi
