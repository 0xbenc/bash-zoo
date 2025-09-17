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

ASTRA_ROOT_RESOLVED=$(find_astra_root || true)

if [[ -z "$ASTRA_ROOT_RESOLVED" ]]; then
  cat >&2 <<'ERR'
astra: unable to locate runtime files.
Re-run ./install.sh and ensure Astra assets are installed.
ERR
  exit 1
fi

exec "$ASTRA_ROOT_RESOLVED/bin/astra" "$@"
