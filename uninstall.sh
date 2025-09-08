#!/bin/bash

set -euo pipefail

# Uninstall aliases added by the Bash Zoo wizard.
# - Scans ~/.bashrc and ~/.zshrc for alias lines pointing to scripts/*.sh
# - Lets you interactively select which to remove
# - Works with enquirer (Node) if available; falls back to a minimal TUI

SCRIPTS_DIR="$PWD/scripts"

# Candidate RC files to scan (wizard writes to one of these)
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

if [[ ${#alias_names[@]} -eq 0 ]]; then
  echo "No Bash Zoo aliases found in ~/.bashrc or ~/.zshrc."
  exit 0
fi

###############################################################
# Build grouped selection list (zapp+zapper appear as one item)
###############################################################

# Prepare item lists and a parallel list of base indices per item
item_ids=()
item_labels=()
item_idxlists=()  # space-separated base indices making up the item

visited=()
for _ in "${alias_names[@]}"; do visited+=(0); done

# Helper to push an item
push_item() {
  item_ids+=("$1")
  item_labels+=("$2")
  item_idxlists+=("$3")
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
  push_item "grp-zapps" "zapps (zapp + zapper)" "$list"
  for idx in ${zapps_idxs[*]}; do visited[$idx]=1; done
fi

# Add remaining individual items
for i in "${!alias_names[@]}"; do
  if [[ ${visited[$i]} -eq 1 ]]; then continue; fi
  push_item "i-$i" "${alias_names[$i]} → scripts/${script_names[$i]}.sh (${rc_display[$i]})" "$i"
done

# Build selection payload
payload='{ "title": "Select aliases to remove", "choices": ['
for j in "${!item_ids[@]}"; do
  id="${item_ids[$j]}"
  label="${item_labels[$j]}"
  esc_label=$(printf '%s' "$label" | sed 's/"/\\"/g')
  payload+="{\"name\":\"$id\",\"message\":\"$esc_label\"},"
done
payload=${payload%,}
payload+='] }'

selected_ids=()
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

if [[ ${#selected_ids[@]} -eq 0 ]]; then
  echo "No aliases selected. Exiting."
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
      for idx in ${item_idxlists[$j]}; do
        rc_file="${rc_files[$idx]}"
        name="${alias_names[$idx]}"
        script="${script_names[$idx]}"
        delete_alias_line "$rc_file" "$name" "$script"
        ((removed++))
      done
      break
    fi
  done
done

echo "Removed $removed alias(es). Open a new terminal or run:"
echo "  exec \"$SHELL\" -l"
echo "to reload your shell configuration."
