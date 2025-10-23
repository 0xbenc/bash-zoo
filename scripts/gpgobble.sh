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

  printf '==> %s\n' "$f"

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
      printf '    would import: %d new of %d key(s)\n' "$new_here" "${#fps[@]}"
    else
      printf '    would import (idempotent; all present)\n'
    fi
  else
    if ! gpg --batch --yes --quiet --import "$f" >/dev/null 2>&1; then
      printf '    import failed (skipping)\n' >&2
      continue
    fi
  fi

  # 3) Local-sign + trust management for each primary fp
  for fp in "${fps[@]}"; do
    [[ -n "$fp" ]] || continue
    keys_considered=$((keys_considered+1))

    # (A) Skip if a secret key exists locally
    if gpg --batch --quiet --list-secret-keys "$fp" >/dev/null 2>&1; then
      printf '    skip (own secret key present): %s\n' "$fp"
      processed_any=true
      skipped_secret_count=$((skipped_secret_count+1))
      continue
    fi

    # (B) Local-sign (idempotent). Avoid --batch so pinentry can prompt if needed.
    if $dry_run; then
      printf '    would localsign (idempotent): %s\n' "$fp"
      would_lsign_count=$((would_lsign_count+1))
    else
      if gpg --quiet --yes --quick-lsign-key "$fp" >/dev/null 2>&1; then
        printf '    localsign OK: %s\n' "$fp"
      else
        printf '    localsign FAILED (continuing to set ownertrust): %s\n' "$fp" >&2
      fi
    fi

    # (C) Decide based on current ownertrust
    lvl="$(trust_level "$fp")"
    if [[ "$lvl" == "5" ]]; then
      printf '    skip trust (already ultimate): %s\n' "$fp"
    elif [[ "$lvl" == "4" ]]; then
      printf '    trust already full: %s\n' "$fp"
    else
      if $dry_run; then
        printf '    would trust full (4): %s\n' "$fp"
        would_trust_full_count=$((would_trust_full_count+1))
      else
        printf '    trust full (4): %s\n' "$fp"
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
    if ! gpg --batch --yes --quiet --import-ownertrust "$tmp" >/dev/null 2>&1; then
      printf 'Failed importing ownertrust updates (file: %s)\n' "$tmp" >&2
      exit 1
    fi
  fi

  if $processed_any; then
    printf 'Done. Imported keys, local-signed non-local keys, and set ownertrust=FULL (4) where needed.\n'
  else
    printf 'No keys were imported.\n'
  fi
else
  printf 'Dry run complete. No changes made.\n'
  printf 'Summary: files=%d, keys=%d, skipped_secret=%d, would_lsign=%d, would_set_trust_full=%d, would_import_new=%d\n' \
    "$files_scanned" "$keys_considered" "$skipped_secret_count" "$would_lsign_count" "$would_trust_full_count" "$would_import_new_count"
fi
