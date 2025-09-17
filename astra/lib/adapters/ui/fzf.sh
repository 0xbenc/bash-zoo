#!/usr/bin/env bash

set -Eeuo pipefail

declare -ag ASTRA_LAST_LISTING=()

fzf_capture_terminal_size() {
  local size lines cols
  if size=$(stty size 2>/dev/null); then
    lines=${size% *}
    cols=${size#* }
  elif command -v tput >/dev/null 2>&1; then
    lines=$(tput lines 2>/dev/null || echo 0)
    cols=$(tput cols 2>/dev/null || echo 0)
  else
    lines=${LINES:-0}
    cols=${COLUMNS:-0}
  fi

  if [[ -z "$lines" || "$lines" == 0 ]]; then
    lines=24
  fi
  if [[ -z "$cols" || "$cols" == 0 ]]; then
    cols=80
  fi

  ASTRA_TTY_LINES="$lines"
  ASTRA_TTY_COLS="$cols"
  export ASTRA_TTY_LINES ASTRA_TTY_COLS
}

fzf_controls_footer() {
  local line1 line2 reset
  reset=$'\033[0m'
  line1=$'\033[7m ^G Search  ^E Edit    ^Y Copy   Alt-M Move  ^D Delete  ^P Props  \033[0m'
  line2=$'\033[7m Enter Open  Left/h Up  Space Select  . Hidden  ^B Mkdir  ^N New  ^Q Quit \033[0m'
  printf '%s\n%s%s' "$line1" "$line2" "$reset"
}

fzf_start() {
  if ! command -v fzf >/dev/null 2>&1; then
    echo "astra: fzf is required" >&2
    return 1
  fi

  while true; do
    local header preview_cmd expect output status key paths=()
    fzf_capture_terminal_size
    header=$(fzf_header_text)
    preview_cmd="$(printf '%q' "$ASTRA_ROOT/bin/astra") --preview-only {2}"
    expect="enter,ctrl-m,right,l,left,h,ctrl-q,ctrl-c,ctrl-e,ctrl-r,ctrl-y,alt-m,ctrl-d,ctrl-b,ctrl-n,ctrl-p,.,ctrl-g,?"

    mapfile -t ASTRA_LAST_LISTING < <(search_list_directory "$ASTRA_CWD" "$ASTRA_SHOW_HIDDEN")
    if [[ ${#ASTRA_LAST_LISTING[@]} -eq 0 ]]; then
      ASTRA_LAST_LISTING=($'\t')
    fi

    local footer_opts=()
    if [[ -t 1 ]]; then
      footer_opts=(--footer "$(fzf_controls_footer)" --footer-border=none)
    fi

    output=$(printf '%s\n' "${ASTRA_LAST_LISTING[@]}" | \
      FZF_DEFAULT_OPTS='' fzf --ansi --multi --delimiter=$'\t' --with-nth=1 --expect "$expect" \
          --preview-window='right:60%,border-left' --preview "$preview_cmd" \
          --bind 'space:toggle' --no-sort --layout=default "${footer_opts[@]}" --header "$header") || status=$?

    if [[ ${status:-0} -ne 0 ]]; then
      break
    fi
    unset status

    local raw_lines=()
    mapfile -t raw_lines <<<"$output"
    if [[ ${#raw_lines[@]} -eq 0 ]]; then
      break
    fi

    key="${raw_lines[0]}"
    local selection_lines=()
    if (( ${#raw_lines[@]} > 1 )); then
      selection_lines=("${raw_lines[@]:1}")
    fi

    if [[ ${#selection_lines[@]} -eq 0 ]]; then
      if [[ -n "$key" && "$key" == *$'\t'* ]]; then
        selection_lines=("$key")
        key="enter"
      else
        selection_lines=("${raw_lines[0]}")
        key="enter"
      fi
    fi

    if [[ -z "$key" ]]; then
      key="enter"
    fi

    paths=()
    local line
    for line in "${selection_lines[@]}"; do
      [[ -z "$line" ]] && continue
      paths+=("$(search_extract_path "$line")")
    done

    if [[ ${#paths[@]} -eq 0 ]]; then
      continue
    fi

    log_debug "fzf key=$key paths=${paths[*]} cwd=$ASTRA_CWD"

    ASTRA_NAV_CHANGED=0

    case "$key" in
      ctrl-q|ctrl-c)
        break
        ;;
      enter|ctrl-m|right|l)
        fzf_handle_open "${paths[@]}"
        if [[ ${ASTRA_NAV_CHANGED:-0} -eq 1 ]]; then
          continue
        fi
        ;;
      h|left)
        fzf_handle_up
        if [[ ${ASTRA_NAV_CHANGED:-0} -eq 1 ]]; then
          continue
        fi
        ;;
      .)
        state_toggle_hidden
        continue
        ;;
      ctrl-e)
        fzf_handle_action "edit" "${paths[0]}"
        ;;
      ctrl-r)
        fzf_handle_action "rename" "${paths[0]}"
        ;;
      ctrl-y)
        fzf_handle_action "copy" "${paths[@]}"
        ;;
      alt-m)
        fzf_handle_action "move" "${paths[@]}"
        ;;
      ctrl-d)
        fzf_handle_action "delete" "${paths[@]}"
        ;;
      ctrl-b)
        fzf_handle_action "mkdir"
        ;;
      ctrl-n)
        fzf_handle_action "touch"
        ;;
      ctrl-p)
        fzf_handle_action "properties" "${paths[0]}"
        ;;
      ctrl-g)
        fzf_search_dialog
        ;;
      ?)
        fzf_show_help
        ;;
      *)
        log_debug "Unhandled key: $key"
        ;;
    esac
  done

}

fzf_header_text() {
  local hidden_status
  if [[ "$ASTRA_SHOW_HIDDEN" == true ]]; then
    hidden_status="hidden:on"
  else
    hidden_status="hidden:off"
  fi
  printf '%s  [%s]' "$ASTRA_CWD" "$hidden_status"
}

fzf_handle_open() {
  local path
  if [[ $# -eq 0 ]]; then
    return
  fi
  for path in "$@"; do
    log_debug "handle_open candidate=$path"
    if [[ -d "$path" ]]; then
      state_change_dir "$path"
      return 0
    fi
  done
  if [[ -n "$1" && -f "$1" ]]; then
    fzf_handle_action "open" "$1"
  fi
}

fzf_handle_up() {
  local parent
  parent="$(dirname "$ASTRA_CWD")"
  if [[ "$parent" != "$ASTRA_CWD" ]]; then
    state_change_dir "$parent"
  fi
}

fzf_handle_action() {
  local action="$1"
  shift || true
  actions_dispatch "$action" "$@"
}

fzf_show_help() {
  cat <<'HELP'
Key bindings:
  enter / → / l   open
  ← / h           up one directory
  ctrl-e          edit
  ctrl-r          rename
  ctrl-y          copy
  alt-m           move
  ctrl-d          delete
  ctrl-b          new directory
  ctrl-n          new file
  ctrl-p          properties
  ctrl-g          search
  .               toggle hidden files
  space           toggle selection
  ctrl-q          quit
HELP
  read -r -p "Press Enter to continue" _dummy
}

fzf_search_dialog() {
  read -r -p "Search pattern: " query
  if [[ -z "$query" ]]; then
    return
  fi
  local matches
  matches=$(search_name "$ASTRA_CWD" "$query" "$ASTRA_SHOW_HIDDEN") || return
  if [[ -z "$matches" ]]; then
    echo "No matches"
    read -r -p "Press Enter to continue" _dummy
    return
  fi
  local preview_cmd="$(printf '%q' "$ASTRA_ROOT/bin/astra") --preview-only {}"
  local selection
  selection=$(printf '%s\n' "$matches" | fzf --ansi --header "Search results" --preview "$preview_cmd") || return
  if [[ -z "$selection" ]]; then
    return
  fi
  if [[ -d "$selection" ]]; then
    state_change_dir "$selection"
  else
    actions_dispatch "open" "$selection"
  fi
}
