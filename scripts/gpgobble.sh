#!/usr/bin/env bash
# gpgobble — bulk import public keys + set ownertrust to FULL (4) for non-local keys
#
# Behavior (no flags):
#  • Import all public keys from DIR (default ".")
#  • If this machine has the secret key for a fingerprint, DO NOT touch its trust
#  • For others, set ownertrust to FULL (4) iff not already full (4) or ultimate (5)
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

DIR="${1:-.}"

if ! command -v gpg >/dev/null 2>&1; then
  printf 'gpg not found in PATH. Install GnuPG first.\n' >&2
  exit 2
fi

if [[ ! -d "$DIR" ]]; then
  printf 'Directory not found: %s\n' "$DIR" >&2
  exit 2
fi

# Collect candidate files (shallow, no recursion) in a portable way.
# We'll try everything; non-key files will be skipped after import-show.
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
  if ! gpg --batch --yes --quiet --import "$f" >/dev/null 2>&1; then
    printf '    import failed (skipping)\n' >&2
    continue
  fi

  # 3) Trust management for each primary fp
  for fp in "${fps[@]}"; do
    [[ -n "$fp" ]] || continue

    # (A) Skip if a secret key exists locally
    if gpg --batch --quiet --list-secret-keys "$fp" >/dev/null 2>&1; then
      printf '    skip trust (secret key present): %s\n' "$fp"
      processed_any=true
      continue
    fi

    # (B) Decide based on current ownertrust
    lvl="$(trust_level "$fp")"
    if [[ "$lvl" == "5" ]]; then
      printf '    skip trust (already ultimate): %s\n' "$fp"
    elif [[ "$lvl" == "4" ]]; then
      printf '    trust already full: %s\n' "$fp"
    else
      printf '    trust full (4): %s\n' "$fp"
      TO_FULL+=( "$fp" )
    fi

    processed_any=true
  done
done

# Batch-apply ownertrust=4 to all needed keys (idempotent; dedup first).
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
  printf 'Done. Imported keys and set ownertrust=FULL (4) where needed.\n'
else
  printf 'No keys were imported.\n'
fi
