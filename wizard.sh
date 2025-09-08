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

#############################################
# Interactive selection (enquirer-style)
#############################################

ensure_enquirer() {
    # Requires node; then ensures enquirer is resolvable (tries local vendor)
    if ! command -v node >/dev/null 2>&1; then
        return 1
    fi

    # Check if enquirer is already resolvable (including via vendor path)
    if NODE_PATH="$PWD/.interactive/node_modules${NODE_PATH:+:$NODE_PATH}" \
       node -e "require('enquirer')" >/dev/null 2>&1; then
        return 0
    fi

    # Attempt to install enquirer to local vendor dir (.interactive)
    mkdir -p "$PWD/.interactive"
    if [[ ! -f "$PWD/.interactive/package.json" ]]; then
        printf '{"name":"bash-zoo-interactive","private":true}\n' > "$PWD/.interactive/package.json"
    fi

    # Choose a package manager (prefer npm; fallback to pnpm/yarn/bun)
    PM=""
    if command -v npm >/dev/null 2>&1; then
        PM="npm"
    elif command -v pnpm >/dev/null 2>&1; then
        PM="pnpm"
    elif command -v yarn >/dev/null 2>&1; then
        PM="yarn"
    elif command -v bun >/dev/null 2>&1; then
        PM="bun"
    else
        return 1
    fi

    echo "Preparing modern selector (installing enquirer)..."
    case "$PM" in
        npm)
            ( cd "$PWD/.interactive" && npm install --silent enquirer@^2 ) || return 1 ;;
        pnpm)
            ( cd "$PWD/.interactive" && pnpm add -s enquirer@^2 ) || return 1 ;;
        yarn)
            ( cd "$PWD/.interactive" && yarn add -s enquirer@^2 ) || return 1 ;;
        bun)
            ( cd "$PWD/.interactive" && bun add -y enquirer@^2 ) || return 1 ;;
    esac

    # Re-check
    if NODE_PATH="$PWD/.interactive/node_modules${NODE_PATH:+:$NODE_PATH}" \
       node -e "require('enquirer')" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Build JSON payload for the Node-based selector
payload='{ "title": "Select scripts to install", "choices": ['
for i in "${!scripts[@]}"; do
    label="${scripts[i]}"
    if [[ "${scripts_has_deps[i]}" == "yes" ]]; then
        label+=" (installer)"
    else
        label+=" (alias-only)"
    fi
    # escape quotes in label just in case
    esc_label=$(printf '%s' "$label" | sed 's/"/\\"/g')
    esc_name=$(printf '%s' "${scripts[i]}" | sed 's/"/\\"/g')
    payload+="{\"name\":\"$esc_name\",\"message\":\"$esc_label\"},"
done
# Trim trailing comma and close array
payload=${payload%,}
payload+='] }'

# Run the selector; collect selected names (one per line)
if ensure_enquirer; then
    selected_names=()
    # Pass payload in env var to keep stdin/tty free for interactivity
    while IFS= read -r __sel_line; do
        [[ -z "${__sel_line:-}" ]] && continue
        selected_names+=("$__sel_line")
    done < <(BZ_PAYLOAD="$payload" NODE_PATH="$PWD/.interactive/node_modules${NODE_PATH:+:$NODE_PATH}" node "bin/select.js")
else
    # Fallback to the original minimal interactivity when Node or enquirer are unavailable
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
    # Convert fallback selections into the same selected_names format
    selected_names=()
    for i in "${!scripts[@]}"; do
        if [[ ${selected[i]} -eq 1 ]]; then
            selected_names+=("${scripts[i]}")
        fi
    done
fi

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
    # Run installer if file exists; set executable bit if needed
    if [[ -f "$path" ]]; then
        chmod +x "$path" || true
        "$path"
        return 0
    fi
    echo "Warning: no installer for '$name' (expected $path)." >&2
    return 1
}

# Process selected scripts
for i in "${!scripts[@]}"; do
    script_name="${scripts[i]}"
    # check if this script_name was selected
    for sel in "${selected_names[@]:-}"; do
        if [[ "$sel" == "$script_name" ]]; then
            selected_scripts+=("$script_name")
            chmod +x "$SCRIPTS_DIR/$script_name.sh"

            if [[ "${scripts_has_deps[i]}" == "yes" ]]; then
                install_with_installer "$script_name" "$OS_TYPE" || true
            else
                echo "Skipping installer for '$script_name' (alias-only)."
            fi
            break
        fi
    done
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
    echo "Aliases added. Open a new terminal or run:"
    echo "  exec $USER_SHELL -l"
    echo "to reload your shell configuration. Skipping auto-reload to avoid cross-shell issues."
else
    echo "No scripts selected. Exiting."
    exit 0
fi

echo "Installation complete! You can now use the selected scripts as commands."
