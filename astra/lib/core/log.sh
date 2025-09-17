#!/usr/bin/env bash

set -Eeuo pipefail

ASTRA_LOG_LEVEL=${ASTRA_LOG_LEVEL:-info}

_log_level_value() {
  case "$1" in
    debug) echo 10 ;;
    info)  echo 20 ;;
    warn)  echo 30 ;;
    error) echo 40 ;;
    *)     echo 20 ;;
  esac
}

log_set_level() {
  ASTRA_LOG_LEVEL="$1"
}

log_should_print() {
  local level current
  level=$(_log_level_value "$1")
  current=$(_log_level_value "$ASTRA_LOG_LEVEL")
  (( level >= current ))
}

log_emit() {
  local level message timestamp
  level="$1"
  shift
  message="$*"
  timestamp=$(date '+%Y-%m-%dT%H:%M:%S')
  if log_should_print "$level"; then
    printf '[%s] %-5s %s\n' "$timestamp" "$level" "$message" >&2
  fi
  if [[ -n "${ASTRA_LOG_FILE:-}" ]]; then
    printf '[%s] %-5s %s\n' "$timestamp" "$level" "$message" >>"$ASTRA_LOG_FILE"
  fi
}

log_debug() { log_emit debug "$*"; }
log_info() { log_emit info "$*"; }
log_warn() { log_emit warn "$*"; }
log_error() { log_emit error "$*"; }
