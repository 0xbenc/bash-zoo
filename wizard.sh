#!/bin/bash

set -euo pipefail

# Directories
INSTALLERS_DIR="installers"
SCRIPTS_DIR="scripts"
REGISTRY_FILE="$INSTALLERS_DIR/registry.tsv"

# Ensure directories exist
if [[ ! -d "$INSTALLERS_DIR" || ! -d "$SCRIPTS_DIR" ]]; then
    echo "Error: Both '$INSTALLERS_DIR' and '$SCRIPTS_DIR' directories must exist."
    exit 1
fi

if [[ ! -f "$REGISTRY_FILE" ]]; then
    echo "Error: Missing registry file: $REGISTRY_FILE"
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

if [[ "$OS_TYPE" == "other" ]]; then
    echo "Unsupported platform (not Debian-like Linux or macOS). No installers available."
    exit 0
fi

# Read registry and build candidate list for this OS
scripts=()
scripts_has_deps=()

while IFS=$'\t' read -r name oses has_deps _rest; do
    # skip comments and empty lines
    [[ -z "${name:-}" ]] && continue
    [[ "$name" =~ ^# ]] && continue
    # optional header line
    if [[ "$name" == "script" ]]; then
        continue
    fi

    # verify the script exists
    if [[ ! -f "$SCRIPTS_DIR/$name.sh" ]]; then
        # silently skip registry entries without a script
        continue
    fi

    # check OS allowlist
    include=0
    IFS=',' read -r -a os_list <<< "$oses"
    for os in "${os_list[@]}"; do
        if [[ "$os" == "$OS_TYPE" ]]; then
            include=1
            break
        fi
    done
    if [[ $include -eq 1 ]]; then
        scripts+=("$name")
        # normalize has_deps to yes/no without bash 4 lowercase feature
        deps_norm=$(printf '%s' "$has_deps" | tr '[:upper:]' '[:lower:]')
        case "$deps_norm" in
            yes|true|1) scripts_has_deps+=("yes") ;;
            *)          scripts_has_deps+=("no")  ;;
        esac
    fi
done < "$REGISTRY_FILE"

if [[ ${#scripts[@]} -eq 0 ]]; then
    echo "No installable scripts defined for OS '$OS_TYPE' in $REGISTRY_FILE"
    exit 0
fi

# selection state
selected=()
for _ in "${scripts[@]}"; do selected+=(0); done
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

        label="${scripts[i]}"
        if [[ "${scripts_has_deps[i]}" == "yes" ]]; then
            label+=" (installer)"
        else
            label+=" (alias-only)"
        fi
        echo -e "$label\e[0m"
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

install_with_installer() {
    local name="$1"
    local os="$2"
    local path="$INSTALLERS_DIR/$os/$name.sh"
    if [[ -x "$path" ]]; then
        chmod +x "$path"
        "$path"
        return 0
    fi
    echo "Warning: no installer for '$name' (expected $path)." >&2
    return 1
}

# Process selected scripts
for i in "${!scripts[@]}"; do
    if [[ ${selected[i]} -eq 1 ]]; then
        script_name="${scripts[i]}"
        selected_scripts+=("$script_name")
        chmod +x "$SCRIPTS_DIR/$script_name.sh"

        if [[ "${scripts_has_deps[i]}" == "yes" ]]; then
            install_with_installer "$script_name" "$OS_TYPE" || true
        else
            echo "Skipping installer for '$script_name' (alias-only)."
        fi
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
    # shellcheck disable=SC1091
    source "$RC_FILE" || true
else
    echo "No scripts selected. Exiting."
fi

echo "Installation complete! You can now use the selected scripts as commands."
