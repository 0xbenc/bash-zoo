#!/usr/bin/env bash
# gpgobble — bulk import public keys + local-sign + set ownertrust FULL (4) for non-local keys
#
# Behavior (no flags):
#  • Import all public keys from DIR (default ".")
#  • If this machine has the secret key for a fingerprint, DO NOT touch its trust/signature
#  • For others, local-sign (lsign) and set ownertrust to FULL (4) iff not already 4 or 5
#  • If trust is already ULTIMATE (5), leave it as-is (do not downgrade)
#
# Usage:
#   gpgobble [DIR]
# Examples:
#   gpgobble
#   gpgobble ./keys/work
#   GNUPGHOME=/tmp/gnupg gpgobble ./keys
#
# Bash zoo drop by 0xbenc 🐒

set -euo pipefail

# Flags and args
dry_run=false
dir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--dry-run)
      dry_run=true
      shift
      ;;
    -h|--help)
      cat <<'USAGE'
gpgobble — bulk import public keys + local-sign + set ownertrust FULL (4) for non-local keys

Usage:
  gpgobble [OPTIONS] [DIR]

Options:
  -n, --dry-run   Preview actions without changing your keyring
  -h, --help      Show this help and exit

Notes:
  - Imports all files in DIR (non-recursive; default ".").
  - For keys with a local secret key, nothing is signed or trust-tweaked.
  - For others, local-sign + set ownertrust to FULL (4) if not already 4 or 5.
USAGE
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      printf 'Unknown option: %s\n' "$1" >&2
      exit 2
      ;;
    *)
      if [[ -z "$dir" ]]; then
        dir="$1"
        shift
      else
        printf 'Too many positional arguments (only DIR is allowed): %s\n' "$1" >&2
        exit 2
      fi
      ;;
  esac
done

if [[ -z "$dir" ]]; then
  DIR="."
else
  DIR="$dir"
fi

if ! command -v gpg >/dev/null 2>&1; then
  printf 'gpg not found in PATH. Install GnuPG first.\n' >&2
  exit 2
fi

if [[ ! -d "$DIR" ]]; then
  printf 'Directory not found: %s\n' "$DIR" >&2
  exit 2
fi

# Styling: colors (TTY-aware, disabled by NO_COLOR) and gum availability
is_tty=0
if [[ -t 1 ]]; then is_tty=1; fi
if [[ ${NO_COLOR:-} != "" ]]; then is_tty=0; fi

BOLD=""; DIM=""; FG_BLUE=""; FG_GREEN=""; FG_YELLOW=""; FG_MAGENTA=""; FG_RED=""; FG_CYAN=""; FG_WHITE=""; RESET=""
if [[ $is_tty -eq 1 ]] && command -v tput >/dev/null 2>&1; then
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

use_gum=0
if [[ $is_tty -eq 1 ]] && command -v gum >/dev/null 2>&1; then
  use_gum=1
fi

