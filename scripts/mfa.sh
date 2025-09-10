#!/bin/bash
set -euo pipefail
# macOS Bash 3.2–compatible MFA helper using pass + oathtool + figlet
# - No mapfile/readarray
# - No associative arrays
# - Uses pbcopy on macOS, xclip if present (Linux)

PASSWORD_STORE_DIR="$HOME/.password-store"

if [[ ! -d "$PASSWORD_STORE_DIR" ]]; then
  echo "Password store directory '$PASSWORD_STORE_DIR' does not exist."
  exit 1
fi

# Collect matching files safely (handles spaces) into mfa_files[]
mfa_files=()
while IFS= read -r -d '' f; do
  mfa_files+=("$f")
done < <(find "$PASSWORD_STORE_DIR" -type f \( -name "mfa" -o -name "mfa.gpg" \) -print0)

if [[ ${#mfa_files[@]} -eq 0 ]]; then
  echo "No MFA files found in '$PASSWORD_STORE_DIR'."
  exit 1
fi

# Build parallel arrays (index-based rather than associative)
pass_entries=()
display_prefixes=()

for file in "${mfa_files[@]}"; do
  relpath="${file#$PASSWORD_STORE_DIR/}"
  pass_entry="${relpath%.gpg}"

  if [[ "$pass_entry" == */mfa ]]; then
    display_prefix="${pass_entry%/mfa}"
  elif [[ "$pass_entry" == "mfa" ]]; then
    display_prefix="(root)"
  else
    display_prefix="$pass_entry"
  fi

  pass_entries+=("$pass_entry")
  display_prefixes+=("$display_prefix")
done

# Limit to 26 items (a–z). Expand if you need more.
letters=( {a..z} )
max=${#pass_entries[@]}
if (( max > 26 )); then
  echo "Note: Showing first 26 entries (a–z). You have $max matches."
  max=26
fi

echo "Available MFA entries:"
for ((i=0; i<max; i++)); do
  echo "  [${letters[$i]}] ${display_prefixes[$i]}"
done

read -p "Enter the letter corresponding to the MFA you want to generate: " user_choice

# Find the index of the chosen letter
choice_idx=-1
for ((i=0; i<max; i++)); do
  if [[ "$user_choice" == "${letters[$i]}" ]]; then
    choice_idx=$i
    break
  fi
done

if (( choice_idx < 0 )); then
  echo "Invalid selection. Exiting."
  exit 1
fi

selected_pass="${pass_entries[$choice_idx]}"

# Generate OTP
if ! command -v pass >/dev/null 2>&1 || ! command -v oathtool >/dev/null 2>&1; then
  echo "Missing dependencies: require 'pass' and 'oathtool'." >&2
  exit 1
fi

otp="$(oathtool --totp -b "$(pass show "$selected_pass")")"
if [[ -z "$otp" ]]; then
  echo "Failed to generate OTP for '$selected_pass'."
  exit 1
fi

# Copy to clipboard: pbcopy (macOS) or xclip (Linux)
if command -v pbcopy >/dev/null 2>&1; then
  printf "%s" "$otp" | pbcopy
elif command -v xclip >/dev/null 2>&1; then
  printf "%s" "$otp" | xclip -selection clipboard
else
  echo "Warning: No clipboard tool found (pbcopy/xclip). OTP not copied." >&2
fi

# Pretty print with figlet spacing
figlet_text="$(printf "%s" "$otp" | sed 's/./& /g; s/ $//')"

echo "OTP for [${letters[$choice_idx]}] (${display_prefixes[$choice_idx]}): copied to clipboard."
figlet "$figlet_text"
