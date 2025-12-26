#!/usr/bin/env bash
set -euo pipefail

# passage: Interactive GNU Pass browser with pins + MRU
# UX: Simple text menu (no fzf); no nested preview; built‑in TOTP (MFA) helpers.
# Requires: pass and a clipboard tool (pbcopy/wl-copy/xclip/xsel). For TOTP, `oathtool`.

PASSWORD_STORE_DIR="${PASSWORD_STORE_DIR:-$HOME/.password-store}"

# State (pins + MRU)
STATE_DIR_DEFAULT="$HOME/.local/state"
STATE_DIR="${XDG_STATE_HOME:-$STATE_DIR_DEFAULT}/bash-zoo/passage"
STATE_FILE="$STATE_DIR/state.tsv"

# TOTP window (seconds)
TOTP_WINDOW=30

# Colors
BOLD=""; DIM=""; FG_BLUE=""; FG_GREEN=""; FG_YELLOW=""; FG_MAGENTA=""; FG_RED=""; FG_CYAN=""; FG_WHITE=""; RESET=""
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
  colors="$(tput colors 2>/dev/null || printf '0')"
  if [[ "$colors" =~ ^[0-9]+$ ]] && [[ "$colors" -ge 8 ]]; then
    BOLD="$(tput setaf 2 bold 2>/dev/null || printf '')"
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

screen_clear() {
  if [[ -t 1 ]]; then
    if command -v tput >/dev/null 2>&1; then
      tput clear
    else
      printf '\033[2J\033[H'
    fi
  fi
}

# Ensure gpg pinentry can attach to this terminal session on first decrypt.
# This prevents silent failures when gpg-agent needs to prompt but has no TTY.
if [[ -t 0 ]]; then
  export GPG_TTY="$(tty)"
  if command -v gpg-connect-agent >/dev/null 2>&1; then
    gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1 || true
  fi
fi

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

# Mark listing cache dirty to trigger rebuild on next refresh
LISTING_DIRTY=1
mark_listing_dirty() { LISTING_DIRTY=1; }

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
  mark_listing_dirty
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
  mark_listing_dirty
}

state_toggle_pin() { local path="$1"; [[ "$(state_get_pin "$path")" == 1 ]] && state_set_pin "$path" 0 || state_set_pin "$path" 1; }
state_unpin_all() { local i; for i in "${!state_pins[@]}"; do state_pins[$i]="0"; done; mark_listing_dirty; }
state_clear_recents() { local i; for i in "${!state_used[@]}"; do state_used[$i]="0"; done; mark_listing_dirty; }

format_label() { local entry="$1"; printf '%s' "${entry//\// | }"; }

CLIPBOARD_TOOL_LAST=""
ownertrust_cache=""

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

trust_level() {
  local fp="$1"
  awk -F: -v F="$fp" '$1==F {print $2; exit}' <<<"$ownertrust_cache"
}

ownertrust_label() {
  local lvl="$1"
  case "$lvl" in
    5) printf 'ultimate' ;;
    4) printf 'full' ;;
    3) printf 'marginal' ;;
    2) printf 'never' ;;
    1) printf 'unknown' ;;
    *) printf 'unset' ;;
  esac
}

discover_entries() {
  [[ -d "$PASSWORD_STORE_DIR" ]] || die "Password store directory '$PASSWORD_STORE_DIR' does not exist."
  # Prefer fd/fdfind for speed; fallback to find
  if command -v fd >/dev/null 2>&1; then
    fd -a -t f -e gpg . "$PASSWORD_STORE_DIR" | sed -e "s#^$PASSWORD_STORE_DIR/##" -e 's/\.gpg$//'
  elif command -v fdfind >/dev/null 2>&1; then
    fdfind -a -t f -e gpg . "$PASSWORD_STORE_DIR" | sed -e "s#^$PASSWORD_STORE_DIR/##" -e 's/\.gpg$//'
  else
    find "$PASSWORD_STORE_DIR" -type f -name '*.gpg' -print | \
      sed -e "s#^$PASSWORD_STORE_DIR/##" -e 's/\.gpg$//'
  fi | LC_ALL=C sort -u
}

build_sorted_listing() {
  # Output: path<TAB>display<TAB>pin<TAB>used
  local entries_tmp joined_tmp rows path pin used label star
  entries_tmp=$(mktemp "${TMPDIR:-/tmp}/passage_entries.XXXXXX")
  discover_entries > "$entries_tmp"

  joined_tmp=$(mktemp "${TMPDIR:-/tmp}/passage_join.XXXXXX")
  if [[ -f "$STATE_FILE" ]]; then
    awk -v OFS='\t' 'FNR==NR {pin[$1]=$2; used[$1]=$3; next} {p=$0; up=pin[p]; uu=used[p]; if (up=="") up=0; if (uu=="") uu=0; print p, up, uu}' \
      "$STATE_FILE" "$entries_tmp" > "$joined_tmp"
  else
    awk -v OFS='\t' '{print $0, 0, 0}' "$entries_tmp" > "$joined_tmp"
  fi

  rows=$(mktemp "${TMPDIR:-/tmp}/passage_rows.XXXXXX")
  while IFS=$'\t' read -r path pin used; do
    [[ -z "$path" ]] && continue
    label="$(format_label "$path")"; star=""; [[ "$pin" == "1" ]] && star="${FG_YELLOW}★ ${RESET}"
    printf '%s\t%010d\t%s\t%s%s\t%s\t%s\n' "$pin" "$used" "$path" "$star" "$label" "$pin" "$used" >> "$rows"
  done < "$joined_tmp"

  LC_ALL=C sort -t $'\t' -k1,1nr -k2,2nr -k3,3 "$rows" | awk -F '\t' '{ printf "%s\t%s\t%s\t%s\n", $3, $4, $6, $7 }'
  rm -f "$entries_tmp" "$joined_tmp" "$rows"
}

pass_decrypt() { pass show -- "$1"; }
parse_password() { local content="$1"; printf '%s' "${content%%$'\n'*}"; }

## parse_fields removed (field operations no longer supported)

