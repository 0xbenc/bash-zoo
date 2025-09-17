#!/usr/bin/env bash

set -Eeuo pipefail

ASTRA_HISTORY=()
ASTRA_SELECTION=()
ASTRA_SORT_MODE="name"
ASTRA_SORT_REVERSE=false
ASTRA_SHOW_HIDDEN=false
ASTRA_CWD=""
ASTRA_HISTORY_LIMIT=200
ASTRA_NAV_CHANGED=0
ASTRA_RESUME_LAST=0

state_init() {
  ASTRA_CWD="$(pwd)"
  ASTRA_SHOW_HIDDEN=false
  if cfg_get_bool "browser.show_hidden"; then
    ASTRA_SHOW_HIDDEN=true
  fi
  ASTRA_SORT_MODE="$(cfg_get_or_default "browser.sort.mode" "name")"
  ASTRA_SORT_REVERSE=false
  ASTRA_HISTORY_LIMIT=$(cfg_get_or_default "history.limit" "200")
  ASTRA_HISTORY=()
  ASTRA_SELECTION=()
  ASTRA_NAV_CHANGED=0
  ASTRA_RESUME_LAST=0
  if cfg_get_bool "session.resume_last"; then
    ASTRA_RESUME_LAST=1
  fi
  state_load
}

state_load() {
  if [[ -z "${ASTRA_JQ_CMD:-}" || ! -f "$ASTRA_STATE_FILE" ]]; then
    return
  fi

  local data
  data=$("$ASTRA_JQ_CMD" -c '.' "$ASTRA_STATE_FILE" 2>/dev/null || true)
  if [[ -z "$data" ]]; then
    return
  fi

  local cwd show_hidden sort reverse history_json
  cwd=$(printf '%s' "$data" | "$ASTRA_JQ_CMD" -r '.cwd // empty')
  show_hidden=$(printf '%s' "$data" | "$ASTRA_JQ_CMD" -r '.show_hidden // false')
  sort=$(printf '%s' "$data" | "$ASTRA_JQ_CMD" -r '.sort.mode // "name"')
  reverse=$(printf '%s' "$data" | "$ASTRA_JQ_CMD" -r '.sort.reverse // false')
  history_json=$(printf '%s' "$data" | "$ASTRA_JQ_CMD" -c '.history // []')

  if [[ $ASTRA_RESUME_LAST -eq 1 && -n "$cwd" && -d "$cwd" ]]; then
    ASTRA_CWD="$cwd"
  fi
  if [[ "$show_hidden" == "true" ]]; then
    ASTRA_SHOW_HIDDEN=true
  else
    ASTRA_SHOW_HIDDEN=false
  fi
  ASTRA_SORT_MODE="$sort"
  ASTRA_SORT_REVERSE=false
  if [[ "$reverse" == "true" ]]; then
    ASTRA_SORT_REVERSE=true
  fi

  mapfile -t ASTRA_HISTORY < <(printf '%s' "$history_json" | "$ASTRA_JQ_CMD" -r '.[]?')
}

state_save() {
  if [[ -z "${ASTRA_JQ_CMD:-}" ]]; then
    return
  fi

  local tmp reverse_json hidden_json history_json
  tmp="${ASTRA_STATE_FILE}.tmp"

  if [[ "$ASTRA_SORT_REVERSE" == true ]]; then
    reverse_json="true"
  else
    reverse_json="false"
  fi

  if [[ "$ASTRA_SHOW_HIDDEN" == true ]]; then
    hidden_json="true"
  else
    hidden_json="false"
  fi

  history_json=$(printf '%s\n' "${ASTRA_HISTORY[@]}" | "$ASTRA_JQ_CMD" -R -s 'split("\\n") | map(select(length > 0))')
  history_json=${history_json:-[]}

  "$ASTRA_JQ_CMD" -n \
    --arg cwd "$ASTRA_CWD" \
    --arg mode "$ASTRA_SORT_MODE" \
    --argjson reverse "$reverse_json" \
    --argjson show_hidden "$hidden_json" \
    --argjson history "$history_json" \
    '{cwd:$cwd, show_hidden:$show_hidden, sort:{mode:$mode, reverse:$reverse}, history:$history}' \
    >"$tmp"

  mv "$tmp" "$ASTRA_STATE_FILE"
}

state_change_dir() {
  local path="$1"
  if [[ -d "$path" ]]; then
    local resolved
    resolved=$(cd "$path" && pwd)
    log_debug "state_change_dir path=$path resolved=$resolved"
    ASTRA_CWD="$resolved"
    state_selection_clear
    state_history_add "$ASTRA_CWD"
    ASTRA_NAV_CHANGED=1
  else
    log_warn "Directory not found: $path"
  fi
}

state_history_add() {
  local entry="$1"
  ASTRA_HISTORY=("$entry" "${ASTRA_HISTORY[@]}")
  if (( ${#ASTRA_HISTORY[@]} > ASTRA_HISTORY_LIMIT )); then
    ASTRA_HISTORY=("${ASTRA_HISTORY[@]:0:ASTRA_HISTORY_LIMIT}")
  fi
}

state_toggle_hidden() {
  if [[ "$ASTRA_SHOW_HIDDEN" == true ]]; then
    ASTRA_SHOW_HIDDEN=false
  else
    ASTRA_SHOW_HIDDEN=true
  fi
}

state_selection_clear() {
  ASTRA_SELECTION=()
}

state_selection_contains() {
  local target="$1"
  local item
  for item in "${ASTRA_SELECTION[@]}"; do
    if [[ "$item" == "$target" ]]; then
      return 0
    fi
  done
  return 1
}

state_toggle_selection() {
  local path="$1"
  if [[ -z "$path" ]]; then
    return
  fi
  if state_selection_contains "$path"; then
    local new=()
    local item
    for item in "${ASTRA_SELECTION[@]}"; do
      if [[ "$item" != "$path" ]]; then
        new+=("$item")
      fi
    done
    ASTRA_SELECTION=("${new[@]}")
  else
    ASTRA_SELECTION+=("$path")
  fi
}

state_selected_paths() {
  printf '%s\n' "${ASTRA_SELECTION[@]}"
}

state_has_selection() {
  (( ${#ASTRA_SELECTION[@]} > 0 ))
}
