#!/usr/bin/env bash

set -Eeuo pipefail

declare -Ag ASTRA_ACTION_HANDLERS=()

register_action() {
  local name="$1"
  local fn="$2"
  ASTRA_ACTION_HANDLERS["$name"]="$fn"
}

actions_dispatch() {
  local action="$1"
  shift || true
  local handler="${ASTRA_ACTION_HANDLERS[$action]:-}"
  if [[ -z "$handler" ]]; then
    log_warn "Unknown action: $action"
    return 1
  fi
  "$handler" "$@"
}

astra_default_open() {
  local path="$1"
  if [[ -d "$path" ]]; then
    state_change_dir "$path"
    return 0
  fi

  if is_macos; then
    if command -v open >/dev/null 2>&1; then
      open "$path" >/dev/null 2>&1 & disown || true
      return 0
    fi
  elif is_linux; then
    if command -v xdg-open >/dev/null 2>&1; then
      xdg-open "$path" >/dev/null 2>&1 & disown || true
      return 0
    fi
  fi

  if declare -F os_open >/dev/null; then
    os_open "$path" >/dev/null 2>&1 & disown || true
    return 0
  fi

  local editor="${EDITOR:-vi}"
  "$editor" "$path"
}

action_open() {
  local path="$1"
  if [[ -z "$path" ]]; then
    return 1
  fi
  astra_default_open "$path"
}

action_edit() {
  local path="$1"
  local editor="${EDITOR:-vi}"
  "$editor" "$path"
}

action_rename() {
  local path="$1"
  if [[ -z "$path" ]]; then
    return 1
  fi
  local base dir new_name
  dir=$(dirname "$path")
  base=$(basename "$path")
  read -r -p "Rename '$base' to: " new_name
  if [[ -z "$new_name" ]]; then
    echo "Rename cancelled"
    return 1
  fi
  mv -- "$path" "$dir/$new_name"
}

action_copy() {
  local targets=()
  if (( $# > 0 )); then
    targets=("$@")
  elif state_has_selection; then
    mapfile -t targets < <(state_selected_paths)
    state_selection_clear
  fi
  if [[ ${#targets[@]} -eq 0 ]]; then
    return 1
  fi
  read -r -p "Copy to directory: " dest
  if [[ -z "$dest" ]]; then
    echo "Copy cancelled"
    return 1
  fi
  mkdir -p "$dest"
  cp -R -- "${targets[@]}" "$dest/"
}

action_move() {
  local targets=()
  if (( $# > 0 )); then
    targets=("$@")
  elif state_has_selection; then
    mapfile -t targets < <(state_selected_paths)
    state_selection_clear
  fi
  if [[ ${#targets[@]} -eq 0 ]]; then
    return 1
  fi
  read -r -p "Move to directory: " dest
  if [[ -z "$dest" ]]; then
    echo "Move cancelled"
    return 1
  fi
  mkdir -p "$dest"
  mv -- "${targets[@]}" "$dest/"
}

action_delete() {
  local targets=()
  if (( $# > 0 )); then
    targets=("$@")
  elif state_has_selection; then
    mapfile -t targets < <(state_selected_paths)
    state_selection_clear
  fi
  if [[ ${#targets[@]} -eq 0 ]]; then
    return 1
  fi
  echo "Delete the following?"
  printf '  %s\n' "${targets[@]}"
  read -r -p "Type 'yes' to confirm: " confirm
  if [[ "$confirm" != "yes" ]]; then
    echo "Delete cancelled"
    return 1
  fi
  if cfg_get_bool "actions.delete.use_trash" && [[ -n "${ASTRA_TRASH_CMD:-}" ]]; then
    if [[ "$ASTRA_TRASH_CMD" == "gio" ]]; then
      local item
      for item in "${targets[@]}"; do
        gio trash "$item"
      done
    elif [[ "$ASTRA_TRASH_CMD" == "trash" ]]; then
      "$ASTRA_TRASH_CMD" -- "${targets[@]}"
    else
      "$ASTRA_TRASH_CMD" "${targets[@]}"
    fi
  else
    rm -rf -- "${targets[@]}"
  fi
}

action_new_dir() {
  local name
  read -r -p "New directory name: " name
  if [[ -z "$name" ]]; then
    echo "Creation cancelled"
    return 1
  fi
  mkdir -p -- "$ASTRA_CWD/$name"
}

action_new_file() {
  local name
  read -r -p "New file name: " name
  if [[ -z "$name" ]]; then
    echo "Creation cancelled"
    return 1
  fi
  : >"$ASTRA_CWD/$name"
}

action_properties() {
  local path="$1"
  if [[ -z "$path" ]]; then
    return 1
  fi
  local size mtime perms type
  if command -v stat >/dev/null 2>&1; then
    if is_macos; then
      size=$(stat -f "%z" -- "$path")
      mtime=$(stat -f "%Sm" -- "$path")
      perms=$(stat -f "%Sp" -- "$path")
    else
      size=$(stat -c "%s" -- "$path")
      mtime=$(stat -c "%y" -- "$path")
      perms=$(stat -c "%A" -- "$path")
    fi
  else
    size=$(wc -c <"$path")
    mtime=""
    perms=""
  fi
  if [[ -d "$path" ]]; then
    type="directory"
  elif [[ -f "$path" ]]; then
    type="file"
  else
    type="other"
  fi
  cat <<INFO
Path: $path
Type: $type
Size: $size bytes
Modified: $mtime
Permissions: $perms
INFO
  read -r -p "Press Enter to continue" _noop
}

register_default_actions() {
  register_action "open" action_open
  register_action "edit" action_edit
  register_action "rename" action_rename
  register_action "copy" action_copy
  register_action "move" action_move
  register_action "delete" action_delete
  register_action "mkdir" action_new_dir
  register_action "touch" action_new_file
  register_action "properties" action_properties
}

register_default_actions
