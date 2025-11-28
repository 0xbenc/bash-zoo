#!/bin/bash

set -euo pipefail

usage() {
  echo "Usage: $0 [--all] [--exp] [--names <a,b,c>]" >&2
}

select_all=0
include_exp=0
names_csv=""
names_given=0
if [[ $# -gt 0 ]]; then
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
      --all|-a|all)
        select_all=1
        shift ;;
      --exp)
        include_exp=1
        shift ;;
      --names)
        if [[ $# -lt 2 ]]; then
          echo "--names requires a comma-separated argument" >&2
          exit 1
        fi
        names_csv="$2"
        names_given=1
        shift 2 ;;
      --names=*)
        names_csv="${arg#*=}"
        names_given=1
        shift ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        echo "Unknown argument: $arg" >&2
        usage
        exit 1
        ;;
    esac
  done
fi

# Directories
SETUP_DIR="setup"
SCRIPTS_DIR="scripts"
REGISTRY_FILE="$SETUP_DIR/registry.tsv"

# Ensure directories exist
if [[ ! -d "$SETUP_DIR" || ! -d "$SCRIPTS_DIR" ]]; then
    echo "Error: Both '$SETUP_DIR' and '$SCRIPTS_DIR' directories must exist."
    exit 1
fi

if [[ ! -f "$REGISTRY_FILE" ]]; then
    echo "Error: Missing registry file: $REGISTRY_FILE"
    exit 1
fi

# One-time ASCII animation ("0xbenc") before interactive selection
# - Skips if not a TTY or disabled via BZ_NO_ASCII=1
# - Uses text frame files under ascii/0xbenc_large or ascii/0xbenc_small
#   (>=96 cols uses large; <=95 uses small). BZ_ASCII_DIR overrides.
play_ascii_once() {
  if [[ -n "${BZ_NO_ASCII:-}" ]]; then
    return 0
  fi
  if [[ ! -t 1 ]]; then
    return 0
  fi
  # Some CI terms are "dumb" and don't render control sequences well
  if [[ "${TERM:-}" == "dumb" ]]; then
    return 0
  fi

  # Terminal control helpers
  local have_tput=0 used_alt=0
  if command -v tput >/dev/null 2>&1; then
    have_tput=1
    # Enter alternate screen if supported (keeps main screen untouched)
    if tput smcup 2>/dev/null; then used_alt=1; fi
    # Hide cursor (no redirection; actually emit sequence)
    tput civis 2>/dev/null || true
  else
    # Fallback: ANSI sequences
    printf '\033[?1049h' && used_alt=1
    printf '\033[?25l'
  fi

  # Clear + home once, and a lightweight home-only command for subsequent frames
  local clear_cmd="printf '\033[2J\033[H'"
  local home_cmd="printf '\033[H'"
  if [[ $have_tput -eq 1 ]]; then
    clear_cmd="tput clear"
    home_cmd="tput cup 0 0"
  fi

  # Hold duration on last frame (seconds); default 1
  local hold_secs="${BZ_ASCII_HOLD:-3}"
  case "$hold_secs" in
    ''|*[!0-9]*) hold_secs=3 ;;
  esac

  # Choose frames directory based on terminal width unless overridden
  local frames_dir
  if [[ -n "${BZ_ASCII_DIR:-}" ]]; then
    frames_dir="${BZ_ASCII_DIR}"
  else
    # Determine column width
    local cols=""
    if [[ $have_tput -eq 1 ]]; then
      cols=$(tput cols 2>/dev/null || true)
    fi
    if [[ -z "${cols:-}" ]]; then
      # stty prints: rows cols
      if command -v stty >/dev/null 2>&1 && [[ -t 1 ]]; then
        cols=$(stty size 2>/dev/null | awk '{print $2}')
      fi
    fi
    if [[ -z "${cols:-}" ]]; then
      cols="${COLUMNS:-}"
    fi
    case "${cols:-}" in
      ''|*[!0-9]*) cols=80 ;;
    esac
    if (( cols >= 96 )); then
      frames_dir="$PWD/ascii/0xbenc_large"
    else
      frames_dir="$PWD/ascii/0xbenc_small"
    fi
  fi
  local use_files=0
  if compgen -G "$frames_dir/frame_*.txt" >/dev/null 2>&1; then
    use_files=1
  fi

  if [[ $use_files -eq 1 ]]; then
    # Discover highest frame index, assuming names frame_1.txt..frame_N.txt
    local max_frames=0 f base n
    for f in "$frames_dir"/frame_*.txt; do
      base=${f##*/}
      n=${base#frame_}
      n=${n%.txt}
      case "$n" in
        (*[!0-9]*) continue ;;
      esac
      if (( n > max_frames )); then max_frames=$n; fi
    done
    # Guard if somehow none parsed
    if (( max_frames <= 0 )); then
      use_files=0
    else
      local cycles=${BZ_ASCII_CYCLES:-1}
      local i r first=1
      for (( r=1; r<=cycles; r++ )); do
        for (( i=1; i<=max_frames; i++ )); do
          if (( first == 1 )); then eval "$clear_cmd" || true; first=0; else eval "$home_cmd" || true; fi
          if [[ -f "$frames_dir/frame_${i}.txt" ]]; then
            cat "$frames_dir/frame_${i}.txt"
          fi
          sleep 0.08
        done
      done
      # Hold on last frame before restoring
      sleep "$hold_secs"
      # Restore screen and cursor
      if [[ $used_alt -eq 1 ]]; then
        if [[ $have_tput -eq 1 ]]; then tput rmcup 2>/dev/null || true; else printf '\033[?1049l'; fi
      else
        eval "$clear_cmd" || true
      fi
      if [[ $have_tput -eq 1 ]]; then tput cnorm 2>/dev/null || true; else printf '\033[?25h'; fi
      return 0
    fi
  fi

  # Fallback: simple orbit if no frame files present
  ascii_frame() {
    case "$1" in
      0)
cat <<'EOF'
                               
               o               
                               
            0xbenc             
                               
                               
                               
EOF
        ;;
      1)
cat <<'EOF'
                               
                        o      
                               
            0xbenc             
                               
                               
                               
EOF
        ;;
      2)
