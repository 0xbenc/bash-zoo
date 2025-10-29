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

ensure_gum() {
  # Ensure gum exists; on Linux, bootstrap Homebrew (Linuxbrew) and install gum
  if command -v gum >/dev/null 2>&1; then
    return 0
  fi
  local os
  os=$(resolve_os_type)
  if [[ "$os" == "macos" ]]; then
    if command -v brew >/dev/null 2>&1; then
      echo "Preparing selector (installing gum via Homebrew)..."
      brew list --versions gum >/dev/null 2>&1 || brew install gum >/dev/null 2>&1 || true
      command -v gum >/dev/null 2>&1 && return 0
    fi
    return 1
  fi
  if [[ "$os" == "debian" ]]; then
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
    install_homebrew_linux() {
      if find_brew_bin >/dev/null 2>&1; then return 0; fi
      echo "Installing Homebrew for Linux (non-interactive)..."
      local tmp_dir installer
      tmp_dir=$(mktemp -d)
      installer="$tmp_dir/install-homebrew.sh"
      if curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$installer"; then
        chmod +x "$installer" || true
        NONINTERACTIVE=1 /bin/bash "$installer"
      fi
      rm -rf "$tmp_dir" 2>/dev/null || true
      find_brew_bin >/dev/null 2>&1
    }
    if ! find_brew_bin >/dev/null 2>&1; then
      install_homebrew_linux || true
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
    if ! ensure_gum; then
      echo_err "gum is required for interactive selection and could not be installed automatically."
      echo_err "Use 'bash-zoo uninstall --all' to remove everything except the meta CLI without prompts."
      return 1
    fi
    local labels=()
    labels+=("meta-cli — Remove meta CLI (bash-zoo)")
    labels+=("all — All (aliases + binaries)")
    for i in "${!ids[@]}"; do
      labels+=("${ids[$i]} — ${item_labels[$i]}")
    done
    while IFS= read -r __sel; do
      [[ -z "${__sel:-}" ]] && continue
      selected_ids+=("${__sel%%[[:space:]]*}")
    done < <(printf '%s\n' "${labels[@]}" | gum choose --no-limit --header "Select items to remove")
    clear || true
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
