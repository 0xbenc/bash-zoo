#!/bin/bash

set -euo pipefail

# Uninstall aliases and binaries installed by Bash Zoo.
# - Removes installed binaries from stable bin dirs and/or aliases.
# - Scans ~/.bashrc and ~/.zshrc for alias lines pointing to scripts/*.sh
# - Uses gum for the interactive picker; ensures Homebrew on Linux (system prefix with sudo, otherwise ~/.linuxbrew).

usage() {
  echo "Usage: $0 [--all]" >&2
}

select_all=0
if [[ $# -gt 0 ]]; then
  for arg in "$@"; do
    case "$arg" in
      --all|-a|all)
        select_all=1
        ;;
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

SCRIPTS_DIR="$PWD/scripts"
BIN_DIRS=("$HOME/.local/bin" "$HOME/bin")

# Candidate RC files to scan (installer writes to one of these)
RC_CANDIDATES=("$HOME/.bashrc" "$HOME/.zshrc")

# OS detection (macos, debian, other)
OS_TYPE="other"
UNAME_S=$(uname -s)
if [[ "$UNAME_S" == "Darwin" ]]; then
  OS_TYPE="macos"
elif [[ "$UNAME_S" == "Linux" ]]; then
  if command -v apt >/dev/null 2>&1 || command -v apt-get >/dev/null 2>&1; then
    OS_TYPE="debian"
  fi
fi

# Ensure gum exists; on Linux, ensure Homebrew first with a resilient bootstrap
ensure_gum() {
  if command -v gum >/dev/null 2>&1; then
    return 0
  fi
  if [[ "$OS_TYPE" == "macos" ]]; then
    if command -v brew >/dev/null 2>&1; then
      echo "Preparing selector (installing gum via Homebrew)..."
      brew list --versions gum >/dev/null 2>&1 || brew install gum >/dev/null 2>&1 || true
      command -v gum >/dev/null 2>&1 && return 0
    fi
    return 1
  fi
  if [[ "$OS_TYPE" == "debian" ]]; then
    find_brew_bin() {
      if command -v brew >/dev/null 2>&1; then
        command -v brew
        return 0
      fi
      for prefix in /home/linuxbrew/.linuxbrew "$HOME/.linuxbrew"; do
        if [[ -x "$prefix/bin/brew" ]]; then
          echo "$prefix/bin/brew"
          return 0
        fi
      done
      return 1
    }
    can_sudo_noninteractive() {
      if ! command -v sudo >/dev/null 2>&1; then return 1; fi
      sudo -n true >/dev/null 2>&1
    }
    install_homebrew_linux_system() {
      local tmp_dir installer
      tmp_dir=$(mktemp -d)
      installer="$tmp_dir/install-homebrew.sh"
      if curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$installer"; then
        chmod +x "$installer" || true
        NONINTERACTIVE=1 /bin/bash "$installer" || true
      fi
      rm -rf "$tmp_dir" 2>/dev/null || true
      find_brew_bin >/dev/null 2>&1
    }
    install_homebrew_linux_user() {
      local prefix="$HOME/.linuxbrew"
      mkdir -p "$prefix" 2>/dev/null || true
      if [[ ! -x "$prefix/bin/brew" ]]; then
        if command -v git >/dev/null 2>&1; then
          if [[ ! -d "$prefix/Homebrew/.git" ]]; then
            git clone --depth=1 https://github.com/Homebrew/brew "$prefix/Homebrew" >/dev/null 2>&1 || true
          fi
        elif command -v curl >/dev/null 2>&1 && command -v tar >/dev/null 2>&1; then
          mkdir -p "$prefix/Homebrew" 2>/dev/null || true
          curl -fsSL https://github.com/Homebrew/brew/tarball/HEAD | tar -xz -C "$prefix/Homebrew" --strip-components=1 >/dev/null 2>&1 || true
        fi
        mkdir -p "$prefix/bin" 2>/dev/null || true
        ln -sfn "$prefix/Homebrew/bin/brew" "$prefix/bin/brew" 2>/dev/null || true
      fi
      find_brew_bin >/dev/null 2>&1
    }
    if ! find_brew_bin >/dev/null 2>&1; then
      if can_sudo_noninteractive; then
        echo "Installing Homebrew for Linux (system prefix)..."
        install_homebrew_linux_system || true
      fi
    fi
    if ! find_brew_bin >/dev/null 2>&1; then
      echo "Installing Homebrew for Linux (user prefix at ~/.linuxbrew)..."
      install_homebrew_linux_user || true
    fi
    local brew_bin=""
    if brew_bin=$(find_brew_bin); then
      eval "$($brew_bin shellenv)"
      echo "Preparing selector (installing gum via Homebrew for Linux)..."
      "$brew_bin" list --versions gum >/dev/null 2>&1 || "$brew_bin" install gum >/dev/null 2>&1 || true
      command -v gum >/dev/null 2>&1 && return 0
    fi
    return 1
  fi
  return 1
}

# Collect uninstallable aliases from RC files
rc_files=()
alias_names=()
script_names=()
rc_display=()

for rc in "${RC_CANDIDATES[@]}"; do
  [[ -f "$rc" ]] || continue
  # Read each line; detect aliases that point to .../scripts/<name>.sh
  while IFS= read -r line; do
    # Basic parse: alias name="/abs/path/.../scripts/foo.sh"
    if [[ "$line" =~ ^alias[[:space:]]+([a-zA-Z0-9_-]+)=[\"\']([^\"\']+)[\"\'] ]]; then
      name="${BASH_REMATCH[1]}"
      target="${BASH_REMATCH[2]}"
      # Extract the script basename if path ends with scripts/<name>.sh
      if [[ "$target" =~ scripts/([a-zA-Z0-9_-]+)\.sh$ ]]; then
        script="${BASH_REMATCH[1]}"
        rc_files+=("$rc")
        alias_names+=("$name")
        script_names+=("$script")
        # Nice, compact rc label
        case "$rc" in
          "$HOME/.bashrc") rc_display+=(".bashrc") ;;
          "$HOME/.zshrc")  rc_display+=(".zshrc")  ;;
          *)                rc_display+=("$(basename "$rc")") ;;
        esac
      fi
    fi
  done < "$rc"
done

###############################################################
# Build grouped selection list (zapp+zapper appear as one item)
###############################################################

###############################################
# Build selection items (aliases and bin files)
###############################################

# Prepare item lists. Parallel arrays to track type and payload
item_ids=()
item_labels=()
item_kinds=()     # alias | bin
item_payloads=()  # alias: space-separated base indices; bin: space-separated fullpaths
item_summaries=() # short names printed in UI summary

visited=()

# Helper to push an item
push_item() {
  item_ids+=("$1")
  item_labels+=("$2")
  item_kinds+=("$3")
  item_payloads+=("$4")
  local summary="${5-}"
  if [[ -z "$summary" ]]; then
    # Derive a minimal name from the label
    local derived="$2"
    derived=${derived#Aliases: }
    derived=${derived#Alias: }
    derived=${derived#Binaries: }
    derived=${derived#Binary: }
    derived=${derived%% at *}
    derived=${derived%% → *}
    summary="$derived"
  fi
  item_summaries+=("$summary")
}

# Find all indices for zapp/zapper
zapps_idxs=()
for i in "${!alias_names[@]}"; do
  sname="${script_names[$i]}"
  if [[ "$sname" == "zapp" || "$sname" == "zapper" ]]; then
    zapps_idxs+=("$i")
  fi
done

if [[ ${#zapps_idxs[@]} -gt 0 ]]; then
  # Create one grouped entry for whatever exists among the pair
  list="${zapps_idxs[*]}"
  # Build a precise label with only present names
  present_names=()
  for idx in ${zapps_idxs[*]}; do
    sname_i="${script_names[$idx]}"
    # Deduplicate while preserving order (zapp/zapper appear few times)
    already=0
    for n in "${present_names[@]:-}"; do [[ "$n" == "$sname_i" ]] && already=1 && break; done
    if [[ $already -eq 0 ]]; then present_names+=("$sname_i"); fi
  done
  label_suffix=""
  if [[ ${#present_names[@]} -eq 1 ]]; then
    label_suffix="${present_names[0]}"
  else
    # Join with ' + '
    join=""
    for n in "${present_names[@]}"; do
      if [[ -z "$join" ]]; then join="$n"; else join="$join + $n"; fi
    done
    label_suffix="$join"
  fi
  push_item "grp-zapps-alias" "Aliases: $label_suffix" "alias" "$list" "$label_suffix"
  for idx in ${zapps_idxs[*]}; do visited[$idx]=1; done
fi

# Add remaining individual items
for i in "${!alias_names[@]}"; do
  if [[ ${visited[$i]:-0} -eq 1 ]]; then continue; fi
  push_item "alias-$i" "Alias: ${alias_names[$i]} → scripts/${script_names[$i]}.sh (${rc_display[$i]})" "alias" "$i" "${alias_names[$i]}"
done

# Collect installed binaries in bin dirs
bin_paths=()
bin_scripts=()
bin_dirs_for_item=()
for d in "${BIN_DIRS[@]}"; do
  [[ -d "$d" ]] || continue
  for sfile in "$SCRIPTS_DIR"/*.sh; do
    [[ -f "$sfile" ]] || continue
    sname=$(basename "$sfile" .sh)
    target="$d/$sname"
    if [[ -e "$target" ]]; then
      bin_paths+=("$target")
      bin_scripts+=("$sname")
      bin_dirs_for_item+=("$d")
    fi
  done
done

# Group zapps binaries into one item
zapps_bin_paths=()
zapps_bin_names=()
for i in "${!bin_scripts[@]}"; do
  sname="${bin_scripts[$i]}"
  if [[ "$sname" == "zapp" || "$sname" == "zapper" ]]; then
    zapps_bin_paths+=("${bin_paths[$i]}")
    zapps_bin_names+=("$sname")
  fi
done
if [[ ${#zapps_bin_paths[@]} -gt 0 ]]; then
  # Compose a label with only present names
  present_bin_names=()
  for nm in "${zapps_bin_names[@]}"; do
    already=0
    for n in "${present_bin_names[@]:-}"; do [[ "$n" == "$nm" ]] && already=1 && break; done
    if [[ $already -eq 0 ]]; then present_bin_names+=("$nm"); fi
  done
  if [[ ${#present_bin_names[@]} -eq 1 ]]; then
    disp="Binaries: ${present_bin_names[0]}"
    summary_bin="${present_bin_names[0]}"
  else
    join=""
    for n in "${present_bin_names[@]}"; do
      if [[ -z "$join" ]]; then join="$n"; else join="$join + $n"; fi
    done
    disp="Binaries: $join"
    summary_bin="$join"
  fi
  push_item "grp-zapps-bin" "$disp" "bin" "${zapps_bin_paths[*]}" "$summary_bin"
fi

# Add remaining individual binaries
for i in "${!bin_paths[@]}"; do
  sname="${bin_scripts[$i]}"
  if [[ "$sname" == "zapp" || "$sname" == "zapper" ]]; then
    continue
  fi
  bpath="${bin_paths[$i]}"
  bdir="${bin_dirs_for_item[$i]}"
  # Pretty display dir, collapse $HOME to ~
  pdir="$bdir"
  case "$pdir" in
    "$HOME"/*) pdir="~${pdir#$HOME}" ;;
  esac
  push_item "bin-$sname" "Binary: $sname at $pdir" "bin" "$bpath" "$sname"
done

if [[ ${#item_ids[@]} -eq 0 ]]; then
  echo "No Bash Zoo aliases or installed binaries found."
fi

selected_ids=()
if [[ $select_all -eq 1 ]]; then
  echo "Selecting all installed items for removal."
  selected_ids=("${item_ids[@]}")
else
  if ! ensure_gum; then
    echo "Error: gum is required for interactive selection and could not be installed automatically." >&2
    echo "- Use --all to remove everything except the meta CLI without prompts." >&2
    exit 1
  fi
  gum_labels=()
  gum_labels+=("meta-cli — Remove meta CLI (bash-zoo)")
  gum_labels+=("all — All (aliases + binaries)")
  for j in "${!item_ids[@]}"; do
    gum_labels+=("${item_ids[$j]} — ${item_labels[$j]}")
  done
  while IFS= read -r __sel; do
    [[ -z "${__sel:-}" ]] && continue
    selected_ids+=("${__sel%%[[:space:]]*}")
  done < <(printf '%s\n' "${gum_labels[@]}" | gum choose --no-limit --header "Select items to remove")
  clear || true
fi

# Track whether meta CLI should be removed (kept separate from "all")
remove_meta_cli=0
for __sel in "${selected_ids[@]:-}"; do
  if [[ "$__sel" == "meta-cli" ]]; then
    remove_meta_cli=1
    break
  fi
done

# If special "all" was selected via the UI, expand to full set (meta excluded)
for __sel in "${selected_ids[@]:-}"; do
  if [[ "$__sel" == "all" ]]; then
    selected_ids=("${item_ids[@]}")
    break
  fi
done

if [[ ${#selected_ids[@]} -eq 0 ]]; then
  echo "No items selected. Exiting."
  exit 0
fi

# Helper: portable sed -i delete
delete_alias_line() {
  local rc_file="$1" name="$2" script="$3"
  local pattern
  # Match: alias NAME=".../scripts/NAME.sh" (be tolerant about path)
  pattern="^alias[[:space:]]+${name}=[\"\'][^\"\']*scripts/${script}\\.sh[\"\']"
  # Escape forward slashes for sed address delimiter
  local esc
  esc=$(printf '%s' "$pattern" | sed 's/\//\\\//g')
  if sed --version >/dev/null 2>&1; then
    sed -i -E "/$esc/d" "$rc_file"
  else
    # macOS/BSD sed
    sed -i '' -E "/$esc/d" "$rc_file"
  fi
}

removed=0
for sel in "${selected_ids[@]}"; do
  [[ "$sel" == "meta-cli" ]] && continue
  # Find the item index by id
  for j in "${!item_ids[@]}"; do
    if [[ "${item_ids[$j]}" == "$sel" ]]; then
      kind="${item_kinds[$j]}"
      payload="${item_payloads[$j]}"
      if [[ "$kind" == "alias" ]]; then
        for idx in $payload; do
          rc_file="${rc_files[$idx]}"
          name="${alias_names[$idx]}"
          script="${script_names[$idx]}"
          delete_alias_line "$rc_file" "$name" "$script"
          ((removed+=1))
        done
      else
        for f in $payload; do
          if [[ -e "$f" ]]; then
            rm -f "$f"
            ((removed+=1))
          fi
        done
      fi
      break
    fi
  done
done

# Optionally remove meta CLI from user bin dirs
if [[ $remove_meta_cli -eq 1 ]]; then
  for d in "${BIN_DIRS[@]}"; do
    if [[ -e "$d/bash-zoo" ]]; then
      rm -f "$d/bash-zoo"
      ((removed+=1))
    fi
  done
fi

# Clean up PATH lines we added (tagged with 'bash-zoo') if no more zoo bins remain
RC_CAND=("$HOME/.bashrc" "$HOME/.zshrc")
cleanup_path_lines=1
for d in "${BIN_DIRS[@]}"; do
  any_left=0
  # Keep PATH if meta CLI remains
  if [[ -e "$d/bash-zoo" ]]; then any_left=1; fi
  for sfile in "$SCRIPTS_DIR"/*.sh; do
    [[ -f "$sfile" ]] || continue
    sname=$(basename "$sfile" .sh)
    if [[ -e "$d/$sname" ]]; then any_left=1; break; fi
  done
  if [[ $any_left -eq 1 ]]; then
    cleanup_path_lines=0
    break
  fi
done
if [[ $cleanup_path_lines -eq 1 ]]; then
  for rc in "${RC_CAND[@]}"; do
    [[ -f "$rc" ]] || continue
    if sed --version >/dev/null 2>&1; then
      sed -i -E "/# bash-zoo$/d" "$rc"
    else
      sed -i '' -E "/# bash-zoo$/d" "$rc"
    fi
  done
fi

echo "Removed $removed item(s). Open a new terminal or run:"
echo "  exec \"$SHELL\" -l"
echo "to reload your shell configuration."