cat <<'EOF'
                               
                               
                               
            0xbenc        o    
                               
                               
                               
EOF
        ;;
      3)
cat <<'EOF'
                               
                               
                               
            0xbenc             
                        o      
                               
                               
EOF
        ;;
      4)
cat <<'EOF'
                               
                               
                               
            0xbenc             
                               
               o               
                               
EOF
        ;;
      5)
cat <<'EOF'
                               
                               
                               
            0xbenc             
                               
        o                      
                               
EOF
        ;;
      6)
cat <<'EOF'
                               
                               
                               
        o   0xbenc             
                               
                               
                               
EOF
        ;;
      7)
cat <<'EOF'
                               
      o                        
                               
            0xbenc             
                               
                               
                               
EOF
        ;;
    esac
  }

  local i r first=1
  for r in 1 2; do
    for i in 0 1 2 3 4 5 6 7; do
      if (( first == 1 )); then eval "$clear_cmd" || true; first=0; else eval "$home_cmd" || true; fi
      ascii_frame "$i"
      sleep 0.08
    done
  done
  # Hold on last frame before restoring
  sleep "$hold_secs"
  # Restore screen and cursor
  if [[ $used_alt -eq 1 ]]; then
    if [[ $have_tput -eq 1 ]]; then tput rmcup 2>/dev/null || true; else printf '\033[?1049l'; fi
  else
    eval "$clear_cmd" || true
  fi
  if [[ $have_tput -eq 1 ]]; then tput cnorm 2>/dev/null || true; else printf '\033[?25h'; fi
}

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
    echo "Unsupported platform (not Debian-like Linux or macOS). No setup helpers available."
    exit 0
fi

