#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

find_astra_root() {
  local candidate
  if [[ -n "${ASTRA_ROOT:-}" && -x "${ASTRA_ROOT}/bin/astra" ]]; then
    printf '%s\n' "$ASTRA_ROOT"
    return 0
  fi

  local candidates=()
  candidates+=("$SCRIPT_DIR/../astra")
  candidates+=("$SCRIPT_DIR/../../astra")
  candidates+=("$HOME/.local/share/bash-zoo/astra")
  candidates+=("${XDG_DATA_HOME:-$HOME/.local/share}/bash-zoo/astra")
  if [[ "$(uname -s)" == "Darwin" ]]; then
    candidates+=("$HOME/Library/Application Support/bash-zoo/astra")
  fi
  candidates+=("/usr/local/share/bash-zoo/astra")
  candidates+=("/usr/share/bash-zoo/astra")

  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate/bin/astra" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

find_modern_bash() {
  local candidates=()
  local candidate

  if [[ -n "${ASTRA_PREFERRED_BASH:-}" ]]; then
    candidates+=("$ASTRA_PREFERRED_BASH")
  fi

  if [[ -x "/opt/homebrew/bin/bash" ]]; then
    candidates+=("/opt/homebrew/bin/bash")
  fi

  if [[ -x "/usr/local/bin/bash" ]]; then
    candidates+=("/usr/local/bin/bash")
  fi

  if command -v brew >/dev/null 2>&1; then
    candidate=$(brew --prefix bash 2>/dev/null)
    if [[ -n "$candidate" && -x "$candidate/bin/bash" ]]; then
      candidates+=("$candidate/bin/bash")
    fi
  fi

  if command -v bash >/dev/null 2>&1; then
    candidate=$(command -v bash)
    if [[ -n "$candidate" ]]; then
      candidates+=("$candidate")
    fi
  fi

  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" ]]; then
      if "$candidate" -c '(( BASH_VERSINFO[0] >= 5 ))' >/dev/null 2>&1; then
        printf '%s\n' "$candidate"
        return 0
      fi
    fi
  done

  return 1
}

ASTRA_ROOT_RESOLVED=$(find_astra_root || true)

if [[ -z "$ASTRA_ROOT_RESOLVED" ]]; then
  cat >&2 <<'ERR'
astra: unable to locate runtime files.
Re-run ./install.sh and ensure Astra assets are installed.
ERR
  exit 1
fi

ASTRA_RUNTIME="$ASTRA_ROOT_RESOLVED/bin/astra"

if modern_bash=$(find_modern_bash 2>/dev/null); then
  exec "$modern_bash" "$ASTRA_RUNTIME" "$@"
fi

exec "$ASTRA_RUNTIME" "$@"
