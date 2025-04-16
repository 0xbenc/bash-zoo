#!/bin/bash
# Script: mfa.sh
# Description:
#   This script recursively searches ~/.password-store for any file named "mfa" (or "mfa.gpg").
#   It builds an alphabetical list showing the prefix (the secret’s path without the trailing "/mfa")
#   for each MFA entry. When you choose a token, it retrieves the secret using "pass show"
#   and generates a TOTP with oathtool. The OTP is then copied to the clipboard using xclip
#   and displayed in ASCII art using figlet.
#
# Usage:
#   ./mfa.sh
#
# Dependencies:
#   pass
#   oathtool
#   figlet
#   xclip

PASSWORD_STORE_DIR="$HOME/.password-store"

if [[ ! -d "$PASSWORD_STORE_DIR" ]]; then
    echo "Password store directory '$PASSWORD_STORE_DIR' does not exist."
    exit 1
fi

mapfile -t mfa_files < <(find "$PASSWORD_STORE_DIR" -type f \( -name "mfa" -o -name "mfa.gpg" \))

if [[ ${#mfa_files[@]} -eq 0 ]]; then
    echo "No MFA files found in '$PASSWORD_STORE_DIR'."
    exit 1
fi

declare -A token_to_pass
declare -A token_to_prefix

letters=( {a..z} )

echo "Available MFA entries:"

counter=0
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

    token="${letters[$counter]}"
    token_to_pass["$token"]="$pass_entry"
    token_to_prefix["$token"]="$display_prefix"

    echo "  [$token] $display_prefix"
    ((counter++))
done

read -p "Enter the letter corresponding to the MFA you want to generate: " user_choice

if [[ -z "${token_to_pass[$user_choice]}" ]]; then
    echo "Invalid selection. Exiting."
    exit 1
fi

selected_pass="${token_to_pass[$user_choice]}"

otp=$(oathtool --totp -b "$(pass show "$selected_pass")")

if [[ $? -ne 0 ]]; then
    echo "Failed to generate OTP for '$selected_pass'."
    exit 1
fi

# Copy OTP to clipboard using xclip
echo -n "$otp" | xclip -selection clipboard

# Output confirmation
figlet_text=$(echo "$otp" | sed 's/./& /g' | sed 's/ $//')

echo "OTP for [$user_choice] (${token_to_prefix[$user_choice]}): copied to clipboard."
figlet "$figlet_text"