# Prerequisites check (brew + gum + figlet)
require_prereqs_or_exit() {
  local missing=0 brew_missing=0 gum_missing=0 figlet_missing=0
  if ! command -v brew >/dev/null 2>&1; then
    echo "Error: Homebrew (brew) is not in PATH." >&2
    missing=1; brew_missing=1
  fi
  if ! command -v gum >/dev/null 2>&1; then
    echo "Error: gum is not installed." >&2
    missing=1; gum_missing=1
  fi
  if ! command -v figlet >/dev/null 2>&1; then
    echo "Error: figlet is not installed." >&2
    missing=1; figlet_missing=1
  fi
  if [[ $missing -eq 0 ]]; then
    return 0
  fi
  echo >&2
  echo "Install prerequisites, then re-run ./install.sh:" >&2
  if [[ $brew_missing -eq 1 ]]; then
    echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' >&2
  fi
  if [[ $gum_missing -eq 1 ]]; then
    echo '  brew install gum' >&2
  fi
  if [[ $figlet_missing -eq 1 ]]; then
    echo '  brew install figlet' >&2
  fi
  exit 1
}

# Prerequisites (brew + gum + figlet) are required for all modes
require_prereqs_or_exit

# Play rotating ASCII animation once before showing selector
play_ascii_once

# Read registry and build candidate list for this OS
scripts=()
scripts_has_deps=()

scripts_desc=()
while IFS=$'\t' read -r name oses has_deps desc; do
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
        # store description (optional 4th column)
        scripts_desc+=("${desc:-}")
    fi
done < "$REGISTRY_FILE"

# When not including experimental tools, filter to the stable set
if [[ $include_exp -eq 0 ]]; then
    stable_names=("uuid" "mfa" "forgit" "gpgobble" "killport" "ssherpa" "passage" "zapp" "zapper")
    filtered_scripts=()
    filtered_has_deps=()
    filtered_desc=()
    for i in "${!scripts[@]}"; do
        sname="${scripts[i]}"
        keep=0
        for st in "${stable_names[@]}"; do
            if [[ "$sname" == "$st" ]]; then
                keep=1
                break
            fi
        done
        if [[ $keep -eq 1 ]]; then
            filtered_scripts+=("$sname")
            filtered_has_deps+=("${scripts_has_deps[i]}")
            filtered_desc+=("${scripts_desc[i]}")
        fi
    done
    scripts=("${filtered_scripts[@]}")
    scripts_has_deps=("${filtered_has_deps[@]}")
    scripts_desc=("${filtered_desc[@]}")
fi

# Group zapp + zapper into a single selectable pair "zapps" (only for interactive mode)
if [[ $names_given -eq 0 ]]; then
    zapp_idx=-1
    zapper_idx=-1
    for i in "${!scripts[@]}"; do
        case "${scripts[i]}" in
            zapp)   zapp_idx=$i ;;
            zapper) zapper_idx=$i ;;
        esac
    done
    if [[ $zapp_idx -ge 0 || $zapper_idx -ge 0 ]]; then
        new_scripts=()
        new_has_deps=()
        new_desc=()
        for i in "${!scripts[@]}"; do
            name="${scripts[i]}"
            # Skip individual entries; we will add the grouped one below
            if [[ "$name" == "zapp" || "$name" == "zapper" ]]; then
                continue
            fi
            new_scripts+=("$name")
            new_has_deps+=("${scripts_has_deps[i]}")
            new_desc+=("${scripts_desc[i]}")
        done
        # Insert grouped entry once if either exists for this OS
        new_scripts+=("zapps")
        # has_deps is "yes" if either zapp or zapper had deps
        dep_flag="no"
        if [[ $zapp_idx -ge 0 && "${scripts_has_deps[$zapp_idx]}" == "yes" ]]; then dep_flag="yes"; fi
        if [[ $zapper_idx -ge 0 && "${scripts_has_deps[$zapper_idx]}" == "yes" ]]; then dep_flag="yes"; fi
        new_has_deps+=("$dep_flag")
        # Build a concise description for the grouped entry
        z_desc=""
        if [[ $zapp_idx -ge 0 && -n "${scripts_desc[$zapp_idx]}" ]]; then
          z_desc+="zapp — ${scripts_desc[$zapp_idx]}"
        fi
        if [[ $zapper_idx -ge 0 && -n "${scripts_desc[$zapper_idx]}" ]]; then
          [[ -n "$z_desc" ]] && z_desc+=$'\n'
          z_desc+="zapper — ${scripts_desc[$zapper_idx]}"
        fi
        if [[ -z "$z_desc" ]]; then
          z_desc="zapp + zapper helpers for managing apps in ~/zapps"
        fi
        new_desc+=("$z_desc")
        scripts=("${new_scripts[@]}")
        scripts_has_deps=("${new_has_deps[@]}")
        scripts_desc=("${new_desc[@]}")
    fi
