#!/usr/bin/env bash
# shellcheck disable=SC2034

set -Eeuo pipefail

ASTRA_MIN_BASH=5

astra_version_ge() {
  local major minor
  major=${BASH_VERSINFO[0]:-0}
  minor=${BASH_VERSINFO[1]:-0}
  if (( major > ASTRA_MIN_BASH )); then
    return 0
  fi
  if (( major == ASTRA_MIN_BASH && minor >= 0 )); then
    return 0
  fi
  return 1
}

env_init() {
  local root share
  root="$1"
  share="$2"

  if [[ -z "$root" ]]; then
    echo "astra: env_init requires root argument" >&2
    exit 1
  fi

  if ! astra_version_ge; then
    echo "astra: requires bash ${ASTRA_MIN_BASH}.0 or newer" >&2
    echo "Current version: ${BASH_VERSINFO[0]:-?}.${BASH_VERSINFO[1]:-?}" >&2
    exit 1
  fi

  ASTRA_ROOT="$root"
  ASTRA_SHARE_DIR="$share"
  ASTRA_RUN_ID="${ASTRA_RUN_ID:-$$}"

  export ASTRA_ROOT ASTRA_SHARE_DIR ASTRA_RUN_ID

  env_setup_directories
  env_detect_os
  env_load_os_adapter
  env_detect_terminal
  env_resolve_tools
}

env_setup_directories() {
  local config_home data_home state_home cache_home
  config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
  data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
  state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
  cache_home="${XDG_CACHE_HOME:-$HOME/.cache}"

  ASTRA_CONFIG_DIR="${ASTRA_CONFIG_DIR:-$config_home/astra}"
  ASTRA_DATA_DIR="${ASTRA_DATA_DIR:-$data_home/astra}"
  ASTRA_STATE_DIR="${ASTRA_STATE_DIR:-$state_home/astra}"
  ASTRA_CACHE_DIR="${ASTRA_CACHE_DIR:-$cache_home/astra}"

  mkdir -p "$ASTRA_CONFIG_DIR" "$ASTRA_DATA_DIR" "$ASTRA_STATE_DIR" "$ASTRA_CACHE_DIR"

  ASTRA_STATE_FILE="$ASTRA_STATE_DIR/state.json"
  ASTRA_BOOKMARK_FILE="$ASTRA_DATA_DIR/bookmarks.json"
  ASTRA_HISTORY_FILE="$ASTRA_DATA_DIR/history.log"
  ASTRA_LOG_FILE="$ASTRA_STATE_DIR/astra.log"
  ASTRA_PREVIEW_CACHE="$ASTRA_CACHE_DIR/previews"
  mkdir -p "$ASTRA_PREVIEW_CACHE"

  export ASTRA_CONFIG_DIR ASTRA_DATA_DIR ASTRA_STATE_DIR ASTRA_CACHE_DIR
  export ASTRA_STATE_FILE ASTRA_BOOKMARK_FILE ASTRA_HISTORY_FILE ASTRA_LOG_FILE ASTRA_PREVIEW_CACHE
}

env_detect_os() {
  local uname
  uname=$(uname -s)
  case "$uname" in
    Darwin)
      ASTRA_OS="macos"
      ;;
    Linux)
      ASTRA_OS="linux"
      ;;
    *)
      ASTRA_OS="unknown"
      ;;
  esac
  export ASTRA_OS
}

env_load_os_adapter() {
  case "$ASTRA_OS" in
    macos)
      # shellcheck disable=SC1091
      source "$ASTRA_ROOT/lib/adapters/os/darwin.sh"
      ;;
    linux)
      # shellcheck disable=SC1091
      source "$ASTRA_ROOT/lib/adapters/os/linux.sh"
      ;;
  esac
}

env_detect_terminal() {
  ASTRA_TERM_IMG="none"
  if [[ -n "${WEZTERM_PANE:-}" ]] && command -v wezterm >/dev/null 2>&1; then
    ASTRA_TERM_IMG="wezterm"
  elif [[ ${TERM_PROGRAM:-} == "iTerm.app" ]] && command -v imgcat >/dev/null 2>&1; then
    ASTRA_TERM_IMG="iterm2"
  elif [[ ${TERM:-} == *kitty* ]] && command -v kitty >/dev/null 2>&1; then
    ASTRA_TERM_IMG="kitty"
  elif command -v chafa >/dev/null 2>&1; then
    ASTRA_TERM_IMG="chafa"
  elif command -v viu >/dev/null 2>&1; then
    ASTRA_TERM_IMG="viu"
  fi
  export ASTRA_TERM_IMG
}

env_resolve_tools() {
  ASTRA_FD_CMD="fd"
  if ! command -v fd >/dev/null 2>&1; then
    if command -v fdfind >/dev/null 2>&1; then
      ASTRA_FD_CMD="fdfind"
    else
      ASTRA_FD_CMD=""
    fi
  fi

  ASTRA_BAT_CMD="bat"
  if ! command -v bat >/dev/null 2>&1; then
    if command -v batcat >/dev/null 2>&1; then
      ASTRA_BAT_CMD="batcat"
    else
      ASTRA_BAT_CMD=""
    fi
  fi

  ASTRA_JQ_CMD="jq"
  if ! command -v jq >/dev/null 2>&1; then
    ASTRA_JQ_CMD=""
  fi

  ASTRA_TRASH_CMD=""
  if command -v trash-put >/dev/null 2>&1; then
    ASTRA_TRASH_CMD="trash-put"
  elif command -v gio >/dev/null 2>&1; then
    ASTRA_TRASH_CMD="gio"
  elif command -v trash >/dev/null 2>&1; then
    ASTRA_TRASH_CMD="trash"
  fi

  export ASTRA_FD_CMD ASTRA_BAT_CMD ASTRA_JQ_CMD ASTRA_TRASH_CMD
}

is_macos() {
  [[ "$ASTRA_OS" == "macos" ]]
}

is_linux() {
  [[ "$ASTRA_OS" == "linux" ]]
}
