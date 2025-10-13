#!/usr/bin/env bash
set -euo pipefail

# passage: Interactive GNU Pass browser with pins + MRU and slot hotkeys
# Scope: Phase 1 + 4 only (no preview/TOTP). Requires: pass, fzf.

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
  # Output: path<TAB>display
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
    printf '%s\t%010d\t%s\t%s%s\n' "$pin" "$used" "$path" "$star" "$label" >> "$rows"
  done < "$entries_tmp"
  sort -t $'\t' -k1,1nr -k2,2nr -k3,3 "$rows" | awk -F '\t' '{ printf "%s\t%s\n", $3, $4 }'
  rm -f "$entries_tmp" "$rows"
}

pass_decrypt() { pass show -- "$1"; }
parse_password() { local content="$1"; printf '%s' "${content%%$'\n'*}"; }

## parse_fields removed (field operations no longer supported)

reveal_until_clear() {
  local title="$1" secret="$2"
  if command -v tput >/dev/null 2>&1; then tput clear; else printf '\033[2J\033[H'; fi
  printf '%s%sReveal:%s %s\n\n' "$BOLD" "$FG_MAGENTA" "$RESET" "$title"
  printf '%s%s%s\n\n' "$BOLD" "$FG_CYAN" "$secret" "$RESET"
  printf '%sPress Enter to clear...%s\n' "$DIM" "$RESET"
  read -r -s _
  if command -v tput >/dev/null 2>&1; then tput clear; else printf '\033[2J\033[H'; fi
}

msg_ok()   { printf '%s%sOK:%s %s\n' "$FG_GREEN" "$BOLD" "$RESET" "$1" >&2; }
msg_note() { printf '%s%sNote:%s %s\n' "$FG_BLUE" "$BOLD" "$RESET" "$1" >&2; }
msg_warn() { printf '%s%sWarn:%s %s\n' "$FG_YELLOW" "$BOLD" "$RESET" "$1" >&2; }

