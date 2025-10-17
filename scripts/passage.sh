#!/usr/bin/env bash
set -euo pipefail

# passage: Interactive GNU Pass browser with pins + MRU
# UX: Simple text menu (no fzf); no nested preview; no TOTP.
# Requires: pass and a clipboard tool (pbcopy/wl-copy/xclip/xsel).

PASSWORD_STORE_DIR="${PASSWORD_STORE_DIR:-$HOME/.password-store}"

# State (pins + MRU)
STATE_DIR_DEFAULT="$HOME/.local/state"
STATE_DIR="${XDG_STATE_HOME:-$STATE_DIR_DEFAULT}/bash-zoo/passage"
STATE_FILE="$STATE_DIR/state.tsv"

# Colors
BOLD=""; DIM=""; FG_BLUE=""; FG_GREEN=""; FG_YELLOW=""; FG_MAGENTA=""; FG_RED=""; FG_CYAN=""; FG_WHITE=""; RESET=""
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
  colors="$(tput colors 2>/dev/null || printf '0')"
  if [[ "$colors" =~ ^[0-9]+$ ]] && [[ "$colors" -ge 8 ]]; then
    BOLD="$(tput bold 2>/dev/null || printf '')"
    DIM="$(tput dim 2>/dev/null || printf '')"
    FG_BLUE="$(tput setaf 4 2>/dev/null || printf '')"
    FG_GREEN="$(tput setaf 2 2>/dev/null || printf '')"
    FG_YELLOW="$(tput setaf 3 2>/dev/null || printf '')"
    FG_MAGENTA="$(tput setaf 5 2>/dev/null || printf '')"
    FG_RED="$(tput setaf 1 2>/dev/null || printf '')"
    FG_CYAN="$(tput setaf 6 2>/dev/null || printf '')"
    FG_WHITE="$(tput setaf 7 2>/dev/null || printf '')"
    RESET="$(tput sgr0 2>/dev/null || printf '')"
  else
    RESET="$(tput sgr0 2>/dev/null || printf '')"
  fi
fi
: "${BOLD:=}"; : "${DIM:=}"; : "${FG_BLUE:=}"; : "${FG_GREEN:=}"; : "${FG_YELLOW:=}"; : "${FG_MAGENTA:=}"; : "${FG_RED:=}"; : "${FG_CYAN:=}"; : "${FG_WHITE:=}"; : "${RESET:=}"

die() { printf '%s%sError:%s %s\n' "$FG_RED" "$BOLD" "$RESET" "$1" >&2; exit 1; }

# Portable date rendering for epoch -> human local time
epoch_to_hms() {
  local epoch="$1"
  if date -d @0 +%H:%M:%S >/dev/null 2>&1; then
    date -d "@${epoch}" +%H:%M:%S
  else
    date -r "${epoch}" +%H:%M:%S
  fi
}

ensure_state_dir() { mkdir -p "$STATE_DIR"; }

# Lowercase helper
to_lower() { tr '[:upper:]' '[:lower:]'; }

# In-memory state
state_paths=(); state_pins=(); state_used=()

state_load() {
  ensure_state_dir
  # Migrate old state file from pass-browse if present
  if [[ ! -f "$STATE_FILE" ]]; then
    local old_state
    old_state="${XDG_STATE_HOME:-$STATE_DIR_DEFAULT}/bash-zoo/pass-browse/state.tsv"
    if [[ -f "$old_state" ]]; then
      cp -f "$old_state" "$STATE_FILE" 2>/dev/null || true
    fi
  fi
  state_paths=(); state_pins=(); state_used=()
  if [[ -f "$STATE_FILE" ]]; then
    while IFS=$'\t' read -r p pin used; do
      [[ -z "${p:-}" ]] && continue
      : "${pin:=0}"; : "${used:=0}"
      state_paths+=("$p"); state_pins+=("$pin"); state_used+=("$used")
    done < "$STATE_FILE"
  fi
}

state_save() {
  ensure_state_dir
  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/passage_state.XXXXXX")
  local i
  for i in "${!state_paths[@]}"; do
    printf '%s\t%s\t%s\n' "${state_paths[$i]}" "${state_pins[$i]}" "${state_used[$i]}" >> "$tmp"
  done
  mv "$tmp" "$STATE_FILE"
}

state_find_index() {
  local path="$1" i
  for i in "${!state_paths[@]}"; do
    [[ "${state_paths[$i]}" == "$path" ]] && { printf '%s' "$i"; return 0; }
  done
  printf '%s' "-1"; return 1
}

state_touch() {
  local path="$1" now idx
  now=$(date +%s)
  idx=$(state_find_index "$path" || true)
  if [[ "$idx" == "-1" ]]; then
    state_paths+=("$path"); state_pins+=("0"); state_used+=("$now")
  else
    state_used[$idx]="$now"
  fi
}

