#!/bin/bash
set -euo pipefail
# Terminal MFA helper with fuzzy selection, clipboard feedback, and countdown.

PASSWORD_STORE_DIR="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
TOTP_WINDOW=30

BOLD=""
DIM=""
FG_BLUE=""
FG_GREEN=""
FG_YELLOW=""
FG_MAGENTA=""
FG_RED=""
FG_CYAN=""
FG_WHITE=""
RESET=""

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

: "${BOLD:=}"
: "${DIM:=}"
: "${FG_BLUE:=}"
: "${FG_GREEN:=}"
: "${FG_YELLOW:=}"
: "${FG_MAGENTA:=}"
: "${FG_RED:=}"
: "${FG_CYAN:=}"
: "${FG_WHITE:=}"
: "${RESET:=}"

CHOICE_SYMBOLS=(a b d e f g h i j k l m n o p q r s t u v w x y z)
CHOICE_SYMBOL_COUNT=${#CHOICE_SYMBOLS[@]}

pass_entries=()
display_labels=()
choice_keys=()

die() {
  printf '%s%sError:%s %s\n' "$FG_RED" "$BOLD" "$RESET" "$1" >&2
  exit 1
}

format_label() {
  local entry="$1"
  local label="$entry"

  if [[ "$label" == */mfa ]]; then
    label="${label%/mfa}"
  elif [[ "$label" == "mfa" ]]; then
    label="(root)"
  fi

  if [[ -z "$label" ]]; then
    label="(root)"
  fi

  label="${label//\// > }"
  printf '%s' "$label"
}

index_to_choice_key() {
  local idx="$1"
  local key=""
  local remainder
  local char

  while true; do
    remainder=$((idx % CHOICE_SYMBOL_COUNT))
    char="${CHOICE_SYMBOLS[$remainder]}"
    key="$char$key"
    idx=$(((idx / CHOICE_SYMBOL_COUNT) - 1))
    if (( idx < 0 )); then
      break
    fi
  done

  printf '%s' "$key"
}

choose_entry() {
  local total="$1"

  if (( total == 1 )); then
    printf '%sAuto-selecting:%s %s%s%s\n' "$DIM" "$RESET" "$FG_GREEN" "${display_labels[0]}" "$RESET" >&2
    printf '0'
    return 0
  fi

  if ! command -v fzf >/dev/null 2>&1; then
    die "Missing dependency: require 'fzf'."
  fi

  local selected_line
  local prompt pointer marker header
  local tmp_input tmp_script
  tmp_input=$(mktemp "${TMPDIR:-/tmp}/mfa_fzf_input.XXXXXX")
  tmp_script=$(mktemp "${TMPDIR:-/tmp}/mfa_fzf_order.XXXXXX")
  trap 'rm -f "$tmp_input" "$tmp_script"' INT TERM EXIT

  # Pre-render the list once so we can reuse it for fuzzy and exact passes.
  {
    for ((i=0; i<total; i++)); do
      local slot
      slot="${choice_keys[$i]}"
      printf '%s\t%s%s%s  %s%s%s\t%s%s%s\n' \
        "$i" \
        "$BOLD$FG_CYAN" "$slot" "$RESET" \
        "$FG_BLUE" "${display_labels[$i]}" "$RESET" \
        "$DIM" "${pass_entries[$i]}" "$RESET"
    done
  } > "$tmp_input"

  cat <<'SCRIPT' > "$tmp_script"
#!/bin/bash
set -euo pipefail

data_file="$1"
query="${FZF_QUERY-}"
delimiter=$'\t'

# Treat blank or whitespace-only queries as fuzzy-only.
if [[ -z "${query//[[:space:]]/}" ]]; then
  cat "$data_file"
  exit 0
fi

exact_lines=""
if exact_lines=$(fzf --filter "$query" --exact --ansi --nth=2,3 \
    --delimiter="$delimiter" --no-sort < "$data_file" 2>/dev/null); then
  :
else
  exact_lines=""
fi

if [[ -z "$exact_lines" ]]; then
  cat "$data_file"
  exit 0
fi

seen=""
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  idx=${line%%"$delimiter"*}
  seen+=" $idx"
  printf '%s\n' "$line"
done <<< "$exact_lines"

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  idx=${line%%"$delimiter"*}
  case " $seen " in
    *" $idx "*)
      continue
      ;;
  esac
  printf '%s\n' "$line"
done < "$data_file"
SCRIPT
  chmod +x "$tmp_script"

  local -a binding_actions=()
  local i
  for ((i=0; i<total; i++)); do
    local key="${choice_keys[$i]}"
    if [[ ${#key} -ne 1 ]]; then
      continue
    fi

    local action="ctrl-${key}:first"
    local steps=$i
    while (( steps > 0 )); do
      action+="+down"
      steps=$((steps - 1))
    done
    action+="+accept"
    binding_actions+=("$action")
  done

  printf -v prompt '%s:: Search >%s ' "$BOLD$FG_MAGENTA" "$RESET"
  pointer='>>'
  marker='>>'
  printf -v header '%sList of TOTPs%s\n%sType to filter | Enter to select | Ctrl+letter to select | Arrows to nav | Esc to exit%s' \
    "$BOLD$FG_CYAN" "$RESET" "$DIM" "$RESET"

  local -a bind_options=()
  bind_options+=("--bind" "change:reload($tmp_script $tmp_input)+first")
  if (( ${#binding_actions[@]} > 0 )); then
    local IFS=,
    bind_options+=("--bind" "${binding_actions[*]}")
  fi

  if ! selected_line=$( \
    fzf --ansi --with-nth=2,3 --delimiter=$'\t' \
      --prompt "$prompt" --pointer "$pointer" --marker "$marker" \
      --height=80% --layout=reverse --border --info=inline \
      --header "$header" --tiebreak=index --no-sort \
      "${bind_options[@]}" < "$tmp_input"
  ); then
    rm -f "$tmp_input" "$tmp_script"
    trap - INT TERM EXIT
    return 1
  fi

  rm -f "$tmp_input" "$tmp_script"
  trap - INT TERM EXIT
  printf '%s' "${selected_line%%$'\t'*}"
  return 0
}

format_otp() {
  local digits="$1"
  local len=${#digits}
  local chunk=3
  local idx=0
  local result=""

  while (( idx < len )); do
    local part="${digits:idx:chunk}"
    if [[ -n "$result" ]]; then
      result+=" "
    fi
    result+="$part"
    idx=$((idx + chunk))
  done

  printf '%s' "$result"
}

render_progress() {
  local remaining="$1"
  local step="$2"
  local width=24
  local elapsed=$((step - remaining))

  if (( elapsed < 0 )); then
    elapsed=0
  elif (( elapsed > step )); then
    elapsed=$step
  fi

  local filled=$((elapsed * width / step))
  local empty=$((width - filled))
  local filled_bar=""
  local empty_bar=""

  if (( filled > 0 )); then
    filled_bar="$(printf '%*s' "$filled" '' | tr ' ' '=')"
  fi
  if (( empty > 0 )); then
    empty_bar="$(printf '%*s' "$empty" '' | tr ' ' '.')"
  fi

  local color="$FG_GREEN"
  if (( remaining <= 5 )); then
    color="$FG_RED"
  elif (( remaining <= 10 )); then
    color="$FG_YELLOW"
  fi

  printf '%s[%s%s%s%s]%s %s%2ds remaining%s\n' \
    "$DIM" "$FG_CYAN" "$filled_bar" "$DIM" "$empty_bar" "$RESET" "$color" "$remaining" "$RESET"
}

copy_to_clipboard() {
  local text="$1"

  # Mirror passage's robust clipboard strategy:
  # - Prefer pbcopy on macOS
  # - On Linux, choose wl-copy vs xclip order based on Wayland/X11
  # - Never crash the script on failure; try next tool

  if command -v pbcopy >/dev/null 2>&1; then
    if printf '%s' "$text" | pbcopy >/dev/null 2>&1; then return 0; fi
  fi

  local try_wayland=0
  if [[ -n "${WAYLAND_DISPLAY-}" ]]; then
    try_wayland=1
  fi

  if (( try_wayland )); then
    if command -v wl-copy >/dev/null 2>&1; then
      if printf '%s' "$text" | wl-copy >/dev/null 2>&1; then return 0; fi
    fi
    if command -v xclip >/dev/null 2>&1; then
      if printf '%s' "$text" | xclip -selection clipboard >/dev/null 2>&1; then return 0; fi
    fi
  else
    if command -v xclip >/dev/null 2>&1; then
      if printf '%s' "$text" | xclip -selection clipboard >/dev/null 2>&1; then return 0; fi
    fi
    if command -v wl-copy >/dev/null 2>&1; then
      if printf '%s' "$text" | wl-copy >/dev/null 2>&1; then return 0; fi
    fi
  fi

  if command -v xsel >/dev/null 2>&1; then
    if printf '%s' "$text" | xsel --clipboard --input >/dev/null 2>&1; then return 0; fi
  fi

  return 1
}

show_result() {
  local label="$1"
  local entry="$2"
  local otp="$3"
  local pretty="$4"
  local copied="$5"

  
  if command -v figlet >/dev/null 2>&1; then
    local figlet_text
    figlet_text="$(printf '%s' "$pretty" | sed 's/ /  /g')"
    printf '%s' "$FG_CYAN"
    figlet "$figlet_text"
    printf '%s' "$RESET"
  else
    printf '%s%s%s%s\n' "$BOLD" "$FG_CYAN" "$pretty" "$RESET"
  fi

  local now
  now=$(date +%s)
  local modulo=$((now % TOTP_WINDOW))
  local remaining=$((TOTP_WINDOW - modulo))
  if (( remaining == 0 )); then
    remaining=$TOTP_WINDOW
  fi

  printf '\n'
  render_progress "$remaining" "$TOTP_WINDOW"
  printf '\n'
}

# Generate an OTP from a pass entry while avoiding secret exposure in argv.
# Rules:
# - Exactly one line (ignoring trailing newlines); multi-line content is rejected.
# - No URI support; entry must be a single-line base32 secret.
# - Whitespace in the single line is stripped.
mfa_generate_otp_from_pass() {
  local entry="$1"
  local content first rest secret code

  # Read decrypted content into memory once; not exposed via ps/argv.
  if ! content="$(pass show -- "$entry")"; then
    return 1
  fi

  # Split first line and the remainder (if any)
  first="${content%%$'\n'*}"
  if [[ "$content" == *$'\n'* ]]; then
    rest="${content#*$'\n'}"
  else
    rest=""
  fi

  # Reject additional non-whitespace content beyond the first line
  if [[ -n "${rest//[[:space:]]/}" ]]; then
    die "MFA entry must contain exactly one line (base32 secret)."
  fi

  # Trim whitespace within the first line
  secret="${first//[[:space:]]/}"

  if [[ -z "$secret" ]]; then
    die "MFA secret is empty. Ensure one non-empty line."
  fi
  if [[ "$secret" == otpauth://* ]]; then
    die "otpauth URIs are not supported. Store the base32 secret only (one line)."
  fi

  # Feed the secret via stdin so it never appears in argv.
  if ! code="$(printf '%s' "$secret" | oathtool --totp -b - 2>/dev/null)"; then
    die "oathtool failed to generate a code."
  fi

  # Minimize lifetime of sensitive variables
  unset -v content first rest secret || true

  printf '%s' "$code"
}

main() {
  pass_entries=()
  display_labels=()
  choice_keys=()

  if [[ ! -d "$PASSWORD_STORE_DIR" ]]; then
    die "Password store directory '$PASSWORD_STORE_DIR' does not exist."
  fi

  local file
  while IFS= read -r -d '' file; do
    local rel="${file#$PASSWORD_STORE_DIR/}"
    rel="${rel%.gpg}"
    pass_entries+=("$rel")
  done < <(find "$PASSWORD_STORE_DIR" -type f \( -name 'mfa' -o -name 'mfa.gpg' \) -print0)

  if [[ ${#pass_entries[@]} -eq 0 ]]; then
    die "No MFA files found in '$PASSWORD_STORE_DIR'."
  fi

  local entry
  for entry in "${pass_entries[@]}"; do
    display_labels+=("$(format_label "$entry")")
  done

  local total=${#pass_entries[@]}
  local i
  for ((i=0; i<total; i++)); do
    choice_keys+=("$(index_to_choice_key "$i")")
  done

  local selection
  selection=""

  # If the user supplied a path-like argument that exactly matches an entry,
  # auto-select it and skip fzf. This restores the pre-fzf behavior while
  # keeping the new interactive flow when no exact match is found.
  if (( $# > 0 )); then
    local query="$*"
    # Normalize query: convert " > " to '/', drop extra spaces, strip trailing '/mfa'.
    query="${query// > /\/}"
    query="${query//>/\/}"  # handle cases like 'work>openai' → 'work/openai'
    query="${query//  / }"
    query="${query%/}"
    if [[ "$query" == */mfa ]]; then
      query="${query%/mfa}"
    fi

    # Try to find an exact match on the normalized path.
    local matched_index=-1
    for ((i=0; i<total; i++)); do
      local ent norm
      ent="${pass_entries[$i]}"
      norm="$ent"
      if [[ "$norm" == */mfa ]]; then
        norm="${norm%/mfa}"
      fi
      if [[ "$norm" == "$query" || "$ent" == "$query" || "$ent" == "$query/mfa" ]]; then
        matched_index=$i
        break
      fi
    done

    if (( matched_index >= 0 )); then
      printf '%sAuto-selecting:%s %s%s%s\n' "$DIM" "$RESET" "$FG_GREEN" "${display_labels[$matched_index]}" "$RESET" >&2
      selection="$matched_index"
    fi
  fi

  # If no exact match from args, fall back to interactive chooser.
  if [[ -z "$selection" ]]; then
    if ! selection="$(choose_entry "$total")"; then
      printf '%sEscape detected. Session closed.%s\n' "$DIM" "$RESET"
      return 0
    fi
  fi

  local selected_entry="${pass_entries[$selection]}"
  local selected_label="${display_labels[$selection]}"

  if ! command -v pass >/dev/null 2>&1 || ! command -v oathtool >/dev/null 2>&1; then
    die "Missing dependencies: require 'pass' and 'oathtool'."
  fi

  # Generate OTP without exposing the secret via argv/ps.
  # Enforce: exactly one non-empty line; no URI support; spaces trimmed.
  local otp
  if ! otp="$(
    mfa_generate_otp_from_pass "$selected_entry"
  )"; then
    die "Failed to generate OTP for '$selected_entry'."
  fi

  local pretty
  pretty="$(format_otp "$otp")"

  local copy_status=1
  if copy_to_clipboard "$otp"; then
    copy_status=0
  fi

  show_result "$selected_label" "$selected_entry" "$otp" "$pretty" "$copy_status"
}

main "$@"
