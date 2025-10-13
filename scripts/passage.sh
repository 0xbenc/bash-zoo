#!/usr/bin/env bash
set -euo pipefail

# passage: Interactive GNU Pass browser with pins + MRU and slot hotkeys
# UX: Single fzf with right-side preview; no nested menus; no TOTP.
# Requires: pass, fzf, and a clipboard tool (pbcopy/wl-copy/xclip/xsel).

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

# Slot letters for quick-select (skip 'c' like mfa)
CHOICE_SYMBOLS=(a b d e f g h i j k l m n o p q r s t u v w x y z)
CHOICE_SYMBOL_COUNT=${#CHOICE_SYMBOLS[@]}

index_to_choice_key() {
  local idx="$1" key="" remainder char
  while true; do
    remainder=$((idx % CHOICE_SYMBOL_COUNT))
    char="${CHOICE_SYMBOLS[$remainder]}"
    key="$char$key"
    idx=$(((idx / CHOICE_SYMBOL_COUNT) - 1))
    (( idx < 0 )) && break
  done
  printf '%s' "$key"
}

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

copy_to_clipboard() {
  local text="$1"
  if command -v pbcopy >/dev/null 2>&1; then printf '%s' "$text" | pbcopy; return 0; fi
  if command -v wl-copy >/dev/null 2>&1; then printf '%s' "$text" | wl-copy; return 0; fi
  if command -v xclip   >/dev/null 2>&1; then printf '%s' "$text" | xclip -selection clipboard; return 0; fi
  if command -v xsel    >/dev/null 2>&1; then printf '%s' "$text" | xsel --clipboard --input; return 0; fi
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

# Preview helpers via subcommands
preview_render_line() {
  # Input: one TSV line: idx, slot, display, path, pin, used
  local line="$1"
  local idx slot display path pin used
  IFS=$'\t' read -r idx slot display path pin used <<< "$line"
  # Header with key cheatsheet
  printf '%sKeys:%s c=Copy  r=Reveal  p=Pin/Unpin  O=Unpin-all  R=Clear-recents  x=Clear-clipboard  b/h=Hide  Esc=Quit\n' "$BOLD$FG_CYAN" "$RESET"
  printf '\n'
  if [[ -z "${path:-}" ]]; then
    printf '%sSelect an entry to view actions.%s\n' "$DIM" "$RESET"
    return 0
  fi
  # Entry details
  printf '%sEntry:%s %s\n' "$BOLD$FG_MAGENTA" "$RESET" "$display"
  printf '%sPath:%s  %s\n' "$DIM" "$RESET" "$path"
  local used_h
  used_h="$(epoch_to_hms "${used:-0}")"
  printf '%sPinned:%s %s   %sLast Used:%s %s\n' "$DIM" "$RESET" "${pin:-0}" "$DIM" "$RESET" "$used_h"
  printf '\n'
  # Mode/data files
  local mode_file data_file mode
  mode_file="${PREVIEW_MODE_FILE-}"
  data_file="${PREVIEW_DATA_FILE-}"
  if [[ -n "${mode_file}" && -f "$mode_file" ]]; then
    mode="$(cat "$mode_file" 2>/dev/null || printf 'help')"
  else
    mode="help"
  fi
  case "$mode" in
    result:copy)
      printf '%s%sOK:%s Password copied.%s\n' "$FG_GREEN" "$BOLD" "$RESET" "$RESET"
      if [[ -f "$data_file" ]]; then
        printf '%s%s%s\n' "$DIM" "$(cat "$data_file" 2>/dev/null | head -n 1)" "$RESET"
      fi
      ;;
    result:reveal)
      printf '%s%sRevealed Password%s\n\n' "$BOLD" "$FG_MAGENTA" "$RESET"
      if [[ -f "$data_file" ]]; then
        printf '%s%s%s\n\n' "$BOLD$FG_CYAN" "$(cat "$data_file" 2>/dev/null | head -n 1)" "$RESET"
      fi
      printf '%sPress h to hide from preview.%s\n' "$DIM" "$RESET"
      ;;
    note)
      if [[ -f "$data_file" ]]; then
        cat "$data_file" 2>/dev/null
      fi
      ;;
    *)
      printf '%sActions:%s\n' "$BOLD" "$RESET"
      printf '  c  Copy password to clipboard\n'
      printf '  r  Reveal password in this preview (also copies)\n'
      printf '  p  Toggle pin for this entry\n'
      printf '  O  Unpin all  |  R  Clear recents\n'
      printf '  x  Clear clipboard  |  h  Hide preview result\n'
      ;;
  esac
}

