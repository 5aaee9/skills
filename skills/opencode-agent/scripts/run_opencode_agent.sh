#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  run_opencode_agent.sh [--model provider/model] [--dry-run] [message...]
  printf '%s\n' "message" | run_opencode_agent.sh [--model provider/model]

Writes the delegated task message to a mktemp file and runs:
  opencode run --dangerously-skip-permissions -i [-m provider/model] -f <file>
USAGE
}

model=""
dry_run=0

while (($#)); do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -m|--model)
      if (($# < 2)) || [[ -z "${2:-}" ]]; then
        echo "error: --model requires a provider/model value" >&2
        exit 2
      fi
      model="$2"
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      break
      ;;
  esac
done

if (($#)); then
  message="$*"
else
  message="$(cat)"
fi

if [[ -z "${message//[[:space:]]/}" ]]; then
  echo "error: message is required via arguments or stdin" >&2
  exit 2
fi

prompt_file="$(mktemp "${TMPDIR:-/tmp}/opencode-agent.XXXXXX.md")"
cleanup() {
  rm -f "$prompt_file"
}
trap cleanup EXIT

printf '%s\n' "$message" > "$prompt_file"

cmd=(opencode run --dangerously-skip-permissions -i)
if [[ -n "$model" ]]; then
  cmd+=(-m "$model")
fi
cmd+=(-f "$prompt_file")

if ((dry_run)); then
  printf 'Prompt file: %s\n' "$prompt_file"
  printf 'Command:'
  printf ' %q' "${cmd[@]}"
  printf '\n'
  printf 'Message bytes: %s\n' "$(wc -c < "$prompt_file")"
  exit 0
fi

exec "${cmd[@]}"
