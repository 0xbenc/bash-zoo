#!/usr/bin/env bash

set -Eeuo pipefail

config_init() {
  local override="$1"
  if [[ -z "${ASTRA_JQ_CMD:-}" ]]; then
    echo "astra: jq is required but not found" >&2
    exit 1
  fi

  ASTRA_DEFAULTS_FILE="$ASTRA_SHARE_DIR/defaults.json"
  if [[ ! -f "$ASTRA_DEFAULTS_FILE" ]]; then
    echo "astra: missing defaults at $ASTRA_DEFAULTS_FILE" >&2
    exit 1
  fi

  if [[ -n "$override" ]]; then
    ASTRA_CONFIG_FILE="$override"
    if [[ ! -f "$ASTRA_CONFIG_FILE" ]]; then
      echo "astra: config override not found: $ASTRA_CONFIG_FILE" >&2
      exit 1
    fi
  else
    ASTRA_CONFIG_FILE="$ASTRA_CONFIG_DIR/config.json"
    if [[ ! -f "$ASTRA_CONFIG_FILE" ]]; then
      if [[ -f "$ASTRA_SHARE_DIR/examples/config.json" ]]; then
        cp "$ASTRA_SHARE_DIR/examples/config.json" "$ASTRA_CONFIG_FILE"
      else
        cp "$ASTRA_DEFAULTS_FILE" "$ASTRA_CONFIG_FILE"
      fi
    fi
  fi

  ASTRA_CONFIG_CACHE="$ASTRA_STATE_DIR/config.merged.json"
  cfg_merge
  export ASTRA_CONFIG_FILE ASTRA_CONFIG_CACHE
}

cfg_merge() {
  local tmp inputs=()
  inputs+=("$ASTRA_DEFAULTS_FILE")
  if [[ -f "$ASTRA_CONFIG_FILE" ]]; then
    inputs+=("$ASTRA_CONFIG_FILE")
  fi
  tmp="${ASTRA_CONFIG_CACHE}.tmp"
  "$ASTRA_JQ_CMD" -s 'reduce .[] as $i ({}; . * $i)' "${inputs[@]}" >"$tmp"
  mv "$tmp" "$ASTRA_CONFIG_CACHE"
}

cfg_reload() {
  cfg_merge
}

cfg_get() {
  local key="$1"
  "$ASTRA_JQ_CMD" -r --arg key "$key" 'getpath(($key | split(".") | map(if test("^[0-9]+$") then tonumber else . end))) // empty' "$ASTRA_CONFIG_CACHE"
}

cfg_get_or_default() {
  local key default value
  key="$1"
  default="$2"
  value=$(cfg_get "$key")
  if [[ -z "$value" ]]; then
    printf '%s' "$default"
  else
    printf '%s' "$value"
  fi
}

cfg_get_bool() {
  local key value
  key="$1"
  value=$(cfg_get "$key")
  if [[ -z "$value" ]]; then
    return 1
  fi
  case "$value" in
    true|1|yes|on) return 0 ;;
    false|0|no|off|null) return 1 ;;
    *) return 1 ;;
  esac
}
