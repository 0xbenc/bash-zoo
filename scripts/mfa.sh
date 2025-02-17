#!/bin/bash
# Script: mfa.sh
# Description:
#   This script recursively searches ~/.password-store for any file named "mfa" (or "mfa.gpg").
#   It builds an alphabetical list showing the prefix (the secret’s path without the trailing "/mfa")
#   for each MFA entry. When you choose a token, it retrieves the secret using "pass show"
#   and generates a TOTP with oathtool. Finally, the OTP is displayed in ASCII art using figlet.
#
# Usage:
#   ./mfa_selector.sh
#
# Dependencies:
#   pass
#   oathtool
#   figlet
#

# Set the password store directory
PASSWORD_STORE_DIR="$HOME/.password-store"

# Ensure the password store directory exists
if [[ ! -d "$PASSWORD_STORE_DIR" ]]; then
    echo "Password store directory '$PASSWORD_STORE_DIR' does not exist."
    exit 1
fi

# Recursively find files named "mfa" or "mfa.gpg" in the password store.
# (This handles both encrypted and unencrypted entries.)
mapfile -t mfa_files < <(find "$PASSWORD_STORE_DIR" -type f \( -name "mfa" -o -name "mfa.gpg" \))

# If no MFA files were found, exit.
if [[ ${#mfa_files[@]} -eq 0 ]]; then
    echo "No MFA files found in '$PASSWORD_STORE_DIR'."
    exit 1
fi

# Declare associative arrays to map letter tokens to the pass entry and its display prefix.
declare -A token_to_pass
declare -A token_to_prefix

# Create an array of letters for unique keys (assuming there are fewer than 26 entries)
letters=( {a..z} )

echo "Available MFA entries:"

counter=0
for file in "${mfa_files[@]}"; do
    # Remove the leading password store directory (and a possible slash)
    relpath="${file#$PASSWORD_STORE_DIR/}"
    # Remove the .gpg extension if present
    pass_entry="${relpath%.gpg}"
    # Determine the display prefix:
    # If the entry ends with "/mfa", remove that part for display.
    if [[ "$pass_entry" == */mfa ]]; then
        display_prefix="${pass_entry%/mfa}"
    elif [[ "$pass_entry" == "mfa" ]]; then
        display_prefix="(root)"
    else
        # Fallback (should not normally happen)
        display_prefix="$pass_entry"
    fi

    # Assign a unique letter token to this entry
    token="${letters[$counter]}"
    token_to_pass["$token"]="$pass_entry"
    token_to_prefix["$token"]="$display_prefix"
    
    echo "  [$token] $display_prefix"
    ((counter++))
done

# Prompt the user to choose one of the entries
read -p "Enter the letter corresponding to the MFA you want to generate: " user_choice

# Validate the selection
if [[ -z "${token_to_pass[$user_choice]}" ]]; then
    echo "Invalid selection. Exiting."
    exit 1
fi

# Retrieve the chosen pass entry.
# This is the value you'll use with the "pass" command.
selected_pass="${token_to_pass[$user_choice]}"

# Generate the OTP:
# "pass show" retrieves the secret, and oathtool generates the TOTP.
otp=$(oathtool --totp -b "$(pass show "$selected_pass")")

# Check for errors generating the OTP
if [[ $? -ne 0 ]]; then
    echo "Failed to generate OTP for '$selected_pass'."
    exit 1
fi

# Output the OTP with figlet on a new line.
echo "OTP for [$user_choice] (${token_to_prefix[$user_choice]}):"

# Insert a space between each digit/character of the OTP
otp_spaced=$(echo "$otp" | sed 's/./& /g' | sed 's/ $//')

# Now display the spaced OTP with figlet
figlet "$otp_spaced"