state_get_pin() {
  local path="$1" idx
  idx=$(state_find_index "$path" || true)
  if [[ "$idx" == "-1" ]]; then printf '0'; else printf '%s' "${state_pins[$idx]}"; fi
}

state_set_pin() {
  local path="$1" val="$2" idx
  idx=$(state_find_index "$path" || true)
  if [[ "$idx" == "-1" ]]; then
    state_paths+=("$path"); state_pins+=("$val"); state_used+=("0")
  else
    state_pins[$idx]="$val"
  fi
}

state_toggle_pin() { local path="$1"; [[ "$(state_get_pin "$path")" == 1 ]] && state_set_pin "$path" 0 || state_set_pin "$path" 1; }
state_unpin_all() { local i; for i in "${!state_pins[@]}"; do state_pins[$i]="0"; done; }
state_clear_recents() { local i; for i in "${!state_used[@]}"; do state_used[$i]="0"; done; }

format_label() { local entry="$1"; printf '%s' "${entry//\// > }"; }

CLIPBOARD_TOOL_LAST=""
clipboard_copy() {
  local text="$1"
  CLIPBOARD_TOOL_LAST=""
  if command -v pbcopy >/dev/null 2>&1; then
    if printf '%s' "$text" | pbcopy >/dev/null 2>&1; then CLIPBOARD_TOOL_LAST="pbcopy"; return 0; fi
  fi
  # Choose order based on session
  local try_wayland=0
  if [[ -n "${WAYLAND_DISPLAY-}" ]]; then try_wayland=1; fi
  if (( try_wayland )); then
    if command -v wl-copy >/dev/null 2>&1; then
      if printf '%s' "$text" | wl-copy >/dev/null 2>&1; then CLIPBOARD_TOOL_LAST="wl-copy"; return 0; fi
    fi
    if command -v xclip >/dev/null 2>&1; then
      if printf '%s' "$text" | xclip -selection clipboard >/dev/null 2>&1; then CLIPBOARD_TOOL_LAST="xclip"; return 0; fi
    fi
  else
    if command -v xclip >/dev/null 2>&1; then
      if printf '%s' "$text" | xclip -selection clipboard >/dev/null 2>&1; then CLIPBOARD_TOOL_LAST="xclip"; return 0; fi
    fi
    if command -v wl-copy >/dev/null 2>&1; then
      if printf '%s' "$text" | wl-copy >/dev/null 2>&1; then CLIPBOARD_TOOL_LAST="wl-copy"; return 0; fi
    fi
  fi
  if command -v xsel >/dev/null 2>&1; then
    if printf '%s' "$text" | xsel --clipboard --input >/dev/null 2>&1; then CLIPBOARD_TOOL_LAST="xsel"; return 0; fi
  fi
  return 1
}

discover_entries() {
  [[ -d "$PASSWORD_STORE_DIR" ]] || die "Password store directory '$PASSWORD_STORE_DIR' does not exist."
  find "$PASSWORD_STORE_DIR" -type f -name '*.gpg' -print | while IFS= read -r file; do
    local rel="${file#$PASSWORD_STORE_DIR/}"; rel="${rel%.gpg}"; printf '%s\n' "$rel"
  done | sort -u
}

build_sorted_listing() {
  # Output: path<TAB>display<TAB>pin<TAB>used
  local entries_tmp rows path pin used idx label star
  entries_tmp=$(mktemp "${TMPDIR:-/tmp}/passage_entries.XXXXXX")
  discover_entries > "$entries_tmp"

  rows=$(mktemp "${TMPDIR:-/tmp}/passage_rows.XXXXXX")
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    pin=$(state_get_pin "$path")
    idx=$(state_find_index "$path" || true)
    used=0; [[ "$idx" != "-1" ]] && used="${state_used[$idx]}"
    label="$(format_label "$path")"; star=""; [[ "$pin" == "1" ]] && star="${FG_YELLOW}★ ${RESET}"
    printf '%s\t%010d\t%s\t%s%s\t%s\t%s\n' "$pin" "$used" "$path" "$star" "$label" "$pin" "$used" >> "$rows"
  done < "$entries_tmp"
  sort -t $'\t' -k1,1nr -k2,2nr -k3,3 "$rows" | awk -F '\t' '{ printf "%s\t%s\t%s\t%s\n", $3, $4, $6, $7 }'
  rm -f "$entries_tmp" "$rows"
}

pass_decrypt() { pass show -- "$1"; }
parse_password() { local content="$1"; printf '%s' "${content%%$'\n'*}"; }

## parse_fields removed (field operations no longer supported)