msg_ok()   { printf '%s%sOK:%s %s\n' "$FG_GREEN" "$BOLD" "$RESET" "$1" >&2; }
msg_note() { printf '%s%sNote:%s %s\n' "$FG_BLUE" "$BOLD" "$RESET" "$1" >&2; }
msg_warn() { printf '%s%sWarn:%s %s\n' "$FG_YELLOW" "$BOLD" "$RESET" "$1" >&2; }

reveal_until_clear() {
  local title="$1" secret="$2"
  screen_clear
  printf '%s%sReveal:%s %s\n\n' "$BOLD" "$FG_MAGENTA" "$RESET" "$title"
  printf '%s%s%s\n\n' "$BOLD" "$FG_CYAN" "$secret" "$RESET"
  printf '%sPress Enter to clear...%s\n' "$DIM" "$RESET"
  read -r -s _
  screen_clear
}

# Determine whether a given pass entry has an MFA secret.
# Rules:
# - If the entry itself ends with '/mfa' (or is exactly 'mfa'), it is an MFA entry.
# - Otherwise, if a sibling entry '<path>/mfa' exists in the store, treat it as MFA-enabled.
has_mfa_for_path() {
  local path="$1"
  if [[ "$path" == */mfa || "$path" == mfa ]]; then
    return 0
  fi
  local sibling="$path/mfa"
  local i
  for i in "${!full_paths[@]}"; do
    if [[ "${full_paths[$i]}" == "$sibling" ]]; then
      return 0
    fi
  done
  return 1
}

# Given a pass entry, return the concrete MFA entry path (echo) or empty if none.
mfa_target_for_path() {
  local path="$1"
  if [[ "$path" == */mfa || "$path" == mfa ]]; then
    printf '%s' "$path"
    return 0
  fi
  local sibling="$path/mfa"
  local i
  for i in "${!full_paths[@]}"; do
    if [[ "${full_paths[$i]}" == "$sibling" ]]; then
      printf '%s' "$sibling"
      return 0
    fi
  done
  printf ''
  return 1
}

