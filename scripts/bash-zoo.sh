#!/bin/bash

set -euo pipefail

# Meta CLI for Bash Zoo
# - Always installed into user bin by install.sh
# - Portable: avoids Bash 4-only features

# Version is embedded at install time by install.sh
BASH_ZOO_VERSION="@VERSION@"
# Default repository URL embedded at install time (may be empty when unknown)
BASH_ZOO_REPO_URL="@REPO_URL@"

print_usage() {
  cat <<'EOF'
bash-zoo — meta CLI

Usage:
  bash-zoo help
  bash-zoo version
  bash-zoo uninstall [--all]
  bash-zoo update passwords
  bash-zoo update zoo [--from PATH] [--repo URL] [--branch BR] [--dry-run] [--force] [--no-meta]

Commands:
  help                 Show this help.
  version              Print the installed bash-zoo version.
  uninstall [--all]    Remove installed tools and aliases. Use --all to skip prompts.
  update passwords     Pull latest for each subfolder in ~/.password-store.
  update zoo           Refresh installed tools and the meta CLI from source.
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

# Install a file atomically within its directory using a temp file + mv
atomic_install_file() {
  local src="$1" dst="$2"
  local dir tmp
  dir=$(dirname "$dst")
  ensure_dir "$dir"
  tmp="$dir/.zoo.$$.$RANDOM.tmp"
  # Copy to a temp neighbor and then move into place
  cp -f "$src" "$tmp" 2>/dev/null || cp "$src" "$tmp"
  mv -f "$tmp" "$dst"
}

# Replace a directory atomically: stage new at sibling, swap with double-rename
atomic_replace_dir() {
  local src_dir="$1" target_dir="$2"
  local parent stage bak
  parent=$(dirname "$target_dir")
  ensure_dir "$parent"
  stage="$parent/.zoo.$$.stage"
  bak="$parent/.zoo.$$.bak"
  rm -rf "$stage" "$bak" 2>/dev/null || true
  mkdir -p "$stage"
  # Copy contents into stage
  # shellcheck disable=SC2164
  (cd "$src_dir" && tar cf - .) | (cd "$stage" && tar xf -) || return 1
  # Perform double-rename swap
  if [[ -e "$target_dir" ]]; then
    mv "$target_dir" "$bak"
  fi
  mv "$stage" "$target_dir"
  rm -rf "$bak" 2>/dev/null || true
}

# Version compare supporting legacy semver and new revisions (rN)
# Returns: 1 if a>b, -1 if a<b, 0 if equal
version_compare() {
  local a b
  a="$1"; b="$2"
  # Detect revision form: rN or N
  if [[ "$a" =~ ^[rR]?[0-9]+$ && "$b" =~ ^[rR]?[0-9]+$ ]]; then
    local ai="${a#[rR]}" bi="${b#[rR]}"
    if (( ai > bi )); then echo 1; return 0; fi
    if (( ai < bi )); then echo -1; return 0; fi
    echo 0; return 0
  fi
  # If only one is revision, treat revisions as newer than any semver
  if [[ "$a" =~ ^[rR]?[0-9]+$ && ! "$b" =~ ^[rR]?[0-9]+$ ]]; then
    echo 1; return 0
  fi
  if [[ "$b" =~ ^[rR]?[0-9]+$ && ! "$a" =~ ^[rR]?[0-9]+$ ]]; then
    echo -1; return 0
  fi
  # Fallback: simple semantic version compare (major.minor.patch)
  local IFS=.
  local a_clean b_clean
  a_clean="$a"; b_clean="$b"
  # Remove any leading non-numeric text
  a_clean=${a_clean##*[!0-9.]}
  b_clean=${b_clean##*[!0-9.]}
  local -a av=(0 0 0 0) bv=(0 0 0 0)
  local av0 av1 av2 av3 bv0 bv1 bv2 bv3 i
  IFS=. read -r av0 av1 av2 av3 <<<"$a_clean"
  IFS=. read -r bv0 bv1 bv2 bv3 <<<"$b_clean"
  av[0]=${av0:-0}; av[1]=${av1:-0}; av[2]=${av2:-0}; av[3]=${av3:-0}
  bv[0]=${bv0:-0}; bv[1]=${bv1:-0}; bv[2]=${bv2:-0}; bv[3]=${bv3:-0}
  for i in 0 1 2 3; do
    if (( av[$i] > bv[$i] )); then echo 1; return 0; fi
    if (( av[$i] < bv[$i] )); then echo -1; return 0; fi
  done
  echo 0
}

read_installed_metadata() {
  # Outputs via global vars: INST_VER, INST_COMMIT, INST_REPO_URL
  # and global array INST_LIST (names only, excludes meta CLI)
  INST_VER="0.0.0"; INST_COMMIT="unknown"; INST_REPO_URL=""
  INST_LIST=()
  local share_root meta_file
  share_root=$(resolve_share_root)
  meta_file="$share_root/installed.json"
  if [[ ! -f "$meta_file" ]]; then
    return 0
  fi
  local line
  line=$(tr -d '\n' < "$meta_file" 2>/dev/null || true)
  if [[ -n "$line" ]]; then
    case "$line" in
      *"version"*) INST_VER=$(printf '%s' "$line" | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p') ;; esac
    case "$line" in
      *"commit"*) INST_COMMIT=$(printf '%s' "$line" | sed -n 's/.*"commit"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p') ;; esac
    case "$line" in
      *"repo_url"*) INST_REPO_URL=$(printf '%s' "$line" | sed -n 's/.*"repo_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p') ;; esac
    # Parse installed list
    if printf '%s' "$line" | grep -q '"installed"'; then
      local arr
      arr=$(printf '%s' "$line" | sed -n 's/.*"installed"[[:space:]]*:[[:space:]]*\[\(.*\)\].*/\1/p')
      # Split on commas and strip quotes/spaces
      IFS=, read -r -a __items <<<"$arr"
      local it name
      for it in "${__items[@]:-}"; do
        name=$(printf '%s' "$it" | sed -e 's/^[[:space:]]*"//' -e 's/"[[:space:]]*$//')
        if [[ -n "$name" && "$name" != "bash-zoo" ]]; then
          INST_LIST+=("$name")
        fi
      done
    fi
  fi
}

write_installed_metadata_update() {
  # Args: version commit repo_url installed_names...
  local version="$1" commit="$2" repo_url="$3"; shift 3
  local share_root meta_file
  share_root=$(resolve_share_root)
  meta_file="$share_root/installed.json"
  ensure_dir "$share_root"
  # Build JSON array
  local out="[" first=1 n
  for n in "$@"; do
    if [[ "$n" == "bash-zoo" || -z "$n" ]]; then continue; fi
    if [[ $first -eq 1 ]]; then out+="\"$n\""; first=0; else out+=",\"$n\""; fi
  done
  out+="]"
  printf '{"version":"%s","commit":"%s","repo_url":"%s","installed":%s}\n' \
    "$version" "${commit:-unknown}" "${repo_url:-}" "$out" > "$meta_file"
}

find_meta_cli_path() {
  local p1 p2
  p1="$HOME/.local/bin/bash-zoo"
  p2="$HOME/bin/bash-zoo"
  if [[ -e "$p1" ]]; then printf '%s\n' "$p1"; return 0; fi
  if [[ -e "$p2" ]]; then printf '%s\n' "$p2"; return 0; fi
  return 1
}

tool_bin_path() {
  local name="$1" p
  for p in "$HOME/.local/bin/$name" "$HOME/bin/$name"; do
    if [[ -x "$p" ]]; then printf '%s\n' "$p"; return 0; fi
  done
  return 1
}

tool_is_alias_only() {
  local name="$1" rc
  if tool_bin_path "$name" >/dev/null 2>&1; then
    return 1
  fi
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [[ -f "$rc" ]] || continue
    if grep -qE "^alias[[:space:]]+$name=" "$rc" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

render_meta_cli() {
  # Args: src_repo_dir out_path version repo_url
  local src_dir="$1" out="$2" version="$3" repo_url="$4"
  local src="$src_dir/scripts/bash-zoo.sh"
  if [[ ! -f "$src" ]]; then
    return 1
  fi
  # Use sed without in-place to keep portability
  if sed --version >/dev/null 2>&1; then
    sed -e "s/@VERSION@/${version//\//\/}/g" \
        -e "s|@REPO_URL@|${repo_url//\//\/}|g" "$src" > "$out"
  else
    sed -e "s/@VERSION@/${version//\//\/}/g" \
        -e "s|@REPO_URL@|${repo_url//\//\/}|g" "$src" > "$out"
  fi
}

update_zoo_cmd() {
  # Options
  local from_path="" repo_url="" branch="" dry_run=0 force=0 no_meta=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --from) from_path="$2"; shift 2 ;;
      --from=*) from_path="${1#*=}"; shift ;;
      --repo) repo_url="$2"; shift 2 ;;
      --repo=*) repo_url="${1#*=}"; shift ;;
      --branch) branch="$2"; shift 2 ;;
      --branch=*) branch="${1#*=}"; shift ;;
      --dry-run) dry_run=1; shift ;;
      --force) force=1; shift ;;
      --no-meta) no_meta=1; shift ;;
      --help|-h) echo "Usage: bash-zoo update zoo [--from PATH] [--repo URL] [--branch BR] [--dry-run] [--force] [--no-meta]"; return 0 ;;
      *) echo_err "Unknown option: $1"; return 1 ;;
    esac
  done

  # Read installed metadata (best-effort)
  read_installed_metadata
  local installed_version="$INST_VER" installed_commit="$INST_COMMIT" installed_repo_url="$INST_REPO_URL"

  # Determine source
  local mode="clone" source_dir tmp_dir
  if [[ -n "$from_path" ]]; then
    mode="dev"
    # Validate contents
    if [[ ! -d "$from_path/scripts" || ! -f "$from_path/VERSION" ]]; then
      echo_err "--from path must contain 'scripts/' and 'VERSION'"
      return 1
    fi
    source_dir="$from_path"
  else
    # Determine repo URL precedence: flag -> env -> embedded
    if [[ -z "$repo_url" ]]; then
      if [[ -n "${BASH_ZOO_REPO_URL:-}" ]]; then
        repo_url="$BASH_ZOO_REPO_URL"
      fi
    fi
    if [[ -z "$repo_url" && -n "${INST_REPO_URL:-}" ]]; then
      repo_url="$INST_REPO_URL"
    fi
    if [[ -z "$repo_url" ]]; then
      echo_err "No repo URL available. Provide --repo or set BASH_ZOO_REPO_URL."
      return 1
    fi
    if ! command -v git >/dev/null 2>&1; then
      echo_err "git is required for cloning updates"
      return 1
    fi
    tmp_dir=$(mktemp -d)
    if [[ -n "$branch" ]]; then
      if ! git clone --depth 1 --branch "$branch" "$repo_url" "$tmp_dir" >/dev/null 2>&1; then
        echo_err "Failed to clone $repo_url (branch $branch)"
        rm -rf "$tmp_dir" 2>/dev/null || true
        return 1
      fi
    else
      if ! git clone --depth 1 "$repo_url" "$tmp_dir" >/dev/null 2>&1; then
        echo_err "Failed to clone $repo_url"
        rm -rf "$tmp_dir" 2>/dev/null || true
        return 1
      fi
    fi
    source_dir="$tmp_dir"
  fi

  # Source metadata
  local src_version src_commit
  if [[ -f "$source_dir/VERSION" ]]; then
    src_version=$(cat "$source_dir/VERSION")
  else
    src_version="0.0.0"
  fi
  if [[ "$mode" == "clone" ]]; then
    src_commit=$(git -C "$source_dir" rev-parse --verify HEAD 2>/dev/null || echo "unknown")
  else
    src_commit="unknown"
  fi

  # Gate update (regular mode only, unless --force)
  local allow_update=1 reason=""
  if [[ $force -eq 1 ]]; then
    allow_update=1
  elif [[ "$mode" == "dev" ]]; then
    allow_update=1
  else
    # Compare versions
    local cmp; cmp=$(version_compare "$src_version" "${installed_version:-0.0.0}")
    if [[ "$cmp" == "1" ]]; then
      allow_update=1
    elif [[ "$cmp" == "-1" ]]; then
      allow_update=0; reason="source version older"
    else
      # Equal versions: check ancestry
      if [[ -n "$installed_commit" && "$installed_commit" != "unknown" ]]; then
        if git -C "$source_dir" merge-base --is-ancestor "$installed_commit" HEAD >/dev/null 2>&1; then
          allow_update=1
        else
          # Possibly shallow; try deepening
          if git -C "$source_dir" fetch --deepen 1000 >/dev/null 2>&1 || git -C "$source_dir" fetch --unshallow >/dev/null 2>&1; then
            if git -C "$source_dir" merge-base --is-ancestor "$installed_commit" HEAD >/dev/null 2>&1; then
              allow_update=1
            else
              allow_update=0; reason="installed commit not ancestor"
            fi
          else
            allow_update=0; reason="ancestry unknown due to shallow clone"
          fi
        fi
      else
        allow_update=0; reason="installed commit unknown; equal versions"
      fi
    fi
  fi

  # Build installed set: discovered + metadata, dedup
  local -a names; names=()
  local seen=""
  while IFS= read -r n; do
    if [[ -z "$n" ]]; then continue; fi
    case ",$seen," in *",$n,"*) ;; *) names+=("$n"); seen="$seen,$n" ;; esac
  done < <(discover_installed_tools)
  local m
  for m in "${INST_LIST[@]:-}"; do
    case ",$seen," in *",$m,"*) ;; *) names+=("$m"); seen="$seen,$m" ;; esac
  done

  local updated=0 uptodate=0 skipped=0 failed=0

  # Update tools (bins only). Skip alias-only installs.
  local name src_tool bin_path line_prefix
  for name in "${names[@]:-}"; do
    # Special-case astra: runtime assets handled later; skip bin here
    if [[ "$name" == "astra" ]]; then
      continue
    fi
    if tool_is_alias_only "$name"; then
      line_prefix="[skipped-alias]"
      if [[ $dry_run -eq 1 ]]; then line_prefix="[would-skipped-alias]"; fi
      echo "$line_prefix $name"
      ((skipped+=1))
      continue
    fi
    if ! bin_path=$(tool_bin_path "$name"); then
      # Not in bin; nothing to do
      line_prefix="[skipped]"
      if [[ $dry_run -eq 1 ]]; then line_prefix="[would-skipped]"; fi
      echo "$line_prefix $name (no installed binary)"
      ((skipped+=1))
      continue
    fi
    src_tool="$source_dir/scripts/$name.sh"
    if [[ ! -f "$src_tool" ]]; then
      line_prefix="[skipped]"; [[ $dry_run -eq 1 ]] && line_prefix="[would-skipped]"
      echo "$line_prefix $name (not found in source)"
      ((skipped+=1))
      continue
    fi
    # Gating
    if [[ $allow_update -eq 0 ]]; then
      line_prefix="[up-to-date]"; [[ $dry_run -eq 1 ]] && line_prefix="[would-up-to-date]"
      echo "$line_prefix $name (repo gate: $reason)"
      ((uptodate+=1))
      continue
    fi
    if cmp -s "$src_tool" "$bin_path"; then
      line_prefix="[up-to-date]"; [[ $dry_run -eq 1 ]] && line_prefix="[would-up-to-date]"
      echo "$line_prefix $name"
      ((uptodate+=1))
    else
      if [[ $dry_run -eq 1 ]]; then
        echo "[would-updated] $name"
      else
        if atomic_install_file "$src_tool" "$bin_path"; then
          echo "[updated] $name"
        else
          echo "[failed]  $name (install error)"; ((failed+=1)); continue
        fi
      fi
      ((updated+=1))
    fi
  done

  # Astra runtime sync if astra is installed
  local have_astra=0 asrc="" share_root runtime_target
  for m in "${names[@]:-}"; do if [[ "$m" == "astra" ]]; then have_astra=1; break; fi; done
  if [[ $have_astra -eq 1 ]]; then
    asrc="$source_dir/astra"
    if [[ -d "$asrc" ]]; then
      share_root=$(resolve_share_root)
      runtime_target="$share_root/astra"
      if [[ $allow_update -eq 0 ]]; then
        line_prefix="[up-to-date]"; [[ $dry_run -eq 1 ]] && line_prefix="[would-up-to-date]"
        echo "$line_prefix astra-runtime (repo gate: $reason)"
        ((uptodate+=1))
      else
        if [[ $dry_run -eq 1 ]]; then
          echo "[would-updated] astra-runtime"
          ((updated+=1))
        else
          if atomic_replace_dir "$asrc" "$runtime_target"; then
            echo "[updated] astra-runtime"
            ((updated+=1))
          else
            echo "[failed]  astra-runtime (replace error)"; ((failed+=1))
          fi
        fi
      fi
    fi
  fi

  # Meta CLI update (unless --no-meta)
  if [[ $no_meta -ne 1 ]]; then
    local meta_path="" rendered="" embed_url=""
    if meta_path=$(find_meta_cli_path); then
      embed_url="$repo_url"
      if [[ -z "$embed_url" ]]; then embed_url="${BASH_ZOO_REPO_URL:-}"; fi
      if [[ -z "$embed_url" ]]; then embed_url="${installed_repo_url:-}"; fi
      rendered=$(mktemp)
      if render_meta_cli "$source_dir" "$rendered" "$src_version" "$embed_url"; then
        chmod +x "$rendered" 2>/dev/null || true
        if [[ $allow_update -eq 0 ]]; then
          line_prefix="[up-to-date]"; [[ $dry_run -eq 1 ]] && line_prefix="[would-up-to-date]"
          echo "$line_prefix bash-zoo (repo gate: $reason)"
          ((uptodate+=1))
        else
          if cmp -s "$rendered" "$meta_path"; then
            line_prefix="[up-to-date]"; [[ $dry_run -eq 1 ]] && line_prefix="[would-up-to-date]"
            echo "$line_prefix bash-zoo"
            ((uptodate+=1))
          else
            if [[ $dry_run -eq 1 ]]; then
              echo "[would-updated] bash-zoo"
              ((updated+=1))
            else
              if atomic_install_file "$rendered" "$meta_path"; then
                echo "[updated] bash-zoo"
                ((updated+=1))
              else
                echo "[failed]  bash-zoo (install error)"; ((failed+=1))
              fi
            fi
          fi
        fi
      fi
      rm -f "$rendered" 2>/dev/null || true
    fi
  fi

  # Merge installed names and write metadata
  local merged=() dedup="," t
  for t in "${names[@]:-}"; do
    case "$dedup" in *",$t,"*) ;; *) merged+=("$t"); dedup="$dedup$t," ;; esac
  done
  # Use repo_url used for clone or fallbacks for metadata
  local meta_repo_url="$repo_url"; [[ -z "$meta_repo_url" ]] && meta_repo_url="${installed_repo_url:-}"
  if [[ $dry_run -eq 1 ]]; then
    : # do not write metadata
  else
    write_installed_metadata_update "$src_version" "$src_commit" "$meta_repo_url" "${merged[@]:-}"
  fi

  echo "-- summary --"
  echo "updated: $updated, up-to-date: $uptodate, failed: $failed, skipped: $skipped"

  # Cleanup
  if [[ "$mode" == "clone" && -n "${tmp_dir:-}" ]]; then rm -rf "$tmp_dir" 2>/dev/null || true; fi
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
        zoo)        shift; update_zoo_cmd "$@" ;;
        *) echo_err "Unknown update target. Use 'passwords' or 'zoo'."; exit 1 ;;
      esac
      ;;
    *) echo_err "Unknown command: $cmd"; print_usage; exit 1 ;;
  esac
}

main "$@"