fi

if [[ ${#scripts[@]} -eq 0 ]]; then
    echo "No installable scripts defined for OS '$OS_TYPE' in $REGISTRY_FILE"
    exit 0
fi

# Ensure the uninstaller is executable for convenience
chmod +x "$PWD/uninstall.sh" 2>/dev/null || true

# Build selection (gum only)
selected_names=()
if [[ $names_given -eq 1 ]]; then
    # Bypass interactive selection; trust provided names
    include_exp=1
    IFS=',' read -r -a selected_names <<< "$names_csv"
elif [[ $select_all -eq 1 ]]; then
    echo "Selecting all available scripts for $OS_TYPE."
    selected_names=("${scripts[@]}")
else
    require_prereqs_or_exit

    gum_labels=()
    gum_labels+=("all — All (everything below)")
    for i in "${!scripts[@]}"; do
        _name="${scripts[i]}"
        _label="$_name"
        if [[ "$_name" == "zapps" ]]; then
            _label="zapps (zapp + zapper)"
        fi
        _summary="${scripts_desc[i]:-}"
        _summary=${_summary//$'\r'/ }
        _summary=${_summary//$'\n'/ }
        if [[ -n "$_summary" ]]; then
            gum_labels+=("$_label — $_summary")
        else
            gum_labels+=("$_label")
        fi
    done
    selected_names=()
    while IFS= read -r __sel_line; do
        [[ -z "${__sel_line:-}" ]] && continue
        __name="${__sel_line%%[[:space:]]*}"
        selected_names+=("$__name")
    done < <(printf '%s\n' "${gum_labels[@]}" | gum choose --no-limit --header "Select tools to install")
    clear || true
fi

echo "Installing selected items..."
selected_scripts=()

# If special "all" was selected, expand to the full list that was shown
for __sel in "${selected_names[@]:-}"; do
    if [[ "$__sel" == "all" ]]; then
        selected_names=("${scripts[@]}")
        break
    fi
done

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

run_setup_script() {
    local name="$1"
    local os="$2"
    local path="$SETUP_DIR/$os/$name.sh"
    # Run setup script if file exists; set executable bit if needed
    if [[ -f "$path" ]]; then
        chmod +x "$path" || true
        "$path"
        return 0
    fi
    echo "Warning: no setup script for '$name' (expected $path)." >&2
    return 1
}

# Process selected scripts
for i in "${!scripts[@]}"; do
    script_name="${scripts[i]}"
    for sel in "${selected_names[@]:-}"; do
        if [[ "$sel" == "$script_name" ]]; then
            if [[ "$script_name" == "zapps" ]]; then
                # Expand to zapp + zapper
                for sub in zapp zapper; do
                    if [[ -f "$SCRIPTS_DIR/$sub.sh" ]]; then
                        selected_scripts+=("$sub")
                        chmod +x "$SCRIPTS_DIR/$sub.sh"
                        # If grouped has deps, attempt setup script for each sub
                        if [[ "${scripts_has_deps[i]}" == "yes" ]]; then
                            run_setup_script "$sub" "$OS_TYPE" || true
                        else
                            echo "No setup script needed for '$sub'."
                        fi
                    fi
                done
            else
                selected_scripts+=("$script_name")
                chmod +x "$SCRIPTS_DIR/$script_name.sh"
                if [[ "${scripts_has_deps[i]}" == "yes" ]]; then
                    run_setup_script "$script_name" "$OS_TYPE" || true
                else
                    echo "No setup script needed for '$script_name'."
                fi
            fi
            break
        fi
    done
done

# Always install bash-zoo meta CLI (not part of selection)


# Determine robust install target directory
resolve_target_dir() {
    # Linux prefers ~/.local/bin; macOS prefers ~/bin
    if [[ "$OS_TYPE" == "debian" ]]; then
        printf '%s\n' "$HOME/.local/bin"
    else
        printf '%s\n' "$HOME/bin"
    fi
}

resolve_share_root() {
    if [[ "$OS_TYPE" == "macos" ]]; then
        printf '%s\n' "$HOME/Library/Application Support/bash-zoo"
    else
        printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/bash-zoo"
    fi
}

 

ensure_dir() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        return 0
    fi
    mkdir -p "$dir" 2>/dev/null || return 1
}

is_writable_dir() {
    local dir="$1"
    [[ -d "$dir" && -w "$dir" ]]
}

path_has_dir() {
    local dir="$1"
    local p
    IFS=":" read -r -a _parts <<< "${PATH:-}"
    for p in "${_parts[@]}"; do
        if [[ "$p" == "$dir" ]]; then
            return 0
        fi
    done
    return 1
}

add_path_line() {
    local rc_file="$1" dir="$2"
    local line
    line="export PATH=\"$dir:\$PATH\"  # bash-zoo"
    touch "$rc_file"
    if grep -qE "(^|:)${dir//\//\/}(:|\")" <<<":$PATH:"; then
        return 0
    fi
    if ! grep -q "bash-zoo" "$rc_file" 2>/dev/null; then
        echo "$line" >> "$rc_file"
        return 0
    fi
    # If a previous bash-zoo PATH line exists but without this dir, append a fresh one
    echo "$line" >> "$rc_file"
}

 

install_file() {
    local src="$1" dst_dir="$2" name="$3"
    local dst="$dst_dir/$name"
    cp -f "$src" "$dst" 2>/dev/null || return 1
    chmod +x "$dst" 2>/dev/null || true
}

install_bash_zoo() {
    local dst_dir="$1"
    local dst="$dst_dir/bash-zoo"
    local src="$PWD/$SCRIPTS_DIR/bash-zoo.sh"
    local version repo_url
    if [[ -f "$PWD/VERSION" ]]; then
        version=$(cat "$PWD/VERSION")
    else
        version="0.0.0"
    fi
    # Best-effort repo URL (may be empty when not a git repo)
    if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
        repo_url=$(git remote get-url origin 2>/dev/null || echo "")
    else
        repo_url=""
    fi
    # Fallback to canonical default when empty
    if [[ -z "$repo_url" ]]; then
        repo_url="https://github.com/0xbenc/bash-zoo.git"
    fi
    mkdir -p "$dst_dir"
    # Embed placeholders @VERSION@ and @REPO_URL@
    if sed --version >/dev/null 2>&1; then
        sed -e "s/@VERSION@/${version//\//\/}/g" -e "s|@REPO_URL@|${repo_url//\//\/}|g" "$src" > "$dst"
    else
        # macOS/BSD sed
        sed -e "s/@VERSION@/${version//\//\/}/g" -e "s|@REPO_URL@|${repo_url//\//\/}|g" "$src" > "$dst"
    fi
    chmod +x "$dst" 2>/dev/null || true
}

write_installed_metadata() {
    # Args: names as positional parameters
    local share_root meta_file version commit repo_url
    share_root=$(resolve_share_root)
    meta_file="$share_root/installed.json"
    mkdir -p "$share_root"
    if [[ -f "$PWD/VERSION" ]]; then
        version=$(cat "$PWD/VERSION")
    else
        version="0.0.0"
    fi
    if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
        commit=$(git rev-parse --verify HEAD 2>/dev/null || echo "unknown")
        repo_url=$(git remote get-url origin 2>/dev/null || echo "")
    else
        commit="unknown"
        repo_url=""
    fi
    # Build JSON array of names
    local out="[" first=1 n
    for n in "$@"; do
        # Skip the meta CLI itself
        if [[ "$n" == "bash-zoo" ]]; then
            continue
        fi
        if [[ $first -eq 1 ]]; then
            out+="\"$n\""; first=0
        else
            out+=",\"$n\""
        fi
    done
    out+="]"
    printf '{"version":"%s","commit":"%s","repo_url":"%s","installed":%s}\n' "$version" "${commit:-unknown}" "$repo_url" "$out" > "$meta_file"
    echo "Wrote metadata: $meta_file"
}

 

# Perform installation: prefer bin dir, fallback to aliases per-script
USER_SHELL=$(basename "${SHELL:-}")
RC_FILE=""
case "$USER_SHELL" in
    bash) RC_FILE="$HOME/.bashrc" ;;
    zsh)  RC_FILE="$HOME/.zshrc" ;;
    *)    RC_FILE="$HOME/.bashrc" ;;
esac

target_dir=$(resolve_target_dir)
if [[ -n "${BZ_SYMLINK:-}" ]]; then
    echo "BZ_SYMLINK is no longer supported; installing launchers as copies." >&2
fi

installed_to_bin=()
installed_as_alias=()

    if ensure_dir "$target_dir" && is_writable_dir "$target_dir"; then
        # Install selected tools (if any)
        for script in "${selected_scripts[@]:-}"; do
        src="$PWD/$SCRIPTS_DIR/$script.sh"
        if install_file "$src" "$target_dir" "$script"; then
            installed_to_bin+=("$script")
        else
            add_or_update_alias "$script" "$src" "$RC_FILE"
            installed_as_alias+=("$script")
        fi
    done

    # Always install meta CLI
    if install_bash_zoo "$target_dir"; then
        installed_to_bin+=("bash-zoo")
    else
        echo "Warning: failed to install bash-zoo CLI to $target_dir" >&2
    fi

    #
else
    echo "Note: Unable to write to $target_dir; falling back to aliases in $RC_FILE"
    for script in "${selected_scripts[@]:-}"; do
        add_or_update_alias "$script" "$PWD/$SCRIPTS_DIR/$script.sh" "$RC_FILE"
        installed_as_alias+=("$script")
    done
    # Try to install bash-zoo even if target_dir initially unwritable (mkdir -p might fix)
    if ensure_dir "$target_dir" && is_writable_dir "$target_dir"; then
        if install_bash_zoo "$target_dir"; then
            installed_to_bin+=("bash-zoo")
        fi
    else
        echo "Warning: could not install bash-zoo binary; alias fallback would require repo — skipped" >&2
    fi

    #
fi

# Ensure PATH if we installed any into bin
if [[ ${#installed_to_bin[@]} -gt 0 ]]; then
    if path_has_dir "$target_dir"; then
        echo "PATH already includes $target_dir"
    else
        echo "Adding $target_dir to PATH in $RC_FILE ..."
        add_path_line "$RC_FILE" "$target_dir"
        echo "Added."
    fi
fi

 

# Summaries
if [[ ${#installed_to_bin[@]} -gt 0 ]]; then
    echo "Installed to $target_dir: ${installed_to_bin[*]}"
fi
if [[ ${#installed_as_alias[@]} -gt 0 ]]; then
    echo "Configured aliases in $RC_FILE: ${installed_as_alias[*]}"
fi

# Write metadata of installed tools (bins + aliases)
installed_all=("${installed_to_bin[@]:-}" "${installed_as_alias[@]:-}")
write_installed_metadata "${installed_all[@]:-}"

echo "Installation complete!"
echo "Open a new terminal or run:"
echo "  exec \"$SHELL\" -l"
echo "to reload your shell configuration."