set_preview_mode() {
  local mode="$1" data_line="$2"
  local mf df
  mf="${PREVIEW_MODE_FILE-}"
  df="${PREVIEW_DATA_FILE-}"
  [[ -n "$mf" ]] && { printf '%s' "$mode" >"$mf"; } || true
  if [[ -n "$df" ]]; then
    : >"$df"
    [[ -n "${data_line:-}" ]] && printf '%s\n' "$data_line" >>"$df"
  fi
}

# Action subcommands for fzf binds
subcmd_copy() {
  local path="$1" ts tool msg c p1
  c=$(pass_decrypt "$path") || die "Failed to decrypt '$path'."
  p1="$(parse_password "$c")"
  ts="$(date +%H:%M:%S)"
  tool=""
  if command -v pbcopy >/dev/null 2>&1; then printf '%s' "$p1" | pbcopy; tool="pbcopy"; elif command -v wl-copy >/dev/null 2>&1; then printf '%s' "$p1" | wl-copy; tool="wl-copy"; elif command -v xclip >/dev/null 2>&1; then printf '%s' "$p1" | xclip -selection clipboard; tool="xclip"; elif command -v xsel >/dev/null 2>&1; then printf '%s' "$p1" | xsel --clipboard --input; tool="xsel"; fi
  state_load; state_touch "$path"; state_save
  if [[ -n "$tool" ]]; then msg="Copied via $tool at $ts"; else msg="No clipboard tool found"; fi
  set_preview_mode "result:copy" "$msg"
}

subcmd_reveal() {
  local path="$1" p2 c2 msg tool
  c2=$(pass_decrypt "$path") || die "Failed to decrypt '$path'."
  p2="$(parse_password "$c2")"
  tool=""
  if command -v pbcopy >/dev/null 2>&1; then printf '%s' "$p2" | pbcopy; tool="pbcopy"; elif command -v wl-copy >/dev/null 2>&1; then printf '%s' "$p2" | wl-copy; tool="wl-copy"; elif command -v xclip >/dev/null 2>&1; then printf '%s' "$p2" | xclip -selection clipboard; tool="xclip"; elif command -v xsel >/dev/null 2>&1; then printf '%s' "$p2" | xsel --clipboard --input; tool="xsel"; fi
  state_load; state_touch "$path"; state_save
  set_preview_mode "result:reveal" "$p2"
  if [[ -n "$tool" ]]; then :; else :; fi
}

subcmd_pin_toggle() {
  local path="$1"
  state_load; state_toggle_pin "$path"; state_save
  set_preview_mode "note" "Pin toggled."
}

subcmd_unpin_all() { state_load; state_unpin_all; state_save; set_preview_mode "note" "All pins cleared."; }
subcmd_clear_recents() { state_load; state_clear_recents; state_save; set_preview_mode "note" "Recents cleared."; }
subcmd_clear_clipboard() {
  local tool
  tool=""
  if command -v pbcopy >/dev/null 2>&1; then printf '' | pbcopy; tool="pbcopy"; elif command -v wl-copy >/dev/null 2>&1; then printf '' | wl-copy; tool="wl-copy"; elif command -v xclip >/dev/null 2>&1; then printf '' | xclip -selection clipboard; tool="xclip"; elif command -v xsel >/dev/null 2>&1; then printf '' | xsel --clipboard --input; tool="xsel"; fi
  if [[ -n "$tool" ]]; then set_preview_mode "note" "Clipboard cleared."; else set_preview_mode "note" "No clipboard tool found."; fi
}
subcmd_hide() { set_preview_mode "help" ""; }