actions_menu_once() {
  local path="$1" pin
  pin=$(state_get_pin "$path")

  local tmp key_line sel_line header expect_keys out
  tmp=$(mktemp "${TMPDIR:-/tmp}/passage_actions.XXXXXX")
  printf 'Copy password\n' >> "$tmp"
  printf 'Reveal password\n' >> "$tmp"
  if [[ "$pin" == "1" ]]; then printf 'Unpin\n' >> "$tmp"; else printf 'Pin\n' >> "$tmp"; fi
  printf 'Clear clipboard\n' >> "$tmp"
  printf 'Back\n' >> "$tmp"
  printf 'Quit\n' >> "$tmp"

  header=$(printf '%sKeys:%s Alt/Ctrl-c=Copy  Alt/Ctrl-r=Reveal  Alt/Ctrl-p=Pin  Alt/Ctrl-x=Clear  Alt/Ctrl-b=Back  Alt/Ctrl-q=Quit' "$BOLD$FG_CYAN" "$RESET")
  expect_keys="enter,esc,alt-c,alt-r,alt-p,alt-x,alt-b,alt-q,ctrl-c,ctrl-r,ctrl-p,ctrl-x,ctrl-b,ctrl-q"

  out=$(mktemp "${TMPDIR:-/tmp}/passage_actions_out.XXXXXX")
  if ! fzf --prompt "${BOLD}${FG_MAGENTA}Actions:${RESET} " --height=40% --layout=reverse --border --info=hidden --no-sort \
        --header "$header" --expect="$expect_keys" < "$tmp" > "$out"; then
    rm -f "$tmp" "$out"; return 1
  fi
  { IFS= read -r key_line || true; IFS= read -r sel_line || true; } < "$out"
  rm -f "$tmp" "$out"

  case "$key_line" in
    esc) return 0 ;;
    alt-c|ctrl-c)
      local c cp; c=$(pass_decrypt "$path") || die "Failed to decrypt '$path'."; cp="$(parse_password "$c")"
      if copy_to_clipboard "$cp"; then state_touch "$path"; state_save; msg_ok "Password copied to clipboard."; else msg_warn "No clipboard tool found."; fi
      return 0 ;;
    alt-r|ctrl-r)
      local cr pr; cr=$(pass_decrypt "$path") || die "Failed to decrypt '$path'."; pr="$(parse_password "$cr")"
      if copy_to_clipboard "$pr"; then msg_note "Also copied to clipboard."; else msg_warn "No clipboard tool found; reveal only."; fi
      state_touch "$path"; state_save; reveal_until_clear "$(format_label "$path")" "$pr"; return 0 ;;
    # field operations removed
    alt-p|ctrl-p) state_toggle_pin "$path"; state_save; msg_ok "Pin toggled."; return 0 ;;
    alt-x|ctrl-x) if copy_to_clipboard ""; then msg_ok "Clipboard cleared."; else msg_warn "No clipboard tool found."; fi; return 0 ;;
    alt-b|ctrl-b) return 0 ;;
    alt-q|ctrl-q) exit 0 ;;
  esac

  # Fallback: selection by Enter
  local sel="$sel_line" content password
  case "$sel" in
    "Copy password")
      content=$(pass_decrypt "$path") || die "Failed to decrypt '$path'."; password="$(parse_password "$content")"
      if copy_to_clipboard "$password"; then state_touch "$path"; state_save; msg_ok "Password copied to clipboard."; else msg_warn "No clipboard tool found."; fi ;;
    "Reveal password")
      content=$(pass_decrypt "$path") || die "Failed to decrypt '$path'."; password="$(parse_password "$content")"
      if copy_to_clipboard "$password"; then msg_note "Also copied to clipboard."; else msg_warn "No clipboard tool found; reveal only."; fi
      state_touch "$path"; state_save; reveal_until_clear "$(format_label "$path")" "$password" ;;
    # field operations removed
    Pin)   state_set_pin "$path" 1; state_save; msg_ok "Pinned." ;;
    Unpin) state_set_pin "$path" 0; state_save; msg_ok "Unpinned." ;;
    "Clear clipboard") if copy_to_clipboard ""; then msg_ok "Clipboard cleared."; else msg_warn "No clipboard tool found."; fi ;;
    Back) : ;;
    Quit) exit 0 ;;
  esac
  return 0
}

options_menu_once() {
  local tmp sel
  tmp=$(mktemp "${TMPDIR:-/tmp}/passage_opt.XXXXXX")
  printf 'Unpin all\n' >> "$tmp"; printf 'Clear recents\n' >> "$tmp"; printf 'Back\n' >> "$tmp"
  sel=""; if ! sel=$(fzf --prompt "${BOLD}${FG_MAGENTA}Options:${RESET} " --height=30% --layout=reverse --border --info=hidden --no-sort < "$tmp"); then rm -f "$tmp"; return 1; fi
  rm -f "$tmp"
  case "$sel" in "Unpin all") state_unpin_all; state_save; msg_ok "All pins cleared." ;; "Clear recents") state_clear_recents; state_save; msg_ok "Recents cleared." ;; esac
  return 0
}

require_deps() { command -v pass >/dev/null 2>&1 || die "Missing dependency: pass"; command -v fzf >/dev/null 2>&1 || die "Missing dependency: fzf"; }

