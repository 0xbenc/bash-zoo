#!/usr/bin/env bash
set -Eeuo pipefail

astra_sample_on_preview() {
  local path="$1"
  if [[ -f "$path" && "${path##*.}" == "md" ]]; then
    echo "[sample plugin] Rendering Markdown header preview"
    sed -n '1,40p' "$path"
    return 0
  fi
  return 1
}

on_preview() {
  astra_sample_on_preview "$@"
}

on_start() {
  log_info "sample plugin initialized"
}

on_exit() {
  log_info "sample plugin exit status: $1"
}
