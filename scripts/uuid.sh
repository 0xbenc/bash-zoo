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
echo "UUID copied to clipboard: $UUID"