main_loop() {
  local header prompt key_line line_line path
  while true; do
    header=$(printf '%sKeys:%s Enter=Actions  Ctrl+Letter=Actions  Alt+Letter=Copy  Alt+Shift+Letter=Reveal  Alt-p=Pin/Unpin  Alt-o=Options  Esc=Quit' "$BOLD$FG_CYAN" "$RESET")
    prompt=$(printf '%s:: Search >%s ' "$BOLD$FG_MAGENTA" "$RESET")

    local listing; listing=$(mktemp "${TMPDIR:-/tmp}/passage_list.XXXXXX"); build_sorted_listing > "$listing"
    [[ -s "$listing" ]] || { rm -f "$listing"; die "No pass entries found under '$PASSWORD_STORE_DIR'."; }

    local tmp_input tmp_bind; tmp_input=$(mktemp "${TMPDIR:-/tmp}/passage_input.XXXXXX"); tmp_bind=$(mktemp "${TMPDIR:-/tmp}/passage_bind.XXXXXX")
    local idx=0 p d slot
    while IFS=$'\t' read -r p d; do
      slot="$(index_to_choice_key "$idx")"
      printf '%s\t%s%s%s\t%s\t%s\n' "$idx" "$BOLD$FG_CYAN" "$slot" "$RESET" "$d" "$p" >> "$tmp_input"
      if [[ ${#slot} -eq 1 ]]; then printf '%s\t%s\n' "$idx" "$slot" >> "$tmp_bind"; fi
      idx=$((idx + 1))
    done < "$listing"

    local bind_args=() expect_keys=(enter alt-p alt-o esc)
    while IFS=$'\t' read -r rid rkey; do
      local jump="" steps upper
      steps=$rid; while (( steps > 0 )); do jump+="+down"; steps=$((steps - 1)); done
      bind_args+=( "--bind" "ctrl-${rkey}:first${jump}+accept" ); expect_keys+=( "ctrl-${rkey}" )
      bind_args+=( "--bind" "alt-${rkey}:first${jump}+accept" );  expect_keys+=( "alt-${rkey}" )
      upper="$(printf '%s' "$rkey" | tr '[:lower:]' '[:upper:]')"
      bind_args+=( "--bind" "alt-${upper}:first${jump}+accept" ); expect_keys+=( "alt-${upper}" )
    done < "$tmp_bind"

    local expect_arg; expect_arg=$(printf '%s,' "${expect_keys[@]}"); expect_arg=${expect_arg%,}
    local tmpout; tmpout=$(mktemp "${TMPDIR:-/tmp}/passage_out.XXXXXX")
    if ! fzf --ansi --with-nth=2,3 --delimiter=$'\t' \
         --prompt "$prompt" --height=80% --layout=reverse --border --info=inline \
         --header "$header" --no-sort --tiebreak=index --expect="$expect_arg" \
         "${bind_args[@]}" < "$tmp_input" > "$tmpout"; then
      rm -f "$listing" "$tmp_input" "$tmp_bind" "$tmpout"; printf '%sExiting.%s\n' "$DIM" "$RESET"; break
    fi
    { IFS= read -r key_line || true; IFS= read -r line_line || true; } < "$tmpout"
    rm -f "$listing" "$tmp_input" "$tmp_bind" "$tmpout"
    if [[ "$key_line" == "esc" || -z "${line_line:-}" ]]; then printf '%sExiting.%s\n' "$DIM" "$RESET"; break; fi

    # Parse selection: idx slot display path
    local line_rest sel_path
    line_rest="${line_line#*$'\t'}"; line_rest="${line_rest#*$'\t'}"; line_rest="${line_rest#*$'\t'}"; sel_path="$line_rest"
    path="$sel_path"

    case "$key_line" in
      enter|ctrl-*)
        actions_menu_once "$path" || true ;;
      alt-p) state_toggle_pin "$path"; state_save; msg_ok "Pin toggled." ;;
      alt-o) options_menu_once || true ;;
      alt-[a-z])
        # Quick copy via Alt+letter
        local c p1; if c=$(pass_decrypt "$path"); then p1="$(parse_password "$c")"; if copy_to_clipboard "$p1"; then state_touch "$path"; state_save; msg_ok "Password copied."; else msg_warn "No clipboard tool found."; fi; else msg_warn "Decrypt failed for '$path'"; fi ;;
      alt-[A-Z])
        # Quick reveal via Alt+Shift+letter (also copies)
        local c2 p2; if c2=$(pass_decrypt "$path"); then p2="$(parse_password "$c2")"; if copy_to_clipboard "$p2"; then msg_note "Also copied to clipboard."; else msg_warn "No clipboard tool found; reveal only."; fi; state_touch "$path"; state_save; reveal_until_clear "$(format_label "$path")" "$p2"; else msg_warn "Decrypt failed for '$path'"; fi ;;
    esac
  done
}

main() { require_deps; state_load; main_loop; }

main "$@"
