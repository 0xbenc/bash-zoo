#!/bin/bash

# Directories
INSTALLERS_DIR="installers"
SCRIPTS_DIR="scripts"

# Ensure directories exist
if [[ ! -d "$INSTALLERS_DIR" || ! -d "$SCRIPTS_DIR" ]]; then
    echo "Error: Both '$INSTALLERS_DIR' and '$SCRIPTS_DIR' directories must exist."
    exit 1
fi

# Collect script names
scripts=($(ls "$SCRIPTS_DIR" | grep '\.sh$' | sed 's/\.sh$//'))
selected=($(for _ in "${scripts[@]}"; do echo 0; done))
current=0

# Function to draw the menu
draw_menu() {
    clear
    echo "Use 'J' and 'K' to move, 'H' to toggle, 'L' to confirm."
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

# Function to handle user input
while true; do
    draw_menu
    read -rsn1 input
    case "$input" in
        "k") ((current = (current - 1 + ${#scripts[@]}) % ${#scripts[@]})) ;;
        "j") ((current = (current + 1) % ${#scripts[@]})) ;;
        "h") selected[current]=$((1 - selected[current])) ;; # Toggle check/uncheck
        "l") break ;;
    esac
done

# Process selected scripts
clear
echo "Installing selected scripts..."
selected_scripts=()
for i in "${!scripts[@]}"; do
    if [[ ${selected[i]} -eq 1 ]]; then
        script_name="${scripts[i]}"
        selected_scripts+=("$script_name")
        chmod +x "$SCRIPTS_DIR/$script_name.sh"
        chmod +x "$INSTALLERS_DIR/$script_name.sh"
        "$INSTALLERS_DIR/$script_name.sh"
    fi
done

# Add selected scripts to PATH
if [[ ${#selected_scripts[@]} -gt 0 ]]; then
    USER_SHELL=$(basename "$SHELL")
    RC_FILE=""
    case "$USER_SHELL" in
        "bash") RC_FILE="$HOME/.bashrc" ;;
        "zsh") RC_FILE="$HOME/.zshrc" ;;
    esac
    
    if [[ -n "$RC_FILE" ]]; then
        echo "Adding scripts to your shell configuration ($RC_FILE)..."
        for script in "${selected_scripts[@]}"; do
            echo "alias $script=\"$PWD/$SCRIPTS_DIR/$script.sh\"" >> "$RC_FILE"
        done
        echo "Reloading shell configuration..."
        source "$RC_FILE"
    else
        echo "Warning: Could not detect a supported shell. Add the scripts manually to your PATH."
    fi
else
    echo "No scripts selected. Exiting."
fi

echo "Installation complete! You can now use the selected scripts as commands."