msg_ok()   { printf '%s%sOK:%s %s\n' "$FG_GREEN" "$BOLD" "$RESET" "$1" >&2; }
msg_note() { printf '%s%sNote:%s %s\n' "$FG_BLUE" "$BOLD" "$RESET" "$1" >&2; }
msg_warn() { printf '%s%sWarn:%s %s\n' "$FG_YELLOW" "$BOLD" "$RESET" "$1" >&2; }

reveal_until_clear() {
  local title="$1" secret="$2"
  if command -v tput >/dev/null 2>&1; then tput clear; else printf '\033[2J\033[H'; fi
  printf '%s%sReveal:%s %s\n\n' "$BOLD" "$FG_MAGENTA" "$RESET" "$title"
  printf '%s%s%s\n\n' "$BOLD" "$FG_CYAN" "$secret" "$RESET"
  printf '%sPress Enter to clear...%s\n' "$DIM" "$RESET"
  read -r -s _
  if command -v tput >/dev/null 2>&1; then tput clear; else printf '\033[2J\033[H'; fi
}

require_deps() { command -v pass >/dev/null 2>&1 || die "Missing dependency: pass"; }

# Load current listing into arrays, optionally filtered by a substring.
list_paths=(); list_displays=(); list_pins=(); list_used=()
load_listing_arrays() {
  local filter="${1-}"
  list_paths=(); list_displays=(); list_pins=(); list_used=()
  if [[ -z "$filter" ]]; then
    while IFS=$'\t' read -r p d pin used; do
      list_paths+=("$p"); list_displays+=("$d"); list_pins+=("$pin"); list_used+=("$used")
    done < <(build_sorted_listing)
  else
    local f_lc p_lc d_lc
    f_lc=$(printf '%s' "$filter" | to_lower)
    while IFS=$'\t' read -r p d pin used; do
      p_lc=$(printf '%s' "$p" | to_lower)
      d_lc=$(printf '%s' "$d" | to_lower)
      if [[ "$p_lc" == *"$f_lc"* || "$d_lc" == *"$f_lc"* ]]; then
        list_paths+=("$p"); list_displays+=("$d"); list_pins+=("$pin"); list_used+=("$used")
      fi
    done < <(build_sorted_listing)
  fi
}

print_listing() {
  local total=${#list_paths[@]}
  local i star
  printf '%sEntries:%s %s%d%s\n' "$BOLD$FG_CYAN" "$RESET" "$FG_GREEN" "$total" "$RESET"
  for ((i=0; i<total; i++)); do
    star=""; [[ "${list_pins[$i]}" == "1" ]] && star="${FG_YELLOW}★ ${RESET}"
    printf '  %2d) %s%s%s  %s%s%s\n' \
      $((i+1)) "$BOLD$FG_CYAN" "$star" "$RESET" \
      "$FG_BLUE" "${list_displays[$i]}" "$RESET"
  done
}

perform_copy() {
  local path="$1"
  local c p1 tool
  c=$(pass_decrypt "$path") || die "Failed to decrypt '$path'."
  p1="$(parse_password "$c")"
  if clipboard_copy "$p1"; then
    tool="$CLIPBOARD_TOOL_LAST"
  else
    tool=""
  fi
  state_touch "$path"; state_save
  if [[ -n "$tool" ]]; then msg_ok "Password copied to clipboard ($tool)."; else msg_warn "No clipboard tool found."; fi
}

perform_reveal() {
  local path="$1" c p tool
  c=$(pass_decrypt "$path") || die "Failed to decrypt '$path'."
  p="$(parse_password "$c")"
  if clipboard_copy "$p"; then
    tool="$CLIPBOARD_TOOL_LAST"
  else
    tool=""
  fi
  state_touch "$path"; state_save
  if [[ -n "$tool" ]]; then msg_note "Also copied to clipboard."; else msg_warn "No clipboard tool found; reveal only."; fi
  reveal_until_clear "$(format_label "$path")" "$p"
}

clear_clipboard() {
  local tool
  if clipboard_copy ""; then
    tool="$CLIPBOARD_TOOL_LAST"
    msg_ok "Clipboard cleared ($tool)."
  else
    msg_warn "No clipboard tool found."
  fi
}

options_menu() {
  printf '%sOptions:%s\n' "$BOLD$FG_MAGENTA" "$RESET"
  printf '  1) Unpin all\n'
  printf '  2) Clear recents\n'
  printf '  b) Back\n'
  printf 'Select: '
  local opt; read -r opt || return 0
  case "$opt" in
    1) state_unpin_all; state_save; msg_ok "All pins cleared." ;;
    2) state_clear_recents; state_save; msg_ok "Recents cleared." ;;
    b|'') : ;;
  esac
}

