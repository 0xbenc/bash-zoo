#!/bin/bash

set -euo pipefail

# Meta CLI for Bash Zoo
# - Always installed into user bin by install.sh
# - Portable: avoids Bash 4-only features

# Version is embedded at install time by install.sh
BASH_ZOO_VERSION="@VERSION@"

print_usage() {
  cat <<'EOF'
bash-zoo — meta CLI

Usage:
  bash-zoo help
  bash-zoo version
  bash-zoo uninstall [--all]
  bash-zoo update passwords

Commands:
  help                 Show this help.
  version              Print the installed bash-zoo version.
  uninstall [--all]    Remove installed tools and aliases. Use --all to skip prompts.
  update passwords     Pull latest for each subfolder in ~/.password-store.
EOF
}

echo_err() { printf '%s\n' "$*" >&2; }

resolve_os_type() {
  local u
  u=$(uname -s)
  if [[ "$u" == "Darwin" ]]; then
    printf '%s\n' macos
  elif [[ "$u" == "Linux" ]]; then
    if command -v apt >/dev/null 2>&1 || command -v apt-get >/dev/null 2>&1; then
      printf '%s\n' debian
    else
      printf '%s\n' linux
    fi
  else
    printf '%s\n' other
  fi
}

resolve_target_dir() {
  local os
  os=$(resolve_os_type)
  if [[ "$os" == "debian" ]]; then
    printf '%s\n' "$HOME/.local/bin"
  else
    printf '%s\n' "$HOME/bin"
  fi
}

resolve_share_root() {
  local os
  os=$(resolve_os_type)
  if [[ "$os" == "macos" ]]; then
    printf '%s\n' "$HOME/Library/Application Support/bash-zoo"
  else
    printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/bash-zoo"
  fi
}

ensure_dir() {
  local d="$1"
  [[ -d "$d" ]] || mkdir -p "$d"
}

ensure_enquirer() {
  # Install/resolve enquirer into a vendor dir in the share root
  if ! command -v node >/dev/null 2>&1; then
    return 1
  fi
  local share_root vendor
  share_root=$(resolve_share_root)
  vendor="$share_root/interactive"
  mkdir -p "$vendor"
  if NODE_PATH="$vendor/node_modules${NODE_PATH:+:$NODE_PATH}" \
     node -e "require('enquirer')" >/dev/null 2>&1; then
    return 0
  fi
  # Prepare minimal package.json
  if [[ ! -f "$vendor/package.json" ]]; then
    printf '{"name":"bash-zoo-interactive","private":true}\n' > "$vendor/package.json"
  fi
  # Pick a package manager
  local pm=""
  if command -v npm >/dev/null 2>&1; then
    pm=npm
  elif command -v pnpm >/dev/null 2>&1; then
    pm=pnpm
  elif command -v yarn >/dev/null 2>&1; then
    pm=yarn
  elif command -v bun >/dev/null 2>&1; then
    pm=bun
  else
    return 1
  fi
  case "$pm" in
    npm)  ( cd "$vendor" && npm install --silent enquirer@^2 ) || return 1 ;;
    pnpm) ( cd "$vendor" && pnpm add -s enquirer@^2 ) || return 1 ;;
    yarn) ( cd "$vendor" && yarn add -s enquirer@^2 ) || return 1 ;;
    bun)  ( cd "$vendor" && bun add -y enquirer@^2 ) || return 1 ;;
  esac
  NODE_PATH="$vendor/node_modules${NODE_PATH:+:$NODE_PATH}" node -e "require('enquirer')" >/dev/null 2>&1
}

selector_js_path() {
  # Location where install.sh copies the selector script
  local share_root
  share_root=$(resolve_share_root)
  printf '%s\n' "$share_root/select.js"
}

known_tools() {
  # Keep in sync with scripts/*.sh (not including this file)
  printf '%s\n' \
    airplane \
    astra \
    forgit \
    gpgobble \
    mfa \
    passage \
    share \
    uuid \
    zapp \
    zapper
}