# Emit current fzf input lines: idx, slot, display, path, pin, used
emit_fzf_input() {
  local rows idx path display slot pin used
  idx=0
  while IFS=$'\t' read -r path display pin used; do
    slot="$(index_to_choice_key "$idx")"
    printf '%s\t%s%s%s\t%s\t%s\t%s\t%s\n' \
      "$idx" "$BOLD$FG_CYAN" "$slot" "$RESET" \
      "$display" "$path" "$pin" "$used"
    idx=$((idx + 1))
  done < <(build_sorted_listing)
}

require_deps() { command -v pass >/dev/null 2>&1 || die "Missing dependency: pass"; command -v fzf >/dev/null 2>&1 || die "Missing dependency: fzf"; }

main_loop() {
  local header prompt
  while true; do
    header=$(printf '%sKeys:%s c=Copy  r=Reveal  p=Pin/Unpin  O=Unpin-all  R=Clear-recents  x=Clear-clipboard  b/h=Hide  Esc=Quit' "$BOLD$FG_CYAN" "$RESET")
    prompt=$(printf '%s:: Search >%s ' "$BOLD$FG_MAGENTA" "$RESET")

    # Ensure there are entries
    local any; any=$(discover_entries | head -n1 || true)
    [[ -n "$any" ]] || die "No pass entries found under '$PASSWORD_STORE_DIR'."

    # Build initial input and slot binds
    local listing tmp_input tmp_bind
    listing=$(mktemp "${TMPDIR:-/tmp}/passage_list.XXXXXX"); build_sorted_listing > "$listing"
    tmp_input=$(mktemp "${TMPDIR:-/tmp}/passage_input.XXXXXX")
    tmp_bind=$(mktemp "${TMPDIR:-/tmp}/passage_bind.XXXXXX")

    local idx=0 p d pin used slot
    while IFS=$'\t' read -r p d pin used; do
      slot="$(index_to_choice_key "$idx")"
      printf '%s\t%s%s%s\t%s\t%s\t%s\t%s\n' "$idx" "$BOLD$FG_CYAN" "$slot" "$RESET" "$d" "$p" "$pin" "$used" >> "$tmp_input"
      if [[ ${#slot} -eq 1 ]]; then printf '%s\t%s\n' "$idx" "$slot" >> "$tmp_bind"; fi
      idx=$((idx + 1))
    done < "$listing"

    # Preview state files
    export PREVIEW_MODE_FILE PREVIEW_DATA_FILE
    PREVIEW_MODE_FILE=$(mktemp "${TMPDIR:-/tmp}/passage_mode.XXXXXX"); printf 'help' >"$PREVIEW_MODE_FILE"
    PREVIEW_DATA_FILE=$(mktemp "${TMPDIR:-/tmp}/passage_data.XXXXXX"); : >"$PREVIEW_DATA_FILE"

    # Build dynamic binds for slot keys
    local bind_args=()
    while IFS=$'\t' read -r rid rkey; do
      local jump="" steps upper
      steps=$rid; while (( steps > 0 )); do jump+="+down"; steps=$((steps - 1)); done
      # ctrl-letter -> Copy
      bind_args+=( "--bind" "ctrl-${rkey}:first${jump}+execute-silent(${0} __action_copy {4})+refresh-preview" )
      # alt-letter -> Copy
      bind_args+=( "--bind" "alt-${rkey}:first${jump}+execute-silent(${0} __action_copy {4})+refresh-preview" )
      # alt-Upper -> Reveal
      upper="$(printf '%s' "$rkey" | tr '[:lower:]' '[:upper:]')"
      bind_args+=( "--bind" "alt-${upper}:first${jump}+execute-silent(${0} __action_reveal {4})+refresh-preview" )
    done < "$tmp_bind"

    # Global binds on current selection
    bind_args+=( "--bind" "c:execute-silent(${0} __action_copy {4})+refresh-preview" )
    bind_args+=( "--bind" "r:execute-silent(${0} __action_reveal {4})+refresh-preview" )
    bind_args+=( "--bind" "p:execute-silent(${0} __action_pin_toggle {4})+reload(cat ${tmp_input})+refresh-preview" )
    bind_args+=( "--bind" "O:execute-silent(${0} __action_unpin_all)+reload(cat ${tmp_input})+refresh-preview" )
    bind_args+=( "--bind" "R:execute-silent(${0} __action_clear_recents)+reload(cat ${tmp_input})+refresh-preview" )
    bind_args+=( "--bind" "x:execute-silent(${0} __action_clear_clipboard)+refresh-preview" )
    bind_args+=( "--bind" "b:execute-silent(${0} __action_hide)+refresh-preview" )
    bind_args+=( "--bind" "h:execute-silent(${0} __action_hide)+refresh-preview" )

    # Run fzf; no --expect; rely on binds and Esc to quit
    if ! fzf --ansi --with-nth=2,3 --delimiter=$'\t' \
         --prompt "$prompt" --height=80% --layout=reverse --border --info=inline \
         --header "$header" --no-sort --tiebreak=index \
         --preview "${0} __preview {}" --preview-window=right,60%,border,wrap \
         "${bind_args[@]}" < "$tmp_input" > /dev/null; then
      printf '%sExiting.%s\n' "$DIM" "$RESET"
      rm -f "$listing" "$tmp_input" "$tmp_bind" "$PREVIEW_MODE_FILE" "$PREVIEW_DATA_FILE"
      break
    fi
    rm -f "$listing" "$tmp_input" "$tmp_bind" "$PREVIEW_MODE_FILE" "$PREVIEW_DATA_FILE"
  done
}

main() { require_deps; state_load; main_loop; }

# Subcommand entry points for fzf preview/actions
case "${1-}" in
  __preview)
    # Input is the full current line as one argument; ensure colors available
    preview_render_line "${2-}"
    exit 0 ;;
  __action_copy)
    PREVIEW_MODE_FILE="${PREVIEW_MODE_FILE-}" PREVIEW_DATA_FILE="${PREVIEW_DATA_FILE-}" subcmd_copy "${2-}"
    exit 0 ;;
  __action_reveal)
    PREVIEW_MODE_FILE="${PREVIEW_MODE_FILE-}" PREVIEW_DATA_FILE="${PREVIEW_DATA_FILE-}" subcmd_reveal "${2-}"
    exit 0 ;;
  __action_pin_toggle)
    PREVIEW_MODE_FILE="${PREVIEW_MODE_FILE-}" PREVIEW_DATA_FILE="${PREVIEW_DATA_FILE-}" subcmd_pin_toggle "${2-}"
    exit 0 ;;
  __action_unpin_all)
    PREVIEW_MODE_FILE="${PREVIEW_MODE_FILE-}" PREVIEW_DATA_FILE="${PREVIEW_DATA_FILE-}" subcmd_unpin_all
    exit 0 ;;
  __action_clear_recents)
    PREVIEW_MODE_FILE="${PREVIEW_MODE_FILE-}" PREVIEW_DATA_FILE="${PREVIEW_DATA_FILE-}" subcmd_clear_recents
    exit 0 ;;
  __action_clear_clipboard)
    PREVIEW_MODE_FILE="${PREVIEW_MODE_FILE-}" PREVIEW_DATA_FILE="${PREVIEW_DATA_FILE-}" subcmd_clear_clipboard
    exit 0 ;;
  __action_hide)
    PREVIEW_MODE_FILE="${PREVIEW_MODE_FILE-}" PREVIEW_DATA_FILE="${PREVIEW_DATA_FILE-}" subcmd_hide
    exit 0 ;;
esac

main "$@"