actions_menu_for() {
  local idx="$1"
  local path="${list_paths[$idx]}"
  local display="${list_displays[$idx]}"
  local pin="${list_pins[$idx]}"
  local used_h="$(epoch_to_hms "${list_used[$idx]:-0}")"
  printf '%sEntry:%s %s\n' "$BOLD$FG_MAGENTA" "$RESET" "$display"
  printf '%sPath:%s  %s\n' "$DIM" "$RESET" "$path"
  printf '%sPinned:%s %s   %sLast Used:%s %s\n' "$DIM" "$RESET" "$pin" "$DIM" "$RESET" "$used_h"
  printf '\n%sActions:%s [c]opy  [r]eveal  [p]in/unpin  [x] clear-clipboard  [o]ptions  [b]ack  [q]uit\n' "$BOLD" "$RESET"
  printf 'Select: '
  local act; read -r act || return 0
  case "$act" in
    c|'') perform_copy "$path" ;;
    r) perform_reveal "$path" ;;
    p) state_toggle_pin "$path"; state_save; msg_ok "Pin toggled." ;;
    x) clear_clipboard ;;
    o) options_menu ;;
    b) : ;;
    q) exit 0 ;;
  esac
}

main_loop() {
  local filter=""
  while true; do
    load_listing_arrays "$filter"
    if [[ ${#list_paths[@]} -eq 0 ]]; then
      if [[ -n "$filter" ]]; then
        msg_warn "No entries match filter '$filter'."
        filter=""
        continue
      fi
      die "No pass entries found under '$PASSWORD_STORE_DIR'."
    fi

    printf '%s::%s /term filter | n select | cN/Nc copy | rN/Nr reveal | pN/Np pin | x clear | o options | q quit\n' "$BOLD$FG_CYAN" "$RESET"
    [[ -n "$filter" ]] && printf '%sFilter:%s %s\n' "$DIM" "$RESET" "$filter"
    print_listing
    printf '\nCommand: '
    local cmd; read -r cmd || { printf '\n'; break; }

    # Trim spaces
    cmd="${cmd## }"; cmd="${cmd%% }"
    if [[ -z "$cmd" ]]; then
      continue
    fi

    case "$cmd" in
      q|quit|exit) printf '%sExiting.%s\n' "$DIM" "$RESET"; break ;;
      o) options_menu ;;
      x) clear_clipboard ;;
      /*) filter="${cmd#/}" ;;
      r[0-9]*)
        local n="${cmd#r}"
        if [[ "$n" =~ ^[0-9]+$ ]] && (( n>=1 && n<=${#list_paths[@]} )); then
          perform_reveal "${list_paths[$((n-1))]}"
        else
          msg_warn "Invalid index: $n"
        fi ;;
      [0-9]*r)
        local n="${cmd%r}"
        if [[ "$n" =~ ^[0-9]+$ ]] && (( n>=1 && n<=${#list_paths[@]} )); then
          perform_reveal "${list_paths[$((n-1))]}"
        else
          msg_warn "Invalid index: $n"
        fi ;;
      c[0-9]*)
        local n="${cmd#c}"
        if [[ "$n" =~ ^[0-9]+$ ]] && (( n>=1 && n<=${#list_paths[@]} )); then
          perform_copy "${list_paths[$((n-1))]}"
        else
          msg_warn "Invalid index: $n"
        fi ;;
      [0-9]*c)
        local n="${cmd%c}"
        if [[ "$n" =~ ^[0-9]+$ ]] && (( n>=1 && n<=${#list_paths[@]} )); then
          perform_copy "${list_paths[$((n-1))]}"
        else
          msg_warn "Invalid index: $n"
        fi ;;
      p[0-9]*)
        local n="${cmd#p}"
        if [[ "$n" =~ ^[0-9]+$ ]] && (( n>=1 && n<=${#list_paths[@]} )); then
          state_toggle_pin "${list_paths[$((n-1))]}"; state_save; msg_ok "Pin toggled."
        else
          msg_warn "Invalid index: $n"
        fi ;;
      [0-9]*p)
        local n="${cmd%p}"
        if [[ "$n" =~ ^[0-9]+$ ]] && (( n>=1 && n<=${#list_paths[@]} )); then
          state_toggle_pin "${list_paths[$((n-1))]}"; state_save; msg_ok "Pin toggled."
        else
          msg_warn "Invalid index: $n"
        fi ;;
      [0-9]*)
        local n="$cmd"
        if [[ "$n" =~ ^[0-9]+$ ]] && (( n>=1 && n<=${#list_paths[@]} )); then
          # Show actions menu for this selection; default Enter copies
          actions_menu_for $((n-1))
        else
          msg_warn "Invalid index: $n"
        fi ;;
      *)
        # Treat as new filter token(s)
        filter="$cmd" ;;
    esac
    printf '\n'
  done
}

main() { require_deps; state_load; main_loop; }

main "$@"