# Utility from mfa: format 6 digits as '123 456'
format_otp() {
  local digits="$1"; local len=${#digits}; local chunk=3; local idx=0; local result=""; local part
  while (( idx < len )); do
    part="${digits:idx:chunk}"
    [[ -n "$result" ]] && result+=" "
    result+="$part"
    idx=$((idx + chunk))
  done
  printf '%s' "$result"
}

# Single-line progress visualization similar to mfa
render_progress() {
  local remaining="$1" step="$2" width=24 elapsed filled empty filled_bar empty_bar color
  elapsed=$((step - remaining))
  (( elapsed < 0 )) && elapsed=0
  (( elapsed > step )) && elapsed=$step
  filled=$((elapsed * width / step))
  empty=$((width - filled))
  [[ $filled -gt 0 ]] && filled_bar="$(printf '%*s' "$filled" '' | tr ' ' '=')" || filled_bar=""
  [[ $empty  -gt 0 ]] && empty_bar="$(printf '%*s' "$empty" ''  | tr ' ' '.')" || empty_bar=""
  color="$FG_GREEN"
  (( remaining <= 5 )) && color="$FG_RED"
  (( remaining > 5 && remaining <= 10 )) && color="$FG_YELLOW"
  printf '%s[%s%s%s%s]%s %s%2ds remaining%s\n' \
    "$DIM" "$FG_CYAN" "$filled_bar" "$DIM" "$empty_bar" "$RESET" "$color" "$remaining" "$RESET"
}

# Generate an OTP from a pass entry while avoiding secret exposure in argv.
# Exactly one non-empty line allowed (base32 secret); otpauth:// URIs are rejected.
mfa_generate_otp_from_pass() {
  local entry="$1" content first rest secret code
  if ! content="$(pass show -- "$entry")"; then return 1; fi
  first="${content%%$'\n'*}"
  if [[ "$content" == *$'\n'* ]]; then rest="${content#*$'\n'}"; else rest=""; fi
  if [[ -n "${rest//[[:space:]]/}" ]]; then die "MFA entry must contain exactly one line (base32 secret)."; fi
  secret="${first//[[:space:]]/}"
  [[ -z "$secret" ]] && die "MFA secret is empty. Ensure one non-empty line."
  [[ "$secret" == otpauth://* ]] && die "otpauth URIs are not supported. Store the base32 secret only (one line)."
  if ! code="$(printf '%s' "$secret" | oathtool --totp -b - 2>/dev/null)"; then
    die "oathtool failed to generate a code."
  fi
  unset -v content first rest secret || true
  printf '%s' "$code"
}

require_deps() { command -v pass >/dev/null 2>&1 || die "Missing dependency: pass"; }

# Full cached listing arrays
full_paths=(); full_displays=(); full_pins=(); full_used=()

refresh_full_listing() {
  full_paths=(); full_displays=(); full_pins=(); full_used=()
  while IFS=$'\t' read -r p d pin used; do
    full_paths+=("$p"); full_displays+=("$d"); full_pins+=("$pin"); full_used+=("$used")
  done < <(build_sorted_listing)
  LISTING_DIRTY=0
}

# Load current listing into arrays, optionally filtered by a substring.
list_paths=(); list_displays=(); list_pins=(); list_used=()
load_listing_arrays() {
  local filter="${1-}"
  list_paths=(); list_displays=(); list_pins=(); list_used=()
  if [[ ${#full_paths[@]} -eq 0 || ${LISTING_DIRTY:-1} -eq 1 ]]; then
    refresh_full_listing
  fi
  if [[ -z "$filter" ]]; then
    list_paths=("${full_paths[@]}")
    list_displays=("${full_displays[@]}")
    list_pins=("${full_pins[@]}")
    list_used=("${full_used[@]}")
  else
    local f_lc p_lc d_lc i
    f_lc=$(printf '%s' "$filter" | to_lower)
    for i in "${!full_paths[@]}"; do
      p_lc=$(printf '%s' "${full_paths[$i]}" | to_lower)
      d_lc=$(printf '%s' "${full_displays[$i]}" | to_lower)
      if [[ "$p_lc" == *"$f_lc"* || "$d_lc" == *"$f_lc"* ]]; then
        list_paths+=("${full_paths[$i]}")
        list_displays+=("${full_displays[$i]}")
        list_pins+=("${full_pins[$i]}")
        list_used+=("${full_used[$i]}")
      fi
    done
  fi
}

term_cols() {
  local c cols st
  c="${COLUMNS:-}"
  if [[ "$c" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$c"; return 0
  fi
  if command -v tput >/dev/null 2>&1; then
    cols="$(tput cols 2>/dev/null || true)"
    if [[ "$cols" =~ ^[0-9]+$ ]]; then
      printf '%s\n' "$cols"; return 0
    fi
  fi
  st="$(stty size 2>/dev/null | awk '{print $2}')"
  if [[ "$st" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$st"; return 0
  fi
  printf '80\n'
}

# Visible label without ANSI color for width calculations
visible_label_for_index() {
  local idx="$1" l star_txt="" mfa_tag=""
  l="$(format_label "${list_paths[$idx]}")"
  [[ "${list_pins[$idx]}" == "1" ]] && star_txt='★ '
  if has_mfa_for_path "${list_paths[$idx]}"; then mfa_tag=' [mfa]'; fi
  printf '%s%s%s' "$star_txt" "$l" "$mfa_tag"
}

# Colored label for display
truncate_text() {
  local s="$1" w="$2"
  local n=${#s}
  if (( w <= 0 )); then printf '' ; return 0; fi
  if (( n <= w )); then printf '%s' "$s"; return 0; fi
  if (( w <= 3 )); then printf '%.*s' "$w" "$s"; return 0; fi
  printf '%s' "${s:0:w-3}..."
}

colored_label_for_index() {
  local idx="$1" w="${2-}" l star_colored="" out pre last mfa_colored=""
  l="$(format_label "${list_paths[$idx]}")"
  if [[ -n "$w" ]]; then
    if [[ "${list_pins[$idx]}" == "1" ]]; then
      star_colored="${FG_YELLOW}★ ${RESET}"
      # reserve 2 chars for star + space in visible width
      local avail=$(( w - 2 )); (( avail < 0 )) && avail=0
      out="$(truncate_text "$l" "$avail")"
      # Split visible text at the last separator to color the tail differently
      last="${out##* | }"
      pre="${out%${last}}"
      if has_mfa_for_path "${list_paths[$idx]}"; then mfa_colored=" ${DIM}[mfa]${RESET}"; fi
      printf '%s%s%s%s%s%s%s' "$star_colored" "$FG_BLUE" "$pre" "$FG_WHITE" "$last" "$RESET" "$mfa_colored"
    else
      out="$(truncate_text "$l" "$w")"
      last="${out##* | }"
      pre="${out%${last}}"
      if has_mfa_for_path "${list_paths[$idx]}"; then mfa_colored=" ${DIM}[mfa]${RESET}"; fi
      printf '%s%s%s%s%s%s' "$FG_BLUE" "$pre" "$FG_WHITE" "$last" "$RESET" "$mfa_colored"
    fi
  else
    [[ "${list_pins[$idx]}" == "1" ]] && star_colored="${FG_YELLOW}★ ${RESET}"
    last="${l##* | }"
    pre="${l%${last}}"
    if has_mfa_for_path "${list_paths[$idx]}"; then mfa_colored=" ${DIM}[mfa]${RESET}"; fi
    printf '%s%s%s%s%s%s%s' "$star_colored" "$FG_BLUE" "$pre" "$FG_WHITE" "$last" "$RESET" "$mfa_colored"
  fi
}

print_listing() {
  local total=${#list_paths[@]}
  local i
  printf '%sEntries:%s %s%d%s\n' "$BOLD$FG_CYAN" "$RESET" "$FG_GREEN" "$total" "$RESET"

  # Compute responsive layout (two columns only if both entries fit without truncation)
  local cols idx_digits idx_field_w gap i j max_left_block
  local -a pair_ok
  cols="$(term_cols)"
  # index field width: at least 2 digits (matches %2d formatting)
  idx_digits=${#total}; (( idx_digits < 2 )) && idx_digits=2
  idx_field_w=$(( idx_digits + 4 ))  # two leading spaces + ") "
  gap=3
  # First pass: decide which adjacent pairs (n,n+1) fit without padding
  local any_pair=0 left_len right_len pair_w n label
  pair_ok=()
  for ((n=0; n+1<total; n++)); do
    label="$(visible_label_for_index "$n")"; left_len=${#label}
    label="$(visible_label_for_index "$((n+1))")"; right_len=${#label}
    pair_w=$(( idx_field_w + left_len + gap + idx_field_w + right_len ))
    if (( pair_w <= cols )); then
      pair_ok[n]=1; any_pair=1
    else
      pair_ok[n]=0
    fi
  done

  if (( any_pair )); then
    # Compute alignment width only across pairs that fit
    max_left_block=0
    for ((n=0; n+1<total; n++)); do
      if [[ "${pair_ok[n]:-0}" -eq 1 ]]; then
        label="$(visible_label_for_index "$n")"
        local left_block=$(( idx_field_w + ${#label} ))
        (( left_block > max_left_block )) && max_left_block=$left_block
      fi
    done

    # Drop pairs that no longer fit when padded to aligned left width
    any_pair=0
    local req
    for ((n=0; n+1<total; n++)); do
      if [[ "${pair_ok[n]:-0}" -eq 1 ]]; then
        label="$(visible_label_for_index "$((n+1))")"; right_len=${#label}
        req=$(( max_left_block + gap + idx_field_w + right_len ))
        if (( req <= cols )); then
          pair_ok[n]=1; any_pair=1
        else
          pair_ok[n]=0
        fi
      fi
    done

  fi

  if (( any_pair )); then
    # Mixed layout: pair when it cleanly fits; otherwise print single-column rows
    local pad left_block label_l
    n=0
    while (( n < total )); do
      if (( n+1 < total )) && [[ "${pair_ok[n]:-0}" -eq 1 ]]; then
        label_l="$(visible_label_for_index "$n")"
        left_block=$(( idx_field_w + ${#label_l} ))
        printf '  %*d) ' "$idx_digits" $((n+1))
        printf '%s' "$(colored_label_for_index "$n")"
        pad=$(( max_left_block - left_block ))
        (( pad > 0 )) && printf '%*s' "$pad" ''
        printf '%*s' "$gap" ''
        printf '  %*d) ' "$idx_digits" $((n+2))
        printf '%s' "$(colored_label_for_index "$((n+1))")"
        printf '\n'
        n=$(( n + 2 ))
      else
        printf '  %*d) ' "$idx_digits" $((n+1))
        printf '%s\n' "$(colored_label_for_index "$n")"
        n=$(( n + 1 ))
      fi
    done
  else
    # One-column layout
    for ((i=0; i<total; i++)); do
      printf '  %*d) ' "$idx_digits" $((i+1))
      printf '%s\n' "$(colored_label_for_index "$i")"
    done
  fi
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

perform_totp() {
  local path="$1" target otp pretty now modulo remaining
  target="$(mfa_target_for_path "$path")"
  if [[ -z "$target" ]]; then msg_warn "No MFA entry found for '$path'."; return 0; fi
  command -v oathtool >/dev/null 2>&1 || die "Missing dependency: oathtool"
  if ! otp="$(mfa_generate_otp_from_pass "$target")"; then die "Failed to generate OTP for '$target'."; fi
  pretty="$(format_otp "$otp")"
  # Copy as a convenience, like reveal password
  if clipboard_copy "$otp"; then :; else :; fi
  state_touch "$path"; state_save
  now=$(date +%s)
  modulo=$((now % TOTP_WINDOW))
  remaining=$((TOTP_WINDOW - modulo))
  (( remaining == 0 )) && remaining=$TOTP_WINDOW
  screen_clear
  printf '%s%sReveal TOTP:%s %s\n\n' "$BOLD" "$FG_MAGENTA" "$RESET" "$(format_label "$path")"
  if command -v figlet >/dev/null 2>&1; then
    local figlet_text
    figlet_text="$(printf '%s' "$pretty" | sed 's/ /  /g')"
    printf '%s' "$FG_CYAN"
    figlet "$figlet_text"
    printf '%s\n' "$RESET"
  else
    printf '%s%s%s\n' "$BOLD" "$FG_CYAN" "$pretty" "$RESET"
  fi
  printf '\n'
  render_progress "$remaining" "$TOTP_WINDOW"
  printf '\n%sPress Enter to clear...%s\n' "$DIM" "$RESET"
  read -r -s _
  screen_clear
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

verify_pass_keys_tool() {
  local root="$PASSWORD_STORE_DIR"
  if [[ ! -d "$root" ]]; then
    msg_warn "Password store directory '$root' does not exist; nothing to verify."
    return 0
  fi
  if ! command -v gpg >/dev/null 2>&1; then
    msg_warn "gpg not found in PATH; cannot verify GNU Pass keys."
    return 0
  fi

  ownertrust_cache="$(gpg --export-ownertrust 2>/dev/null || true)"

  local -a stores labels
  stores=(); labels=()

  # Root store
  stores+=("$root")
  labels+=("default")

  # Immediate subfolders
  local d
  for d in "$root"/*; do
    [[ -d "$d" ]] || continue
    stores+=("$d")
    labels+=("${d##*/}")
  done

  if [[ ${#stores[@]} -eq 0 ]]; then
    msg_warn "No subfolders found under '$root'."
    return 0
  fi

  local -a store_total store_missing store_untrusted store_empty store_no_gpgid \
          store_missing_ids store_untrusted_ids
  store_total=(); store_missing=(); store_untrusted=(); store_empty=(); store_no_gpgid=()
  store_missing_ids=(); store_untrusted_ids=()

  local i
  for i in "${!stores[@]}"; do
    local dir="${stores[$i]}" lbl="${labels[$i]}" gpg_file
    local ids=()
    gpg_file="$dir/.gpg-id"
    store_total[$i]=0
    store_missing[$i]=0
    store_untrusted[$i]=0
    store_empty[$i]=0
    store_no_gpgid[$i]=0
    store_missing_ids[$i]=""
    store_untrusted_ids[$i]=""

    if [[ ! -f "$gpg_file" ]]; then
      store_no_gpgid[$i]=1
      continue
    fi

    # Read identities from .gpg-id (one per line, trim whitespace, skip empties)
    local line trimmed
    while IFS= read -r line || [[ -n "$line" ]]; do
      trimmed="$line"
      # trim leading whitespace
      trimmed="${trimmed#"${trimmed%%[![:space:]]*}"}"
      # trim trailing whitespace
      trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
      [[ -z "$trimmed" ]] && continue
      ids+=("$trimmed")
    done <"$gpg_file"

    if [[ ${#ids[@]} -eq 0 ]]; then
      store_empty[$i]=1
      continue
    fi

    store_total[$i]=${#ids[@]}

    local id missing_list untrusted_list
    missing_list=""
    untrusted_list=""

    for id in "${ids[@]}"; do
      local category fps_line

      # Secret key present for this identity?
      if gpg --batch --quiet --list-secret-keys "$id" >/dev/null 2>&1; then
        category="ok-own"
      else
        # List public keys for this identity
        fps_line="$(gpg --batch --with-colons --list-keys "$id" 2>/dev/null || true)"
        if [[ -z "$fps_line" ]]; then
          category="missing"
        else
          # Extract primary key fingerprints then check ownertrust cache.
          local fp
          local fps=()
          local pub=0
          while IFS= read -r line; do
            case "$line" in
              pub:*)
                pub=1
                ;;
              fpr:*)
                if [[ $pub -eq 1 ]]; then
                  fp=$(printf '%s\n' "$line" | awk -F: '{print $10}')
                  if [[ -n "$fp" ]]; then
                    fps+=("$fp")
                  fi
                  pub=0
                fi
                ;;
            esac
          done <<<"$fps_line"

          local has_keys=0 trusted=0
          for fp in "${fps[@]}"; do
            has_keys=1
            local lvl
            lvl="$(trust_level "$fp")"
            if [[ "$lvl" == "4" || "$lvl" == "5" ]]; then
              trusted=1
              break
            fi
          done

          if [[ $trusted -eq 1 ]]; then
            category="ok-trusted"
          elif [[ $has_keys -eq 1 ]]; then
            category="present"
          else
            category="missing"
          fi
        fi
      fi

      case "$category" in
        ok-own|ok-trusted)
          ;;
        missing)
          store_missing[$i]=$((store_missing[$i]+1))
          if [[ -z "$missing_list" ]]; then
            missing_list="$id"
          else
            missing_list="$missing_list, $id"
          fi
          ;;
        present)
          store_untrusted[$i]=$((store_untrusted[$i]+1))
          if [[ -z "$untrusted_list" ]]; then
            untrusted_list="$id"
          else
            untrusted_list="$untrusted_list, $id"
          fi
          ;;
      esac
    done

    store_missing_ids[$i]="$missing_list"
    store_untrusted_ids[$i]="$untrusted_list"
  done

  screen_clear
  printf '%sTools:%s Verify GNU Pass keys\n\n' "$BOLD$FG_MAGENTA" "$RESET"

  local skip_root=0 has_sub_with_gpgid=0
  if [[ "${store_no_gpgid[0]:-0}" -eq 1 ]]; then
    local idx
    for idx in "${!stores[@]}"; do
      [[ "$idx" -eq 0 ]] && continue
      if [[ "${store_no_gpgid[$idx]}" -eq 0 ]]; then
        has_sub_with_gpgid=1
        break
      fi
    done
    if [[ $has_sub_with_gpgid -eq 1 ]]; then
      skip_root=1
    else
      msg_warn "No .gpg-id found at '$root' or its immediate subfolders. Did you run 'pass init' here?"
    fi
  fi

  local any_store=0 pad=0 name
  local i2
  for i2 in "${!stores[@]}"; do
    if [[ "$i2" -eq 0 && $skip_root -eq 1 ]]; then
      continue
    fi
    name="${labels[$i2]}"
    local n=${#name}
    (( n > pad )) && pad=$n
    any_store=1
  done

  if [[ $any_store -eq 0 ]]; then
    msg_warn "No stores found to inspect."
    return 0
  fi

  printf '%sChecking stores under:%s %s\n\n' "$DIM" "$RESET" "$root"

  for i2 in "${!stores[@]}"; do
    if [[ "$i2" -eq 0 && $skip_root -eq 1 ]]; then
      continue
    fi
    local lbl="${labels[$i2]}"
    local parts=()

    if [[ "${store_no_gpgid[$i2]}" -eq 1 ]]; then
      parts+=("${FG_BLUE}no .gpg-id${RESET}")
    elif [[ "${store_empty[$i2]}" -eq 1 ]]; then
      parts+=("${FG_YELLOW}empty .gpg-id${RESET}")
    else
      if [[ "${store_missing[$i2]}" -gt 0 ]]; then
        parts+=("${FG_RED}missing${RESET} ${DIM}(${store_missing[$i2]}: ${store_missing_ids[$i2]})${RESET}")
      fi
      if [[ "${store_untrusted[$i2]}" -gt 0 ]]; then
        parts+=("${FG_MAGENTA}untrusted${RESET} ${DIM}(${store_untrusted[$i2]}: ${store_untrusted_ids[$i2]})${RESET}")
      fi
      if [[ "${store_missing[$i2]}" -eq 0 && "${store_untrusted[$i2]}" -eq 0 ]]; then
        parts+=("${FG_GREEN}ok${RESET} ${DIM}(${store_total[$i2]} recipient(s))${RESET}")
      fi
    fi

    local status=""
    local j
    for j in "${!parts[@]}"; do
      if [[ $j -gt 0 ]]; then status+=", "; fi
      status+="${parts[$j]}"
    done

    printf "  • %-${pad}s   %s\n" "$lbl" "$status"
  done

  local stores_total=0
  local stores_with_issues=0 stores_ok=0 stores_no_gpgid=0 stores_empty=0
  for i2 in "${!stores[@]}"; do
    if [[ "$i2" -eq 0 && $skip_root -eq 1 ]]; then
      continue
    fi
    stores_total=$((stores_total+1))
    if [[ "${store_no_gpgid[$i2]}" -eq 1 ]]; then
      stores_no_gpgid=$((stores_no_gpgid+1))
    elif [[ "${store_empty[$i2]}" -eq 1 ]]; then
      stores_empty=$((stores_empty+1))
    elif [[ "${store_missing[$i2]}" -gt 0 || "${store_untrusted[$i2]}" -gt 0 ]]; then
      stores_with_issues=$((stores_with_issues+1))
    else
      stores_ok=$((stores_ok+1))
    fi
  done

  local summary_lines=(
    "stores: $stores_total"
    "ok: $stores_ok"
    "with_issues: $stores_with_issues"
    "no_gpgid: $stores_no_gpgid"
    "empty_gpgid: $stores_empty"
  )

  if command -v gum >/dev/null 2>&1 && [[ -t 1 ]]; then
    local gum_width=50 line len
    for line in "${summary_lines[@]}"; do
      len=${#line}
      if [[ $len -gt $gum_width ]]; then
        gum_width=$len
      fi
    done
    gum style \
      --border double \
      --align center \
      --width "$gum_width" \
      --margin "1 2" \
      --padding "1 4" \
      "${summary_lines[@]}"
  else
    local line2
    for line2 in "${summary_lines[@]}"; do
      printf '%s%s%s\n' "$DIM" "$line2" "$RESET"
    done
  fi

  printf '\n'
}

list_local_keys_tool() {
  if ! command -v gpg >/dev/null 2>&1; then
    msg_warn "gpg not found in PATH; cannot list local keys."
    return 0
  fi

  ownertrust_cache="$(gpg --export-ownertrust 2>/dev/null || true)"

  local -a key_fps key_uids
  key_fps=(); key_uids=()

  while IFS=$'\t' read -r fp uid; do
    [[ -z "$fp" ]] && continue
    key_fps+=("$fp")
    key_uids+=("$uid")
  done < <(
    gpg --with-colons --list-keys 2>/dev/null | awk -F: '
      /^pub:/ {
        if (fp != "") {
          print fp "\t" uid
        }
        fp=""; uid=""; pub=1; next
      }
      /^uid:/ && uid == "" { uid=$10; next }
      /^fpr:/ && pub { fp=$10; pub=0; next }
      END {
        if (fp != "") {
          print fp "\t" uid
        }
      }
    '
  )

  if [[ ${#key_fps[@]} -eq 0 ]]; then
    msg_warn "No local public keys found."
    return 0
  fi

  screen_clear
  gum style \
    --border rounded \
    --margin "0 1" \
    --padding "1 2" \
    --width 80 \
    "${BOLD}${FG_MAGENTA}List local GPG keys${RESET}" \
    "" \
    "Shows your local public keys, whether you own the" \
    "secret key, and the ownertrust level (from trustdb)."

  local pad=0 i name
  for i in "${!key_uids[@]}"; do
    name="${key_uids[$i]}"
    [[ -z "$name" ]] && name="<no uid>"
    local n=${#name}
    (( n > pad )) && pad=$n
  done

  local own_count=0 trusted_count=0
  printf '%sKeys:%s\n\n' "$BOLD$FG_CYAN" "$RESET"
  for i in "${!key_fps[@]}"; do
    local fp uid lvl lvl_label has_secret status_parts=()
    fp="${key_fps[$i]}"
    uid="${key_uids[$i]}"
    [[ -z "$uid" ]] && uid="<no uid>"

    if gpg --batch --quiet --list-secret-keys "$fp" >/dev/null 2>&1; then
      has_secret=1
      own_count=$((own_count+1))
      status_parts+=("${FG_GREEN}own-secret${RESET}")
    else
      has_secret=0
      status_parts+=("${FG_YELLOW}public-only${RESET}")
    fi

    lvl="$(trust_level "$fp")"
    lvl_label="$(ownertrust_label "${lvl:-}")"
    if [[ "$lvl" == "4" || "$lvl" == "5" ]]; then
      trusted_count=$((trusted_count+1))
      status_parts+=("${FG_CYAN}trusted${RESET} ${DIM}(${lvl_label})${RESET}")
    else
      status_parts+=("${DIM}trust:${RESET} ${lvl_label}")
    fi

    local status="" j
    for j in "${!status_parts[@]}"; do
      if [[ $j -gt 0 ]]; then status+=", "; fi
      status+="${status_parts[$j]}"
    done

    printf "  • %-${pad}s   %s%s%s\n" "$uid" "${DIM}(${fp})${RESET}  " "$status" ""
  done

  local total=${#key_fps[@]}
  local summary_lines=(
    "keys: $total"
    "with_secret: $own_count"
    "trusted_full_or_ultimate: $trusted_count"
  )

  printf '\n'
  gum style \
    --border double \
    --align center \
    --width 60 \
    --margin "1 2" \
    --padding "1 3" \
    "${summary_lines[@]}"

  printf '\n'
}

list_password_keys_tool() {
  local root="$PASSWORD_STORE_DIR"
  if [[ ! -d "$root" ]]; then
    msg_warn "Password store directory '$root' does not exist; nothing to inspect."
    return 0
  fi
  if ! command -v gpg >/dev/null 2>&1; then
    msg_warn "gpg not found in PATH; cannot inspect password keys."
    return 0
  fi

  ownertrust_cache="$(gpg --export-ownertrust 2>/dev/null || true)"

  local -a stores labels
  stores=(); labels=()

  stores+=("$root")
  labels+=("default")
  local root_has_gpgid=0 any_sub_with_gpgid=0
  [[ -f "$root/.gpg-id" ]] && root_has_gpgid=1

  local d
  for d in "$root"/*; do
    [[ -d "$d" ]] || continue
    stores+=("$d")
    labels+=("${d##*/}")
    if [[ -f "$d/.gpg-id" ]]; then
      any_sub_with_gpgid=1
    fi
  done

  if [[ ${#stores[@]} -eq 0 ]]; then
    msg_warn "No subfolders found under '$root'."
    return 0
  fi

  local skip_root=0
  if [[ $root_has_gpgid -eq 0 && $any_sub_with_gpgid -eq 1 ]]; then
    skip_root=1
  fi

  screen_clear
  gum style \
    --border rounded \
    --margin "0 1" \
    --padding "1 2" \
    --width 80 \
    "${BOLD}${FG_MAGENTA}Password store key roll call${RESET}" \
    "" \
    "For each store, list the identities from .gpg-id" \
    "and whether you own their keys and/or trust them."

  local i
  for i in "${!stores[@]}"; do
    local dir="${stores[$i]}" lbl="${labels[$i]}"
    if [[ "$i" -eq 0 && $skip_root -eq 1 ]]; then
      continue
    fi

    printf '\n%sStore:%s %s (%s)\n' "$BOLD$FG_CYAN" "$RESET" "$lbl" "$dir"
    local gpg_file="$dir/.gpg-id"
    if [[ ! -f "$gpg_file" ]]; then
      printf '  %s(no .gpg-id)%s\n' "$DIM" "$RESET"
      continue
    fi

    local ids=() line trimmed
    while IFS= read -r line || [[ -n "$line" ]]; do
      trimmed="$line"
      trimmed="${trimmed#"${trimmed%%[![:space:]]*}"}"
      trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
      [[ -z "$trimmed" ]] && continue
      ids+=("$trimmed")
    done <"$gpg_file"

    if [[ ${#ids[@]} -eq 0 ]]; then
      printf '  %s(empty .gpg-id)%s\n' "$DIM" "$RESET"
      continue
    fi

    local id
    for id in "${ids[@]}"; do
      local category fps_line
      local uid_disp="" status_parts=()

      if gpg --batch --quiet --list-secret-keys "$id" >/dev/null 2>&1; then
        category="ok-own"
      else
        fps_line="$(gpg --batch --with-colons --list-keys "$id" 2>/dev/null || true)"
        if [[ -z "$fps_line" ]]; then
          category="missing"
        else
          local fp fps=() pub=0
          while IFS= read -r line; do
            case "$line" in
              pub:*)
                pub=1
                ;;
              fpr:*)
                if [[ $pub -eq 1 ]]; then
                  fp=$(printf '%s\n' "$line" | awk -F: '{print $10}')
                  if [[ -n "$fp" ]]; then
                    fps+=("$fp")
                  fi
                  pub=0
                fi
                ;;
              uid:*)
                if [[ -z "$uid_disp" ]]; then
                  uid_disp=$(printf '%s\n' "$line" | awk -F: '{print $10}')
                fi
                ;;
            esac
          done <<<"$fps_line"

          local has_keys=0 trusted=0
          for fp in "${fps[@]}"; do
            has_keys=1
            local lvl
            lvl="$(trust_level "$fp")"
            if [[ "$lvl" == "4" || "$lvl" == "5" ]]; then
              trusted=1
              break
            fi
          done

          if [[ $trusted -eq 1 ]]; then
            category="ok-trusted"
          elif [[ $has_keys -eq 1 ]]; then
            category="present"
          else
            category="missing"
          fi
        fi
      fi

      [[ -z "$uid_disp" ]] && uid_disp="$id"

      case "$category" in
        ok-own)
          status_parts+=("${FG_GREEN}own-secret${RESET}")
          ;;
        ok-trusted)
          status_parts+=("${FG_CYAN}trusted${RESET}")
          ;;
        present)
          status_parts+=("${FG_MAGENTA}untrusted${RESET}")
          ;;
        missing)
          status_parts+=("${FG_RED}missing${RESET}")
          ;;
      esac

      if [[ "$category" != "missing" && "${#fps[@]}" -gt 0 ]]; then
        local first_fp lvl lvl_label
        first_fp="${fps[0]}"
        lvl="$(trust_level "$first_fp")"
        lvl_label="$(ownertrust_label "${lvl:-}")"
        status_parts+=("${DIM}trust:${RESET} ${lvl_label}")
      fi

      local status="" j
      for j in "${!status_parts[@]}"; do
        if [[ $j -gt 0 ]]; then status+=", "; fi
        status+="${status_parts[$j]}"
      done

      printf '  • %s%s%s  %s\n' "$FG_WHITE" "$uid_disp" "$RESET" "$status"
    done
  done

  printf '\n'
}

create_gpg_key_tool() {
  if ! command -v gum >/dev/null 2>&1; then
    msg_warn "gum is required for the key setup guide."
    return 0
  fi

  screen_clear
  gum style \
    --border rounded \
    --margin "0 1" \
    --padding "1 2" \
    --width 72 \
    -- \
    "${BOLD}${FG_MAGENTA}GPG key setup guide${RESET}" \
    "" \
    "Use this guide to create a modern ECC key" \
    "for GNU pass, then local-sign it and mark" \
    "it trusted. All commands are run manually."

  printf '\n'
  gum style \
    --border rounded \
    --margin "0 1" \
    --padding "1 2" \
    --width 72 \
    -- \
    "${BOLD}1) Generate a new key (interactive)${RESET}" \
    "" \
    "Run in a regular terminal:" \
    "" \
    "  gpg --expert --full-generate-key" \
    "" \
    "- Select:  (9) ECC and ECC" \
    "- Curve:   (1) Curve 25519" \
    "- Expiry:  0  (does not expire)" \
    "- Fill in: Real name, Email, Comment" \
    "- Confirm: O (okay)" \
    "" \
    "Wait for GPG to finish generating the" \
    "primary key and encryption subkey."

  printf '\n'
  gum style \
    --border rounded \
    --margin "0 1" \
    --padding "1 2" \
    --width 72 \
    -- \
    "${BOLD}2) Find your new key fingerprint${RESET}" \
    "" \
    "List your keys and find the new key:" \
    "" \
    "  gpg --list-keys" \
    "" \
    "Copy the full fingerprint (40 hex characters)" \
    "for the new key. When the guide says" \
    "KEY_FPR below, paste that fingerprint there."

  printf '\n'
  gum style \
    --border rounded \
    --margin "0 1" \
    --padding "1 2" \
    --width 72 \
    -- \
    "${BOLD}3) Locally sign and trust the key${RESET}" \
    "" \
    "Use the fingerprint you just copied (KEY_FPR):" \
    "" \
    "  gpg --lsign-key KEY_FPR" \
    "" \
    "Then mark it ownertrust FULL (4):" \
    "" \
    "  echo 'KEY_FPR:4:' | gpg --import-ownertrust"

  printf '\n'
}

tools_menu() {
  if ! command -v gum >/dev/null 2>&1; then
    msg_warn "gum is required for the tools menu."
    return 0
  fi

  while true; do
    screen_clear
    gum style \
      --border rounded \
      --margin "0 1" \
      --padding "1 2" \
      --width 60 \
      "${BOLD}${FG_MAGENTA}Tools${RESET} — passage helpers"

    local choice
    choice="$(
      printf '%s\n' \
        'Back' \
        'GPG key setup guide' \
        'List local keys' \
        'List password keys' \
        'Verify GNU Pass keys' | \
        gum choose --cursor '➜' --header 'Select a tool' || true
    )"
    case "$choice" in
      Back|'')
        break
        ;;
      "Verify GNU Pass keys")
        verify_pass_keys_tool
        printf '%sPress Enter to return to tools...%s\n' "$DIM" "$RESET"
        read -r _
        ;;
      "List local keys")
        list_local_keys_tool
        printf '%sPress Enter to return to tools...%s\n' "$DIM" "$RESET"
        read -r _
        ;;
      "List password keys")
        list_password_keys_tool
        printf '%sPress Enter to return to tools...%s\n' "$DIM" "$RESET"
        read -r _
        ;;
      "GPG key setup guide")
        create_gpg_key_tool
        printf '%sPress Enter to return to tools...%s\n' "$DIM" "$RESET"
        read -r _
        ;;
      *)
        break
        ;;
    esac
  done
}

options_menu() {
  if ! command -v gum >/dev/null 2>&1; then
    msg_warn "gum is required for the options menu."
    return 0
  fi

  local choice
  choice="$(printf 'Unpin all\nClear recents\nBack\n' | gum choose --cursor '➜' --header 'Options' || true)"
  case "$choice" in
    "Unpin all")
      state_unpin_all
      state_save
      msg_ok "All pins cleared."
      ;;
    "Clear recents")
      state_clear_recents
      state_save
      msg_ok "Recents cleared."
      ;;
    "Back"|'' )
      :
      ;;
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
  printf '\n%sActions:%s [c]opy  [r]eveal  [t]otp  [p]in/unpin  [x] clear-clipboard  [o]ptions  [b]ack  [q]uit\n' "$BOLD" "$RESET"
  printf 'Select: '
  local act
  read -r act || return 0
  act="${act//$'\r'/}"
  case "$act" in
    c|'') perform_copy "$path" ;;
    r) perform_reveal "$path" ;;
    t) perform_totp "$path" ;;
    p) state_toggle_pin "$path"; state_save; msg_ok "Pin toggled." ;;
    x) clear_clipboard ;;
    o) options_menu ;;
    b) : ;;
    q) screen_clear; exit 0 ;;
  esac
}

MFA_ONLY=0

apply_mfa_only_filter() {
  # Filter current list_* arrays to only entries with MFA available
  local new_paths=() new_displays=() new_pins=() new_used=()
  local i p
  for i in "${!list_paths[@]}"; do
    p="${list_paths[$i]}"
    if has_mfa_for_path "$p"; then
      new_paths+=("$p")
      new_displays+=("${list_displays[$i]}")
      new_pins+=("${list_pins[$i]}")
      new_used+=("${list_used[$i]}")
    fi
  done
  list_paths=("${new_paths[@]}")
  list_displays=("${new_displays[@]}")
  list_pins=("${new_pins[@]}")
  list_used=("${new_used[@]}")
}

main_loop() {
  local filter="${1-}"
  while true; do
    screen_clear
    load_listing_arrays "$filter"
    if (( MFA_ONLY )); then
      apply_mfa_only_filter
    fi
    if [[ ${#list_paths[@]} -eq 0 ]]; then
      if [[ -n "$filter" ]]; then
        msg_warn "No entries match filter '$filter'."
        filter=""
        continue
      fi
      die "No pass entries found under '$PASSWORD_STORE_DIR'."
    fi

    local header
    if (( MFA_ONLY )); then
      header="${BOLD}/[search term]${RESET} filter | ${BOLD}#${RESET} select | ${BOLD}b${RESET} back | ${BOLD}z${RESET} tools | ${BOLD}q${RESET} quit"
    else
      header="${BOLD}/[search term]${RESET} filter | ${BOLD}# (number)${RESET} select | ${BOLD}c#/#c${RESET} copy | ${BOLD}r#${RESET} reveal | ${BOLD}t#${RESET} otp | ${BOLD}p#${RESET} pin | ${BOLD}m${RESET} MFA-mode | ${BOLD}x${RESET} clear | ${BOLD}o${RESET} options | ${BOLD}z${RESET} tools | ${BOLD}q${RESET} quit"
    fi

    gum style \
      --border rounded \
      --margin "0 1" \
      --padding "1 2" \
      --width 75 \
      "$header"
    [[ -n "$filter" ]] && printf '%sFilter:%s %s\n' "$DIM" "$RESET" "$filter"
    (( MFA_ONLY )) && printf '%sView:%s MFA-only\n' "$DIM" "$RESET"
    print_listing
    printf '\nCommand: '
    local cmd
    read -r cmd || { printf '\n'; break; }

    # Normalize Mac-style CR line endings to LF
    cmd="${cmd//$'\r'/}"

    # Trim spaces
    cmd="${cmd## }"; cmd="${cmd%% }"
    if [[ -z "$cmd" ]]; then
      continue
    fi

    case "$cmd" in
      q|quit|exit) screen_clear; printf '%sExiting Passage.%s\n' "$DIM" "$RESET"; break ;;
      b) MFA_ONLY=0 ;;
      o) options_menu ;;
      m) if (( MFA_ONLY )); then MFA_ONLY=0; else MFA_ONLY=1; fi ;;
      x) clear_clipboard ;;
      z) tools_menu ;;
      /*) filter="${cmd#/}" ;;
      r[0-9]*)
        local n="${cmd#r}"
        if [[ "$n" =~ ^[0-9]+$ ]] && (( n>=1 && n<=${#list_paths[@]} )); then
          if (( MFA_ONLY )); then
            perform_totp "${list_paths[$((n-1))]}"
          else
            perform_reveal "${list_paths[$((n-1))]}"
          fi
        else
          msg_warn "Invalid index: $n"
        fi ;;
      [0-9]*r)
        local n="${cmd%r}"
        if [[ "$n" =~ ^[0-9]+$ ]] && (( n>=1 && n<=${#list_paths[@]} )); then
          if (( MFA_ONLY )); then
            perform_totp "${list_paths[$((n-1))]}"
          else
            perform_reveal "${list_paths[$((n-1))]}"
          fi
        else
          msg_warn "Invalid index: $n"
        fi ;;
      c[0-9]*)
        local n="${cmd#c}"
        if [[ "$n" =~ ^[0-9]+$ ]] && (( n>=1 && n<=${#list_paths[@]} )); then
          if (( MFA_ONLY )); then
            perform_totp "${list_paths[$((n-1))]}"
          else
            perform_copy "${list_paths[$((n-1))]}"
          fi
        else
          msg_warn "Invalid index: $n"
        fi ;;
      [0-9]*c)
        local n="${cmd%c}"
        if [[ "$n" =~ ^[0-9]+$ ]] && (( n>=1 && n<=${#list_paths[@]} )); then
          if (( MFA_ONLY )); then
            perform_totp "${list_paths[$((n-1))]}"
          else
            perform_copy "${list_paths[$((n-1))]}"
          fi
        else
          msg_warn "Invalid index: $n"
        fi ;;
      t[0-9]*)
        local n="${cmd#t}"
        if [[ "$n" =~ ^[0-9]+$ ]] && (( n>=1 && n<=${#list_paths[@]} )); then
          perform_totp "${list_paths[$((n-1))]}"
        else
          msg_warn "Invalid index: $n"
        fi ;;
      [0-9]*t)
        local n="${cmd%t}"
        if [[ "$n" =~ ^[0-9]+$ ]] && (( n>=1 && n<=${#list_paths[@]} )); then
          perform_totp "${list_paths[$((n-1))]}"
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
          if (( MFA_ONLY )); then
            perform_totp "${list_paths[$((n-1))]}"
          else
            # Show actions menu for this selection; default Enter copies
            actions_menu_for $((n-1))
          fi
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

main() {
  require_deps
  state_load

  local initial_filter=""

  # If invoked as `passage mfa`, start directly in MFA-only mode.
  # Any additional args seed the initial filter.
  if [[ ${1-} == "mfa" || ${1-} == "MFA" ]]; then
    MFA_ONLY=1
    shift || true
  fi

  if [[ $# -gt 0 ]]; then
    initial_filter="$*"
  fi

  main_loop "$initial_filter"
}

main "$@"