discover_installed_tools() {
  # Discover previously installed tool names by checking bins and rc aliases.
  local target1="$HOME/.local/bin" target2="$HOME/bin"
  local rc1="$HOME/.bashrc" rc2="$HOME/.zshrc"
  local name found any
  while IFS= read -r name; do
    any=0
    # Check bin presence (either target dir)
    if [[ -x "$target1/$name" || -x "$target2/$name" ]]; then
      printf '%s\n' "$name"
      continue
    fi
    # Check rc aliases without relying on current shell aliases
    if [[ -f "$rc1" ]]; then
      if grep -qE "^alias[[:space:]]+$name=" "$rc1"; then any=1; fi
    fi
    if [[ $any -eq 0 && -f "$rc2" ]]; then
      if grep -qE "^alias[[:space:]]+$name=" "$rc2"; then any=1; fi
    fi
    if [[ $any -eq 1 ]]; then
      printf '%s\n' "$name"
    fi
  done < <(known_tools)
}

print_version() {
  printf '%s\n' "$BASH_ZOO_VERSION"
}

uninstall_cmd() {
  local remove_all=0
  if [[ ${1-} == "--all" ]]; then
    remove_all=1
  fi

  # Collect uninstall candidates: bins and rc aliases for known tools
  local bin_dirs rc_files
  bin_dirs=("$HOME/.local/bin" "$HOME/bin")
  rc_files=("$HOME/.bashrc" "$HOME/.zshrc")

  # Build parallel arrays
  local item_labels=() item_kinds=() item_payloads=()

  # Helper: push item
  push_item() {
    item_labels+=("$1")
    item_kinds+=("$2")
    item_payloads+=("$3")
  }

  # Binaries
  local t name d p disp
  while IFS= read -r name; do
    for d in "${bin_dirs[@]}"; do
      p="$d/$name"
      if [[ -e "$p" ]]; then
        disp="$name (bin: ${d/#$HOME/~})"
        push_item "$disp" bin "$p"
      fi
    done
  done < <(known_tools)

  # Aliases
  local rc line alias_name target script label
  for rc in "${rc_files[@]}"; do
    [[ -f "$rc" ]] || continue
    while IFS= read -r line; do
      if [[ "$line" =~ ^alias[[:space:]]+([a-zA-Z0-9_-]+)=[\"\']([^\"\']+)[\"\'] ]]; then
        alias_name="${BASH_REMATCH[1]}"
        target="${BASH_REMATCH[2]}"
        if [[ "$target" =~ scripts/([a-zA-Z0-9_-]+)\.sh$ ]]; then
          script="${BASH_REMATCH[1]}"
          label="alias: $alias_name -> $script (${rc##*/})"
          push_item "$label" alias "$rc $alias_name $script"
        fi
      fi
    done < "$rc"
  done

  # Even if no items found, still offer meta CLI removal option

  local ids=() summaries=()
  local i
  for i in "${!item_labels[@]}"; do
    ids+=("i-$i")
    # Derive a compact summary (left side of label up to first space/paren)
    summaries+=("${item_labels[$i]}")
  done

  local selected_ids=()
  if [[ $remove_all -eq 1 ]]; then
    selected_ids=("${ids[@]}")
  else
    # Prefer enquirer-based selector; fallback to the minimal TUI
    local payload sel_js vendor
    vendor="$(resolve_share_root)/interactive"
    payload='{ "title": "Select items to remove", "choices": ['
    payload+='{"name":"meta-cli","message":"Remove meta CLI (bash-zoo)","summary":"Also remove the bash-zoo command"},'
    payload+='{"name":"all","message":"All (aliases + binaries)","summary":"Remove every listed item (excludes meta CLI)"},'
    for i in "${!ids[@]}"; do
      esc_label=$(printf '%s' "${item_labels[$i]}" | sed 's/\\/\\\\/g; s/"/\\"/g')
      esc_name=$(printf '%s' "${ids[$i]}" | sed 's/"/\\"/g')
      esc_sum=$(printf '%s' "${summaries[$i]}" | sed 's/\\/\\\\/g; s/"/\\"/g')
      payload+="{\"name\":\"$esc_name\",\"message\":\"$esc_label\",\"summary\":\"$esc_sum\"},"
    done
    payload=${payload%,}
    payload+='] }'

    if ensure_enquirer && [[ -f "$(selector_js_path)" ]]; then
      while IFS= read -r __sel; do
        [[ -z "${__sel:-}" ]] && continue
        selected_ids+=("$__sel")
      done < <(BZ_PAYLOAD="$payload" NODE_PATH="$vendor/node_modules${NODE_PATH:+:$NODE_PATH}" node "$(selector_js_path)")
    else
      # Minimal TUI with META + ALL synthetic rows
      local current=0 total=${#item_labels[@]}
      local mark=() meta_selected=0 all_selected=0
      for i in "${!item_labels[@]}"; do mark+=(0); done
      draw_menu() {
        clear
        echo "Select items to remove (J/K move, H toggle, L confirm)"
        # META row
        if [[ $current -eq 0 ]]; then echo -ne "\e[1;32m> "; else echo -ne "  "; fi
        if [[ $meta_selected -eq 1 ]]; then echo -ne "[✔ ] "; else echo -ne "[ ] "; fi
        echo -e "Remove meta CLI (bash-zoo)\e[0m"
        # ALL row
        if [[ $current -eq 1 ]]; then echo -ne "\e[1;32m> "; else echo -ne "  "; fi
        if [[ $all_selected -eq 1 ]]; then echo -ne "[✔ ] "; else echo -ne "[ ] "; fi
        echo -e "All (aliases + binaries)\e[0m"
        # Items
        for i in "${!item_labels[@]}"; do
          local row=$((i+2))
          if [[ $row -eq $current ]]; then echo -ne "\e[1;32m> "; else echo -ne "  "; fi
          if [[ ${mark[$i]} -eq 1 ]]; then echo -ne "[✔ ] "; else echo -ne "[ ] "; fi
          echo -e "${item_labels[$i]}\e[0m"
        done
      }
      while true; do
        draw_menu
        read -rsn1 _k
        case "$_k" in
          j) ((current = (current + 1) % (total + 2))) ;;
          k) ((current = (current - 1 + (total + 2)) % (total + 2))) ;;
          h)
            if [[ $current -eq 0 ]]; then
              meta_selected=$((1 - meta_selected))
            elif [[ $current -eq 1 ]]; then
              if [[ $all_selected -eq 1 ]]; then
                all_selected=0; for i in "${!mark[@]}"; do mark[$i]=0; done
              else
                all_selected=1; for i in "${!mark[@]}"; do mark[$i]=1; done
              fi
            else
              local pos=$((current-2))
              mark[$pos]=$((1 - mark[$pos]))
              # sync all_selected
              all_selected=1
              for i in "${!mark[@]}"; do if [[ ${mark[$i]} -eq 0 ]]; then all_selected=0; break; fi; done
            fi
            ;;
          l) break ;;
        esac
      done
      if [[ $meta_selected -eq 1 ]]; then selected_ids+=("meta-cli"); fi
      if [[ $all_selected -eq 1 ]]; then
        for i in "${!item_labels[@]}"; do selected_ids+=("i-$i"); done
      else
        for i in "${!mark[@]}"; do if [[ ${mark[$i]} -eq 1 ]]; then selected_ids+=("i-$i"); fi; done
      fi
    fi
  fi

  if [[ ${#selected_ids[@]} -eq 0 ]]; then
    echo "No items selected. Exiting."
    return 0
  fi

  # Apply removals
  local remove_meta_cli=0 __s
  for __s in "${selected_ids[@]:-}"; do
    if [[ "$__s" == "meta-cli" ]]; then remove_meta_cli=1; break; fi
  done
  # Expand 'all' if chosen
  for __s in "${selected_ids[@]:-}"; do
    if [[ "$__s" == "all" ]]; then selected_ids=("${ids[@]}"); break; fi
  done

  local removed=0 idx kind payload rcfile aname sname path pat esc rest __sel
  for __sel in "${selected_ids[@]}"; do
    if [[ "$__sel" == all ]]; then continue; fi
    if [[ "$__sel" == meta-cli ]]; then continue; fi
    idx=${__sel#i-}
    kind="${item_kinds[$idx]}"
    payload="${item_payloads[$idx]}"
    if [[ "$kind" == "bin" ]]; then
      path="$payload"
      if [[ -e "$path" ]]; then rm -f "$path" && ((removed+=1)); fi
    else
      # payload: rcfile name script
      rcfile=${payload%% *}
      rest=${payload#* }
      aname=${rest%% *}
      sname=${rest##* }
      pat="^alias[[:space:]]+${aname}=[\"\'][^\"\']*scripts/${sname}\\.sh[\"\']"
      esc=$(printf '%s' "$pat" | sed 's/\//\\\//g')
      if sed --version >/dev/null 2>&1; then
        sed -i -E "/$esc/d" "$rcfile" && ((removed+=1))
      else
        sed -i '' -E "/$esc/d" "$rcfile" && ((removed+=1))
      fi
    fi
  done

  # Optionally remove meta CLI
  if [[ $remove_meta_cli -eq 1 ]]; then
    local d
    for d in "${bin_dirs[@]}"; do
      if [[ -e "$d/bash-zoo" ]]; then rm -f "$d/bash-zoo" && ((removed+=1)); fi
    done
  fi

  # If no more zoo bins remain, clean PATH lines we added earlier
  local any_left=0 d sfile sname
  for d in "${bin_dirs[@]}"; do
    # meta CLI present keeps PATH line
    if [[ -e "$d/bash-zoo" ]]; then any_left=1; break; fi
    for sfile in $(known_tools); do
      sname="$sfile"
      if [[ -e "$d/$sname" ]]; then any_left=1; break; fi
    done
    [[ $any_left -eq 1 ]] && break
  done
  if [[ $any_left -eq 0 ]]; then
    for rc in "${rc_files[@]}"; do
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
}


update_passwords_cmd() {
  local root="$HOME/.password-store"
  if [[ ! -d "$root" ]]; then
    echo_err "No ~/.password-store found"
    exit 1
  fi
  if ! command -v git >/dev/null 2>&1; then
    echo_err "git is required for password store updates"
    exit 1
  fi
  local dir updated=0 uptodate=0 ahead=0 diverged=0 skipped=0 failed=0
  for dir in "$root"/*; do
    [[ -d "$dir" ]] || continue
    if ! git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
      echo "[skipped] ${dir##*/} (not a git repo)"
      ((skipped+=1))
      continue
    fi

    # Ensure we have remote info without altering the working tree
    if ! git -C "$dir" fetch --quiet; then
      echo "[failed]  ${dir##*/} (fetch error)"
      ((failed+=1))
      continue
    fi

    # Determine upstream; skip repos without an upstream
    if ! git -C "$dir" rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
      echo "[skipped] ${dir##*/} (no upstream)"
      ((skipped+=1))
      continue
    fi

    local head_sha up_sha base_sha
    if ! head_sha=$(git -C "$dir" rev-parse --verify HEAD 2>/dev/null); then
      echo "[failed]  ${dir##*/} (no HEAD)"
      ((failed+=1))
      continue
    fi
    if ! up_sha=$(git -C "$dir" rev-parse --verify @{u} 2>/dev/null); then
      echo "[skipped] ${dir##*/} (cannot resolve upstream)"
      ((skipped+=1))
      continue
    fi
    if ! base_sha=$(git -C "$dir" merge-base HEAD @{u} 2>/dev/null); then
      echo "[failed]  ${dir##*/} (merge-base error)"
      ((failed+=1))
      continue
    fi

    if [[ "$head_sha" == "$up_sha" ]]; then
      echo "[up-to-date] ${dir##*/}"
      ((uptodate+=1))
    elif [[ "$head_sha" == "$base_sha" ]]; then
      # Behind; fast-forward pull
      if git -C "$dir" pull --ff-only --quiet; then
        echo "[updated] ${dir##*/}"
        ((updated+=1))
      else
        echo "[failed]  ${dir##*/} (fast-forward failed)"
        ((failed+=1))
      fi
    elif [[ "$up_sha" == "$base_sha" ]]; then
      echo "[ahead] ${dir##*/}"
      ((ahead+=1))
    else
      echo "[diverged] ${dir##*/}"
      ((diverged+=1))
    fi
  done
  echo "-- summary --"
  echo "updated: $updated, up-to-date: $uptodate, ahead: $ahead, diverged: $diverged, failed: $failed, skipped: $skipped"
}

main() {
  local cmd="${1:-version}"
  case "$cmd" in
    help|-h|--help) print_usage ;;
    version)        print_version ;;
    uninstall)      shift; uninstall_cmd "${1-}" ;;
    update)
      shift
      case "${1-}" in
        passwords)  shift; update_passwords_cmd ;;
        *) echo_err "Unknown update target. Use 'passwords'."; exit 1 ;;
      esac
      ;;
    *) echo_err "Unknown command: $cmd"; print_usage; exit 1 ;;
  esac
}

main "$@"
