#!/bin/bash

set -euo pipefail

# Uninstall aliases added by the Bash Zoo installer.
# - Removes installed binaries from stable bin dirs and/or aliases.
# - Scans ~/.bashrc and ~/.zshrc for alias lines pointing to scripts/*.sh
# - Lets you interactively select which to remove
# - Works with enquirer (Node) if available; falls back to a minimal TUI

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

ensure_enquirer() {
  if ! command -v node >/dev/null 2>&1; then
    return 1
  fi
  if NODE_PATH="$PWD/.interactive/node_modules${NODE_PATH:+:$NODE_PATH}" \
     node -e "require('enquirer')" >/dev/null 2>&1; then
    return 0
  fi
  mkdir -p "$PWD/.interactive"
  if [[ ! -f "$PWD/.interactive/package.json" ]]; then
    printf '{"name":"bash-zoo-interactive","private":true}\n' > "$PWD/.interactive/package.json"
  fi

  local PM=""
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

  echo "Preparing selector (installing enquirer)..."
  case "$PM" in
    npm)  ( cd "$PWD/.interactive" && npm install --silent enquirer@^2 ) || return 1 ;;
    pnpm) ( cd "$PWD/.interactive" && pnpm add -s enquirer@^2 ) || return 1 ;;
    yarn) ( cd "$PWD/.interactive" && yarn add -s enquirer@^2 ) || return 1 ;;
    bun)  ( cd "$PWD/.interactive" && bun add -y enquirer@^2 ) || return 1 ;;
  esac

  if NODE_PATH="$PWD/.interactive/node_modules${NODE_PATH:+:$NODE_PATH}" \
     node -e "require('enquirer')" >/dev/null 2>&1; then
    return 0
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

visited=()

# Helper to push an item
push_item() {
  item_ids+=("$1")
  item_labels+=("$2")
  item_kinds+=("$3")
  item_payloads+=("$4")
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
  push_item "grp-zapps-alias" "Aliases: zapps (zapp + zapper)" "alias" "$list"
  for idx in ${zapps_idxs[*]}; do visited[$idx]=1; done
fi

# Add remaining individual items
for i in "${!alias_names[@]}"; do
  if [[ ${visited[$i]:-0} -eq 1 ]]; then continue; fi
  push_item "alias-$i" "Alias: ${alias_names[$i]} → scripts/${script_names[$i]}.sh (${rc_display[$i]})" "alias" "$i"
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
zapps_bin_labels=()
for i in "${!bin_scripts[@]}"; do
  sname="${bin_scripts[$i]}"
  if [[ "$sname" == "zapp" || "$sname" == "zapper" ]]; then
    zapps_bin_paths+=("${bin_paths[$i]}")
  fi
done
if [[ ${#zapps_bin_paths[@]} -gt 0 ]]; then
  # Compose a label showing dirs succinctly
  disp="Binaries: zapps (zapp + zapper)"
  push_item "grp-zapps-bin" "$disp" "bin" "${zapps_bin_paths[*]}"
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
  push_item "bin-$sname" "Binary: $sname at $pdir" "bin" "$bpath"
done

if [[ ${#item_ids[@]} -eq 0 ]]; then
  echo "No Bash Zoo aliases or installed binaries found."
  exit 0
fi

selected_ids=()
if [[ $select_all -eq 1 ]]; then
  echo "Selecting all installed items for removal."
  selected_ids=("${item_ids[@]}")
else
  # Build selection payload
  payload='{ "title": "Select items to remove", "choices": ['
  for j in "${!item_ids[@]}"; do
    id="${item_ids[$j]}"
    label="${item_labels[$j]}"
    esc_label=$(printf '%s' "$label" | sed 's/"/\\"/g')
    payload+="{\"name\":\"$id\",\"message\":\"$esc_label\"},"
  done
  payload=${payload%,}
  payload+='] }'

  if ensure_enquirer; then
    while IFS= read -r __sel; do
      [[ -z "${__sel:-}" ]] && continue
      selected_ids+=("$__sel")
    done < <(BZ_PAYLOAD="$payload" NODE_PATH="$PWD/.interactive/node_modules${NODE_PATH:+:$NODE_PATH}" node "bin/select.js")
  else
    # Fallback minimal TUI (hjkl)
    current=0
    selected=()
    for _ in "${item_ids[@]}"; do selected+=(0); done
    draw_menu() {
      clear
      echo "Use 'J' and 'K' to move, 'H' to toggle, 'L' to confirm."
      for j in "${!item_ids[@]}"; do
        if [[ $j -eq $current ]]; then echo -ne "\e[1;32m> "; else echo -ne "  "; fi
        if [[ ${selected[j]} -eq 1 ]]; then echo -ne "[✔ ] "; else echo -ne "[ ] "; fi
        echo -e "${item_labels[$j]}\e[0m"
      done
    }
    while true; do
      draw_menu
      read -rsn1 key
      case "$key" in
        "k") ((current = (current - 1 + ${#item_ids[@]}) % ${#item_ids[@]})) ;;
        "j") ((current = (current + 1) % ${#item_ids[@]})) ;;
        "h") selected[current]=$((1 - selected[current])) ;;
        "l") break ;;
      esac
    done
    for j in "${!selected[@]}"; do
      if [[ ${selected[j]} -eq 1 ]]; then selected_ids+=("${item_ids[$j]}"); fi
    done
  fi
fi

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
          ((removed++))
        done
      else
        for f in $payload; do
          if [[ -e "$f" ]]; then rm -f "$f" && ((removed++)); fi
        done
      fi
      break
    fi
  done
done

# Clean up PATH lines we added (tagged with 'bash-zoo') if no more zoo bins remain
RC_CAND=("$HOME/.bashrc" "$HOME/.zshrc")
cleanup_path_lines=1
for d in "${BIN_DIRS[@]}"; do
  any_left=0
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
