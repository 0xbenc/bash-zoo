#!/bin/bash

set -euo pipefail

# Directories
INSTALLERS_DIR="installers"
SCRIPTS_DIR="scripts"

# Ensure directories exist
if [[ ! -d "$INSTALLERS_DIR" || ! -d "$SCRIPTS_DIR" ]]; then
    echo "Error: Both '$INSTALLERS_DIR' and '$SCRIPTS_DIR' directories must exist."
    exit 1
fi

# Detect OS: debian-like linux, macOS, or other
OS_TYPE="other"
UNAME_S=$(uname -s)
if [[ "$UNAME_S" == "Darwin" ]]; then
    OS_TYPE="macos"
elif [[ "$UNAME_S" == "Linux" ]]; then
    if command -v apt >/dev/null 2>&1 || command -v apt-get >/dev/null 2>&1; then
        OS_TYPE="debian"
    fi
fi

# Collect script names based on platform
if [[ "$OS_TYPE" == "debian" ]]; then
    mapfile -t scripts < <(ls "$SCRIPTS_DIR" | grep '\.sh$' | sed 's/\.sh$//')
elif [[ "$OS_TYPE" == "macos" ]]; then
    # macOS: only support MFA
    if [[ -f "$SCRIPTS_DIR/mfa.sh" ]]; then
        scripts=("mfa")
    else
        echo "This repo currently supports only 'mfa' on macOS, but it was not found."
        exit 1
    fi
else
    echo "Unsupported platform (not Debian-like Linux or macOS). No installers available."
    exit 0
fi

selected=($(for _ in "${scripts[@]}"; do echo 0; done))
current=0

draw_menu() {
    clear
    echo "Use 'J' and 'K' to move, 'H' to toggle, 'L' to confirm."
    echo "Detected platform: $OS_TYPE"
    for i in "${!scripts[@]}"; do
        if [[ $i -eq $current ]]; then
            echo -ne "\e[1;32m> "
        else
            echo -ne "  "
        fi

        if [[ ${selected[i]} -eq 1 ]]; then
            echo -ne "[✔ ] "
        else
            echo -ne "[ ] "
        fi

        echo -e "${scripts[i]}\e[0m"
    done
}

# Handle user input
while true; do
    draw_menu
    read -rsn1 input
    case "$input" in
        "k") ((current = (current - 1 + ${#scripts[@]}) % ${#scripts[@]})) ;;
        "j") ((current = (current + 1) % ${#scripts[@]})) ;;
        "h") selected[current]=$((1 - selected[current])) ;;
        "l") break ;;
    esac
done

clear
echo "Installing selected scripts..."
selected_scripts=()

# Idempotent alias add/update
add_or_update_alias() {
    local name="$1"
    local target="$2"
    local rc_file="$3"
    local alias_line
    alias_line="alias $name=\"$target\""

    touch "$rc_file"
    if grep -qE "^alias[[:space:]]+$name=" "$rc_file"; then
        # Replace existing alias line
        if sed --version >/dev/null 2>&1; then
            sed -i -E "s|^alias[[:space:]]+$name=.*|$alias_line|" "$rc_file"
        else
            # macOS/BSD sed
            sed -i '' -E "s|^alias[[:space:]]+$name=.*|$alias_line|" "$rc_file"
        fi
    else
        echo "$alias_line" >> "$rc_file"
    fi
}

# Process selected scripts
for i in "${!scripts[@]}"; do
    if [[ ${selected[i]} -eq 1 ]]; then
        script_name="${scripts[i]}"
        selected_scripts+=("$script_name")
        chmod +x "$SCRIPTS_DIR/$script_name.sh"

        case "$OS_TYPE" in
            debian)
                if [[ -x "$INSTALLERS_DIR/debian/$script_name.sh" ]]; then
                    chmod +x "$INSTALLERS_DIR/debian/$script_name.sh"
                    "$INSTALLERS_DIR/debian/$script_name.sh"
                else
                    echo "Warning: no installer for '$script_name' (expected $INSTALLERS_DIR/debian/$script_name.sh)."
                fi
                ;;
            macos)
                if [[ -x "$INSTALLERS_DIR/macos/$script_name.sh" ]]; then
                    chmod +x "$INSTALLERS_DIR/macos/$script_name.sh"
                    "$INSTALLERS_DIR/macos/$script_name.sh"
                else
                    echo "Warning: no macOS installer for '$script_name' (expected $INSTALLERS_DIR/macos/$script_name.sh)."
                fi
                ;;
        esac
    fi
done

# Add selected scripts to shell rc idempotently
if [[ ${#selected_scripts[@]} -gt 0 ]]; then
    USER_SHELL=$(basename "${SHELL:-}")
    RC_FILE=""
    case "$USER_SHELL" in
        bash) RC_FILE="$HOME/.bashrc" ;;
        zsh)  RC_FILE="$HOME/.zshrc" ;;
        *)    RC_FILE="$HOME/.bashrc" ;;
    esac

    echo "Configuring aliases in $RC_FILE ..."
    for script in "${selected_scripts[@]}"; do
        add_or_update_alias "$script" "$PWD/$SCRIPTS_DIR/$script.sh" "$RC_FILE"
    done
    echo "Reloading shell configuration..."
    # shellcheck disable=SC1090
    source "$RC_FILE" || true
else
    echo "No scripts selected. Exiting."
fi

echo "Installation complete! You can now use the selected scripts as commands."
