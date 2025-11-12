#!/bin/bash
set -euo pipefail

# uuid: generate a UUID and copy to clipboard (supports macOS/Linux)

gen_uuid() {
  local u=""
  # Prefer uuidgen if present
  if command -v uuidgen >/dev/null 2>&1; then
    # Some platforms don't support --random; fall back to default
    if uuidgen --help 2>/dev/null | grep -qi -- "--random"; then
      u="$(uuidgen --random)"
    else
      u="$(uuidgen)"
    fi
  fi
  # Linux kernel fallback
  if [[ -z "$u" && -r /proc/sys/kernel/random/uuid ]]; then
    u="$(cat /proc/sys/kernel/random/uuid)"
  fi
  # Python fallback if available
  if [[ -z "$u" ]] && command -v python3 >/dev/null 2>&1; then
    u="$(python3 - <<'PY'
import uuid
print(uuid.uuid4())
PY
)"
  fi
  if [[ -z "$u" ]]; then
    echo "Error: unable to generate UUID (need uuidgen or python3)." >&2
    return 1
  fi
  printf '%s' "$u"
}

copy_clipboard() {
  if command -v pbcopy >/dev/null 2>&1; then
    printf '%s' "$1" | pbcopy
    return 0
  fi
  if command -v xclip >/dev/null 2>&1; then
    printf '%s' "$1" | xclip -selection clipboard
    return 0
  fi
  if command -v xsel >/dev/null 2>&1; then
    printf '%s' "$1" | xsel --clipboard --input
    return 0
  fi
  return 1
}

UUID="$(gen_uuid)"
if ! copy_clipboard "$UUID"; then
  echo "Warning: no clipboard tool found (pbcopy/xclip/xsel)." >&2
fi

# Colors (TTY-aware, disabled by NO_COLOR)
is_tty=0
if [[ -t 1 ]]; then is_tty=1; fi
if [[ ${NO_COLOR:-} != "" ]]; then is_tty=0; fi

FG_CYAN=""; RESET=""; BOLD=""
if [[ $is_tty -eq 1 ]] && command -v tput >/dev/null 2>&1; then
  colors="$(tput colors 2>/dev/null || printf '0')"
  if [[ "$colors" =~ ^[0-9]+$ ]] && [[ "$colors" -ge 8 ]]; then
    FG_CYAN="$(tput setaf 6 2>/dev/null || printf '')"
    BOLD="$(tput bold 2>/dev/null || printf '')"
    RESET="$(tput sgr0 2>/dev/null || printf '')"
  else
    RESET="$(tput sgr0 2>/dev/null || printf '')"
  fi
fi

# Basic gum styling when available and writing to a TTY
use_gum=0
if [[ -t 1 ]] && command -v gum >/dev/null 2>&1; then
  use_gum=1
fi

if [[ $use_gum -eq 1 ]]; then
  # Colorize UUID within styled box (ANSI preserved by gum)
  gum style \
    --border double \
    --align center \
    --margin "1 2" \
    --padding "1 3" \
    "UUID copied to clipboard" \
    "${FG_CYAN}${UUID}${RESET}"
else
  # Plain fallback with colored UUID when possible
  printf 'UUID copied to clipboard: %s%s%s\n' "$FG_CYAN" "$UUID" "$RESET"
fi