# Collect candidate files (shallow, no recursion).
prev_nullglob=$(shopt -p nullglob 2>/dev/null || true)
prev_dotglob=$(shopt -p dotglob 2>/dev/null || true)
shopt -s nullglob dotglob
FILES=("$DIR"/*)
eval "$prev_nullglob" 2>/dev/null || true
eval "$prev_dotglob" 2>/dev/null || true
if [[ ${#FILES[@]} -eq 0 ]]; then
  printf 'No files in %s\n' "$DIR"
  exit 0
fi

processed_any=false

# Dry-run counters
files_scanned=0
keys_considered=0
skipped_secret_count=0
would_lsign_count=0
would_trust_full_count=0
would_import_new_count=0

# Cache ownertrust once for speed.
ownertrust_cache="$(gpg --export-ownertrust 2>/dev/null || true)"

trust_level() {
  # Echoes numeric ownertrust level (1..5) if set; empty if unset.
  local fp="$1"
  awk -F: -v F="$fp" '$1==F {print $2; exit}' <<<"$ownertrust_cache"
}

# Will batch-apply ownertrust with a single import at the end.
declare -a TO_FULL=()

for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || continue
  files_scanned=$((files_scanned+1))
  # 1) Peek PRIMARY fingerprints (avoid subkeys) without importing; be robust to non-key files
  fps=()
  while IFS= read -r line; do
    fps+=("$line")
  done < <(
    ( gpg --with-colons --import-options import-show --import "$f" 2>/dev/null || true ) \
      | awk -F: '
          /^pub:/ {pub=1; next}
          /^fpr:/ && pub {print $10; pub=0}
        ' \
      | sort -u
  )
  [[ ${#fps[@]} -gt 0 ]] || continue

  printf '%s==> %s%s\n' "${BOLD}${FG_BLUE}" "$f" "$RESET"

  # 2) Real import (idempotent if already present)
  if $dry_run; then
    # Estimate whether import would add any new primary keys
    new_here=0
    for fp in "${fps[@]}"; do
      if ! gpg --batch --quiet --list-keys "$fp" >/dev/null 2>&1; then
        new_here=$((new_here+1))
      fi
    done
    would_import_new_count=$((would_import_new_count+new_here))
    if [[ $new_here -gt 0 ]]; then
      printf '%s    would import: %d new of %d key(s)%s\n' "${DIM}" "$new_here" "${#fps[@]}" "${RESET}"
    else
      printf '%s    would import (idempotent; all present)%s\n' "${DIM}" "${RESET}"
    fi
  else
    if [[ $use_gum -eq 1 ]]; then
      if ! gum spin --spinner points --title "Importing: $(basename "$f")" -- gpg --batch --yes --quiet --import "$f" >/dev/null 2>&1; then
        printf '%s    import failed (skipping)%s\n' "${FG_RED}" "${RESET}" >&2
        continue
      fi
    else
      if ! gpg --batch --yes --quiet --import "$f" >/dev/null 2>&1; then
        printf '%s    import failed (skipping)%s\n' "${FG_RED}" "${RESET}" >&2
        continue
      fi
    fi
  fi

  # 3) Local-sign + trust management for each primary fp
  for fp in "${fps[@]}"; do
    [[ -n "$fp" ]] || continue
    keys_considered=$((keys_considered+1))

    # (A) Skip if a secret key exists locally
    if gpg --batch --quiet --list-secret-keys "$fp" >/dev/null 2>&1; then
      printf '%s    skip (own secret key present): %s%s\n' "${FG_YELLOW}" "$fp" "${RESET}"
      processed_any=true
      skipped_secret_count=$((skipped_secret_count+1))
      continue
    fi

    # (B) Local-sign (idempotent). Avoid --batch so pinentry can prompt if needed.
    if $dry_run; then
      printf '%s    would localsign (idempotent): %s%s\n' "${DIM}${FG_MAGENTA}" "$fp" "${RESET}"
      would_lsign_count=$((would_lsign_count+1))
    else
      if gpg --quiet --yes --quick-lsign-key "$fp" >/dev/null 2>&1; then
        printf '%s    localsign OK:%s %s\n' "${FG_GREEN}" "${RESET}" "$fp"
      else
        printf '%s    localsign FAILED (continuing to set ownertrust): %s%s\n' "${FG_RED}" "$fp" "${RESET}" >&2
      fi
    fi

    # (C) Decide based on current ownertrust
    lvl="$(trust_level "$fp")"
    if [[ "$lvl" == "5" ]]; then
      printf '%s    skip trust (already ultimate): %s%s\n' "${DIM}" "$fp" "${RESET}"
    elif [[ "$lvl" == "4" ]]; then
      printf '%s    trust already full: %s%s\n' "${DIM}" "$fp" "${RESET}"
    else
      if $dry_run; then
        printf '%s    would trust full (4): %s%s\n' "${FG_CYAN}" "$fp" "${RESET}"
        would_trust_full_count=$((would_trust_full_count+1))
      else
        printf '%s    trust full (4):%s %s\n' "${FG_CYAN}" "${RESET}" "$fp"
        TO_FULL+=( "$fp" )
      fi
    fi

    processed_any=true
  done
done

# Batch-apply ownertrust=4 to all needed keys (idempotent; dedup first).
if ! $dry_run; then
  if [[ ${#TO_FULL[@]} -gt 0 ]]; then
    tmp="$(mktemp "${TMPDIR:-/tmp}/gpgobble.XXXXXX" 2>/dev/null || mktemp)"
    trap 'rm -f "$tmp"' EXIT
    printf '%s\n' "${TO_FULL[@]}" | sort -u | awk '{printf "%s:4:\n",$0}' > "$tmp"
    if [[ $use_gum -eq 1 ]]; then
      if ! gum spin --spinner points --title "Applying ownertrust FULL (4) to $(printf '%s\n' "${TO_FULL[@]}" | sort -u | wc -l | awk '{print $1}') key(s)" -- gpg --batch --yes --quiet --import-ownertrust "$tmp" >/dev/null 2>&1; then
        printf '%sFailed importing ownertrust updates (file: %s)%s\n' "${FG_RED}" "$tmp" "${RESET}" >&2
        exit 1
      fi
    else
      if ! gpg --batch --yes --quiet --import-ownertrust "$tmp" >/dev/null 2>&1; then
        printf '%sFailed importing ownertrust updates (file: %s)%s\n' "${FG_RED}" "$tmp" "${RESET}" >&2
        exit 1
      fi
    fi
  fi

  if $processed_any; then
    done_msg='Done. Imported keys, local-signed non-local keys, and set ownertrust=FULL (4) where needed.'
    if [[ $use_gum -eq 1 ]]; then
      gum style --border double --align center --margin "1 2" --padding "1 4" "$done_msg"
    else
      printf '%s\n' "$done_msg"
    fi
  else
    printf '%sNo keys were imported.%s\n' "${DIM}" "${RESET}"
  fi
else
  if [[ $use_gum -eq 1 ]]; then
    gum_lines=(
      "Dry run complete. No changes made."
      "files: $files_scanned"
      "keys: $keys_considered"
      "skipped_secret: $skipped_secret_count"
      "would_lsign: $would_lsign_count"
      "would_set_trust_full: $would_trust_full_count"
      "would_import_new: $would_import_new_count"
    )
    gum_width=50
    for line in "${gum_lines[@]}"; do
      len=${#line}
      if [[ $len -gt $gum_width ]]; then gum_width=$len; fi
    done
    gum style --border double --align center --width "$gum_width" --margin "1 2" --padding "1 4" "${gum_lines[@]}"
  else
    printf 'Dry run complete. No changes made.\n'
    printf 'Summary: files=%d, keys=%d, skipped_secret=%d, would_lsign=%d, would_set_trust_full=%d, would_import_new=%d\n' \
      "$files_scanned" "$keys_considered" "$skipped_secret_count" "$would_lsign_count" "$would_trust_full_count" "$would_import_new_count"
  fi
fi
