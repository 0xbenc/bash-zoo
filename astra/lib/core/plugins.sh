#!/usr/bin/env bash

set -Eeuo pipefail

declare -ag ASTRA_PLUGIN_ON_START=()
declare -ag ASTRA_PLUGIN_ON_EXIT=()
declare -ag ASTRA_PLUGIN_ON_KEY=()
declare -ag ASTRA_PLUGIN_ON_PREVIEW=()

plugins_load() {
  if ! cfg_get_bool "plugins.enabled" 2>/dev/null; then
    return
  fi
  local dir
  dir=$(cfg_get_or_default "plugins.dir" "${ASTRA_CONFIG_DIR}/plugins")
  mkdir -p "$dir"
  if [[ ! -d "$dir" ]]; then
    return
  fi
  local plugin
  while IFS= read -r -d '' plugin; do
    plugins_source "$plugin"
  done < <(find "$dir" -maxdepth 1 -type f -name '*.sh' -print0 | sort -z)
  if [[ ${ASTRA_PLUGIN_SUPPRESS_START:-0} -eq 0 ]]; then
    plugins_on_start
  fi
}

plugins_source() {
  local file="$1"
  source "$file"
  plugins_register_hooks_from "$file"
  log_info "Loaded plugin $(basename "$file")"
}

plugins_register_hooks_from() {
  local file="$1"
  local fn
  for fn in on_start on_exit on_key on_preview; do
    if declare -F "$fn" >/dev/null; then
      case "$fn" in
        on_start) ASTRA_PLUGIN_ON_START+=("$fn") ;;
        on_exit) ASTRA_PLUGIN_ON_EXIT+=("$fn") ;;
        on_key) ASTRA_PLUGIN_ON_KEY+=("$fn") ;;
        on_preview) ASTRA_PLUGIN_ON_PREVIEW+=("$fn") ;;
      esac
    fi
  done
}

plugins_on_start() {
  local fn
  for fn in "${ASTRA_PLUGIN_ON_START[@]}"; do
    "$fn" "$@"
  done
}

plugins_on_exit() {
  local status="$1"
  local fn
  for fn in "${ASTRA_PLUGIN_ON_EXIT[@]}"; do
    "$fn" "$status"
  done
}

plugins_handle_key() {
  local key="$1"
  local context="$2"
  local fn
  for fn in "${ASTRA_PLUGIN_ON_KEY[@]}"; do
    if "$fn" "$key" "$context"; then
      return 0
    fi
  done
  return 1
}

plugins_preview_override() {
  local path="$1"
  local fn
  for fn in "${ASTRA_PLUGIN_ON_PREVIEW[@]}"; do
    if "$fn" "$path"; then
      return 0
    fi
  done
  return 1
}
