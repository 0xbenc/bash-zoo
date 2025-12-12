#!/bin/bash

set -euo pipefail

# ssherpa: Fuzzy-pick an SSH host from OpenSSH config (with Includes) and connect.
# UI: gum-only (filter). No fzf fallback.
# Parsing: minimal, captures Host, HostName, User, Port, IdentityFile; ignores Match logic.

print_usage() {
  cat <<'EOF'
Usage:
  ssherpa [--all] [--print|--exec] [--filter SUBSTR] [--user USER]
          [--no-color] [--config PATH]
          [--] [ssh-args...]

Subcommands:
  ssherpa add [--alias NAME] [--host HOST] [--user USER] [--port 22]
              [--identity PATH] [--config PATH] [--dry-run] [--yes]
  ssherpa edit [--config PATH] [--all] [--filter SUBSTR] [--user USER]
  ssherpa authkeys                     # manage authorized_keys on this device

Defaults:
  Interactive gum filter, executes ssh after selection.
  Only concrete Host aliases (no wildcards) unless --all.

Examples:
  ssherpa
  ssherpa --print -- -L 8080:localhost:8080
  ssherpa --filter prod --user farmer
  ssherpa --all
EOF
}

echo_err() { printf '%s\n' "$*" >&2; }

ensure_gum() {
  if command -v gum >/dev/null 2>&1; then return 0; fi
  echo_err "gum is required. Install it with Homebrew:"
  echo_err "  brew install gum"
  return 1
}

trim() {
  # Usage: trim "string"
  printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

is_git_user() {
  case "$1" in
    git|Git|GIT) return 0 ;;
    *) return 1 ;;
  esac
}

is_pattern_name() {
  case "$1" in *'*'*|*'?'*) return 0 ;; *) return 1 ;; esac
}

expand_path_pattern() {
  # Args: pattern base_dir
  local pat="$1" base="$2" abs
  if [[ "$pat" == ~* ]]; then
    pat="$HOME${pat#~}"
  elif [[ "$pat" != /* ]]; then
    pat="$base/$pat"
  fi
  # Expand globs to file paths (nullglob)
  local oldshopt
  oldshopt=$(shopt -p nullglob || true)
  shopt -s nullglob
  local f
  for f in $pat; do
    printf '%s\n' "$f"
  done
  eval "$oldshopt" 2>/dev/null || true
}

load_config_files() {
  # Build a list of config files starting with ~/.ssh/config, then Includes (breadth-first), avoid duplicates.
  local main="$HOME/.ssh/config"
  CONFIG_FILES=()
  local queue=() seen=$'\n'
  if [[ -f "$main" ]]; then
    queue+=("$main")
  fi
  local idx=0
  while [[ $idx -lt ${#queue[@]} ]]; do
    local file="${queue[$idx]}"; idx=$((idx+1))
    # Dedup
    case "$seen" in *$'\n'"$file"$'\n'*) continue ;; esac
    seen+="$file"$'\n'
    CONFIG_FILES+=("$file")
    # Parse for Include lines to enqueue
    local dir line key rest pat
    dir=$(dirname "$file")
    while IFS= read -r line || [[ -n "$line" ]]; do
      # Strip leading spaces
      case "$line" in ''|'#'*) continue ;; esac
      # Trim comments (simple: split on # when not first char)
      line=$(printf '%s' "$line" | sed 's/[[:space:]]*#.*$//')
      line=$(trim "$line")
      [[ -z "$line" ]] && continue
      key=$(printf '%s' "$line" | awk '{print tolower($1)}')
      case "$key" in
        include)
          rest=$(printf '%s' "$line" | sed -n 's/^[Ii][Nn][Cc][Ll][Uu][Dd][Ee][[:space:]]\+\(.*\)$/\1/p')
          rest=$(trim "$rest")
          # Split rest by spaces into patterns
          IFS=' ' read -r -a _pats <<<"$rest"
          local p f
          for p in "${_pats[@]}"; do
            for f in $(expand_path_pattern "$p" "$dir"); do
              # avoid duplicates in queue
              case "$seen" in *$'\n'"$f"$'\n'*) ;; *) queue+=("$f") ;; esac
            done
          done
          ;;
      esac
    done < "$file"
  done
}

# Entry arrays (parallel)
NAMES=()
HOSTS=()
USERS=()
PORTS=()
KEYS=()
PATTERNS=()  # 0/1
# UI labels and helpers
ADD_ROW_LABEL="➕ Add new alias…"
JUMP_ROW_LABEL="🧭 Jump via intermediate hops…"
PROXY_ROW_LABEL="🧦 Start SOCKS proxy (preset)…"
EDIT_ROW_LABEL="✏️ Edit aliases or delete…"
AUTHKEYS_ROW_LABEL="🔑 Manage authorized_keys on this device…"
style_step() { gum style --bold --foreground 212 "$1" 2>/dev/null || printf '%s\n' "$1"; }
style_hint() { gum style --faint "$1" 2>/dev/null || printf '%s\n' "$1"; }
clear_screen() {
  if command -v tput >/dev/null 2>&1; then tput clear; else clear 2>/dev/null || printf '\033[2J\033[H'; fi
}
draw_rule() {
  local cols="${COLUMNS:-}"
  if [[ -z "$cols" ]]; then
    if command -v tput >/dev/null 2>&1; then cols=$(tput cols 2>/dev/null || echo 80); else cols=80; fi
  fi
  local line
  printf -v line '%*s' "$cols" ''
  line=${line// /─}
  if command -v gum >/dev/null 2>&1; then
    gum style --foreground 240 "$line"
  else
    printf '%s\n' "$line"
  fi
}
alt_screen_on() {
  if command -v tput >/dev/null 2>&1; then
    tput smcup 2>/dev/null || printf '\033[?1049h'
    tput civis 2>/dev/null || true
  else
    printf '\033[?1049h\033[?25l'
  fi
}
alt_screen_off() {
  if command -v tput >/dev/null 2>&1; then
    tput cnorm 2>/dev/null || true
    tput rmcup 2>/dev/null || printf '\033[?1049l'
  else
    printf '\033[?25h\033[?1049l'
  fi
}

# Alias-only: no known_hosts integration

add_or_replace_entry() {
  local name="$1" host="$2" user="$3" port="$4" key="$5" ispat="$6"
  local i
  for i in "${!NAMES[@]}"; do
    if [[ "${NAMES[$i]}" == "$name" ]]; then
      HOSTS[$i]="$host"; USERS[$i]="$user"; PORTS[$i]="$port"; KEYS[$i]="$key"; PATTERNS[$i]="$ispat"
      return 0
    fi
  done
  NAMES+=("$name"); HOSTS+=("$host"); USERS+=("$user"); PORTS+=("$port"); KEYS+=("$key"); PATTERNS+=("$ispat")
}

parse_configs() {
  # Requires CONFIG_FILES[]
  NAMES=(); HOSTS=(); USERS=(); PORTS=(); KEYS=(); PATTERNS=()
  local file dir line key lowkey val cur_names cur_host cur_user cur_port cur_key idx
  for idx in "${!CONFIG_FILES[@]}"; do
    file="${CONFIG_FILES[$idx]}"
    dir=$(dirname "$file")
    # Reset stanza vars when starting a new file
    cur_names=""; cur_host=""; cur_user=""; cur_port=""; cur_key=""
    while IFS= read -r line || [[ -n "$line" ]]; do
      # Strip inline comments and trim
      line=$(printf '%s' "$line" | sed 's/[[:space:]]*#.*$//')
      line=$(trim "$line")
      [[ -z "$line" ]] && continue
      key=${line%%[[:space:]]*}
      lowkey=$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')
      val=$(trim "${line#*$key}")
      case "$lowkey" in
        host)
          # Flush previous stanza entries
          if [[ -n "$cur_names" ]]; then
            IFS=' ' read -r -a _names <<<"$cur_names"
            local nm ispat
            for nm in "${_names[@]}"; do
              is_pattern_name "$nm" && ispat=1 || ispat=0
              add_or_replace_entry "$nm" "$cur_host" "$cur_user" "$cur_port" "$cur_key" "$ispat"
            done
          fi
          cur_names="$val"; cur_host=""; cur_user=""; cur_port=""; cur_key=""
          ;;
        hostname)
          cur_host="$val" ;;
        user)
          cur_user="$val" ;;
        port)
          cur_port="$val" ;;
        identityfile)
          # first occurrence only
          if [[ -z "$cur_key" ]]; then cur_key="$val"; fi ;;
        include|match)
          # handled elsewhere or ignored
          : ;;
        *)
          : ;;
      esac
    done < "$file"
    # Flush at EOF
    if [[ -n "$cur_names" ]]; then
      IFS=' ' read -r -a _names <<<"$cur_names"
      local nm ispat
      for nm in "${_names[@]}"; do
        is_pattern_name "$nm" && ispat=1 || ispat=0
        add_or_replace_entry "$nm" "$cur_host" "$cur_user" "$cur_port" "$cur_key" "$ispat"
      done
    fi
  done
}

build_alias_lines() {
  # Build lines with a real tab between alias token and display.
  local include_patterns="$1" filter_user="$2" prefilter="$3" no_color="$4"
  local ignore_git_user
  case "${SSHERPA_IGNORE_USER_GIT:-1}" in
    0|false|no|off) ignore_git_user=0 ;;
    *) ignore_git_user=1 ;;
  esac
  LINES=()
  # Synthetic Add row first so it appears before other options
  LINES+=("ADD"$'\t'"$ADD_ROW_LABEL")
  # Edit row, placed after ADD and before proxy/jump/aliases
  LINES+=("EDIT"$'\t'"$EDIT_ROW_LABEL")
  # authorized_keys helper, placed after EDIT
  LINES+=("AUTHKEYS"$'\t'"$AUTHKEYS_ROW_LABEL")
  # Proxy row, placed after ADD/EDIT and before jump/aliases
  LINES+=("PROXY"$'\t'"$PROXY_ROW_LABEL")
  # Jump mode row, placed after ADD/EDIT/PROXY and before aliases
  LINES+=("JUMP"$'\t'"$JUMP_ROW_LABEL")
  local i name host user port key ispat info
  for i in "${!NAMES[@]}"; do
    name="${NAMES[$i]}"; host="${HOSTS[$i]}"; user="${USERS[$i]}"; port="${PORTS[$i]}"; key="${KEYS[$i]}"; ispat="${PATTERNS[$i]}"
    if [[ "$include_patterns" != "1" && "$ispat" == "1" ]]; then continue; fi
    if [[ "$ignore_git_user" -eq 1 && -z "$filter_user" ]] && is_git_user "${user:-}"; then
      continue
    fi
    if [[ -n "$filter_user" && -n "$user" && "$user" != "$filter_user" ]]; then continue; fi
    info=""
    if [[ -n "$user" || -n "$host" || -n "$port" ]]; then
      [[ -n "$user" ]] && info+="$user@"
      info+="$host"
      [[ -n "$port" ]] && info+=":$port"
    fi
    if [[ -n "$key" ]]; then
      [[ -n "$info" ]] && info+=" "
      info+="[$key]"
    fi
    [[ -z "$info" ]] && info="(no HostName in config)"
    LINES+=("$name"$'\t'"$info")
  done
  # Prefilter by substring
  if [[ -n "$prefilter" ]]; then
    local tmp=() l
    for l in "${LINES[@]:-}"; do
      case "$l" in *"$prefilter"*) tmp+=("$l") ;; esac
    done
    LINES=("${tmp[@]:-}")
  fi
}

config_path_default() { printf '%s\n' "$HOME/.ssh/config"; }

atomic_write_file() {
  # args: src_tmp dst_path
  local src="$1" dst="$2" dir
  dir=$(dirname "$dst")
  mkdir -p "$dir"
  local tmp="$dir/.zoo.$$.$RANDOM.tmp"
  cp -f "$src" "$tmp" 2>/dev/null || cp "$src" "$tmp"
  mv -f "$tmp" "$dst"
}

remove_alias_from_config_stream() {
  # stdin: original config; stdout: config without the alias stanza(s)
  # args: alias
  local alias="$1"
  awk -v target="$alias" '
    BEGIN{copy=1}
    /^Host[[:space:]]+/ {
      # Determine if this Host line contains the alias as a discrete token
      copy=1
      line=$0
      sub(/^Host[[:space:]]+/, "", line)
      n=split(line, arr, /[[:space:]]+/)
      for (i=1;i<=n;i++) { if (arr[i]==target) { copy=0; break } }
    }
    { if (copy) print }
  '
}

delete_alias_everywhere() {
  # args: alias dry_run
  local alias="$1" dry_run="${2:-0}"
  local cfg tmp changed any=0
  for cfg in "${CONFIG_FILES[@]:-}"; do
    [[ -f "$cfg" ]] || continue
    tmp=$(mktemp)
    remove_alias_from_config_stream "$alias" < "$cfg" > "$tmp"
    if cmp -s "$cfg" "$tmp" 2>/dev/null; then
      rm -f "$tmp" 2>/dev/null || true
      continue
    fi
    changed=1
    any=1
    if [[ "$dry_run" -eq 1 ]]; then
      echo "[would-removed] $alias from $cfg"
      rm -f "$tmp" 2>/dev/null || true
      continue
    fi
    atomic_write_file "$tmp" "$cfg"
    rm -f "$tmp" 2>/dev/null || true
    echo "[removed] $alias from $cfg"
  done
  if [[ "${changed:-0}" -ne 1 && "$any" -eq 0 ]]; then
    echo "[skipped] alias '$alias' not found"
  fi
}

write_alias_stanza() {
  # args: config_path alias host user port identity identities_only dry_run yes
  local cfg="$1" alias="$2" host="$3" user="$4" port="$5" ident="$6" identities_only="$7" dry_run="$8" yes="$9"
  local have=0 existed=0
  if [[ -f "$cfg" ]]; then have=1; fi
  local tmp
  tmp=$(mktemp)
  if [[ $have -eq 1 ]]; then
    # Detect if alias exists as a discrete token on any Host line
    if awk -v target="$alias" 'BEGIN{found=0} /^Host[[:space:]]+/ {line=$0; sub(/^Host[[:space:]]+/,"",line); n=split(line,arr,/[[:space:]]+/); for(i=1;i<=n;i++){ if(arr[i]==target){ found=1 } }} END{ exit(found?0:1) }' "$cfg"; then
      existed=1
    fi
    remove_alias_from_config_stream "$alias" < "$cfg" > "$tmp"
  else
    # Seed with a header
    printf '# Created by ssherpa\n' > "$tmp"
  fi
  # Append stanza
  {
    printf '\nHost %s\n' "$alias"
    printf '  HostName %s\n' "$host"
    if [[ -n "$user" ]]; then printf '  User %s\n' "$user"; fi
    if [[ -n "$port" ]]; then printf '  Port %s\n' "$port"; fi
    if [[ -n "$ident" ]]; then printf '  IdentityFile %s\n' "$ident"; fi
    if [[ "${identities_only:-0}" -eq 1 ]]; then printf '  IdentitiesOnly yes\n'; fi
  } >> "$tmp"

  if [[ $dry_run -eq 1 ]]; then
    if [[ $existed -eq 1 ]]; then echo "[would-updated] $alias"; else echo "[would-added] $alias"; fi
    rm -f "$tmp" 2>/dev/null || true
    return 0
  fi
  atomic_write_file "$tmp" "$cfg"
  rm -f "$tmp" 2>/dev/null || true
  if [[ $existed -eq 1 ]]; then echo "[updated] $alias"; else echo "[added] $alias"; fi
}

suggest_alias_from_host() {
  # Convert host like db.example.com or 10.0.0.5 into db-example-com or 10-0-0-5
  local h="$1"
  printf '%s\n' "$h" | tr '[:upper:]' '[:lower:]' | sed -E -e 's/[^a-z0-9]+/-/g' -e 's/-{2,}/-/g' -e 's/^-+//' -e 's/-+$//'
}

list_private_keys() {
  local dir="$HOME/.ssh"
  local out=() f pub priv line seen=$'\n'
  [[ -d "$dir" ]] || { printf '%s\n' "${out[@]:-}"; return 0; }

  # Prefer any private key that has a matching valid .pub file.
  local oldshopt
  oldshopt=$(shopt -p nullglob || true)
  shopt -s nullglob
  for pub in "$dir"/*.pub; do
    [[ -f "$pub" ]] || continue
    line=""
    while IFS= read -r line || [[ -n "$line" ]]; do
      line=$(trim "$line")
      [[ -z "$line" ]] && continue
      break
    done < "$pub"
    [[ -n "$line" ]] || continue
    if authkeys_parse_pubkey_line "$line" && authkeys_validate_parsed_pubkey; then
      priv="${pub%.pub}"
      if [[ -f "$priv" ]]; then
        case "$seen" in *$'\n'"$priv"$'\n'*) : ;; *)
          out+=("$priv")
          seen+="$priv"$'\n'
        esac
      fi
    fi
  done

  # Fallback to legacy id_* scan if no pub-paired keys found.
  if [[ ${#out[@]} -eq 0 ]]; then
    for f in "$dir"/id_*; do
      [[ -e "$f" ]] || continue
      case "$f" in *.pub) continue ;; esac
      out+=("$f")
    done
  fi

  eval "$oldshopt" 2>/dev/null || true
  printf '%s\n' "${out[@]:-}"
}

ssherpa_add_flow() {
  # args: alias host user port identity config dry_run yes
  local alias="$1" host="$2" user="$3" port="$4" ident="$5" cfg="$6" dry_run="$7" yes="$8"
  local identities_only=0
  alt_screen_on
  clear_screen

  # Step 1: HostName
  while [[ -z "${host:-}" ]]; do
    clear_screen
    style_step "Step 1/5 — HostName"
    draw_rule
    style_hint "Enter the server hostname or IP (required)."
    host=$(gum input --placeholder "e.g., 10.0.0.5 or foo.example.com")
    [[ -n "$host" ]] || echo "Please provide a HostName." >&2
  done

  # Step 2: Alias
  local suggested; suggested=$(suggest_alias_from_host "$host")
  while [[ -z "${alias:-}" ]]; do
    clear_screen
    style_step "Step 2/5 — Alias"
    draw_rule
    style_hint "A short name you’ll use like: ssh <alias>."
    alias=$(gum input --placeholder "e.g., work-prod" --value "$suggested")
    # basic validation: no spaces
    if [[ -z "$alias" ]]; then echo "Alias cannot be empty." >&2; fi
    case "$alias" in *[[:space:]]*) echo "Alias cannot contain spaces." >&2; alias="" ;; esac
  done

  # Step 3: User (optional)
  if [[ -z "${user:-}" ]]; then
    clear_screen
    style_step "Step 3/5 — User (optional)"
    draw_rule
    style_hint "Leave blank to use your SSH config default or remote default user."
    user=$(gum input --placeholder "e.g., farmer (blank = default)")
  fi

  # Step 4: Port (optional)
  if [[ -z "${port:-}" ]]; then
    local valid=0 p
    while [[ $valid -eq 0 ]]; do
      clear_screen
      style_step "Step 4/5 — Port (optional)"
      draw_rule
      style_hint "Default is 22. Press Enter to accept."
      p=$(gum input --placeholder "Default: 22 (press Enter)" --value "22")
      if [[ -z "$p" ]]; then port=""; valid=1
      elif [[ "$p" =~ ^[0-9]+$ ]]; then port="$p"; valid=1
      else echo "Port must be digits only." >&2; fi
    done
  fi

  # Step 5: IdentityFile (optional)
  if [[ -z "${ident:-}" ]]; then
    clear_screen
    style_step "Step 5/5 — IdentityFile (optional)"
    draw_rule
    style_hint "Choose a key, type a path, or select None to skip."
    local sel
    if list_private_keys >/dev/null 2>&1 && [[ -n "$(list_private_keys)" ]]; then
      sel=$( { printf '%s\n' "None" "Other…"; list_private_keys; } | gum choose --header "IdentityFile (optional)") || sel="None"
      case "$sel" in
        "Other…") ident=$(gum input --placeholder "Path to private key (e.g., ~/.ssh/id_ed25519)") ;;
        "None") ident="" ;;
        *) ident="$sel" ;;
      esac
    else
      ident=$(gum input --placeholder "IdentityFile (optional)" --value "")
    fi
  fi

  # Optional: IdentitiesOnly when a key is set
  if [[ -n "$ident" ]]; then
    clear_screen
    style_step "IdentitiesOnly for this key?"
    draw_rule
    style_hint "IdentitiesOnly tells ssh to use only this key for this host,"
    style_hint "instead of trying every key in your agent (avoids 'too many auth failures')."
    if gum confirm "Add 'IdentitiesOnly yes' for '$alias'?"; then
      identities_only=1
    fi
  fi

  # Clear and show concise review + confirmation
  clear_screen
  style_step "Review"
  echo "Alias: $alias"
  echo "HostName: $host"
  [[ -n "$user" ]] && echo "User: $user" || echo "User: (default)"
  [[ -n "$port" ]] && echo "Port: $port" || echo "Port: (22 by default)"
  if [[ -n "$ident" ]]; then
    echo "IdentityFile: $ident"
    if [[ "$identities_only" -eq 1 ]]; then
      echo "IdentitiesOnly: yes"
    else
      echo "IdentitiesOnly: (no — other keys may still be tried)"
    fi
  else
    echo "IdentityFile: (none)"
  fi
  # Confirm path unless --yes
  if [[ "$yes" -ne 1 ]]; then
    gum confirm "Write to $(printf '%s' "${cfg:-$(config_path_default)}")?" || { echo "[skipped] cancelled"; alt_screen_off; return 0; }
  fi
  write_alias_stanza "${cfg:-$(config_path_default)}" "$alias" "$host" "$user" "$port" "$ident" "$identities_only" "$dry_run" "$yes"
  alt_screen_off
}

ssherpa_edit_alias_fields() {
  # args: alias host user port identity cfg_path
  local alias="$1" host="$2" user="$3" port="$4" ident="$5" cfg="$6"

  # Step 1: HostName (required)
  while true; do
    clear_screen
    style_step "Edit '$alias' — HostName"
    draw_rule
    style_hint "Update the server hostname or IP (required)."
    [[ -n "$host" ]] && style_hint "Current: $host"
    local new_host
    new_host=$(gum input --placeholder "e.g., 10.0.0.5 or foo.example.com" --value "$host")
    new_host=$(trim "${new_host:-}")
    if [[ -n "$new_host" ]]; then
      host="$new_host"
      break
    fi
    echo "HostName cannot be empty." >&2
  done

  # Step 2: User (optional)
  clear_screen
  style_step "Edit '$alias' — User (optional)"
  draw_rule
  if [[ -n "$user" ]]; then
    style_hint "Current user: $user (blank = default)."
  else
    style_hint "Leave blank to use your SSH default user."
  fi
  local new_user
  new_user=$(gum input --placeholder "e.g., farmer (blank = default)" --value "$user")
  user="${new_user:-}"

  # Step 3: Port (optional)
  while true; do
    clear_screen
    style_step "Edit '$alias' — Port (optional)"
    draw_rule
    if [[ -n "$port" ]]; then
      style_hint "Current port: $port (blank = default 22)."
    else
      style_hint "Default SSH port is 22. Press Enter to accept."
    fi
    local p
    p=$(gum input --placeholder "Default: 22 (press Enter)" --value "${port:-22}")
    if [[ -z "$p" ]]; then
      port=""
      break
    elif [[ "$p" =~ ^[0-9]+$ ]]; then
      port="$p"
      break
    else
      echo "Port must be digits only." >&2
    fi
  done

  # Step 4: IdentityFile (optional)
  clear_screen
  style_step "Edit '$alias' — IdentityFile (optional)"
  draw_rule
  if [[ -n "$ident" ]]; then
    style_hint "Current IdentityFile: $ident (blank = none)."
  else
    style_hint "Leave blank to keep using your default SSH key settings."
  fi
  local new_ident
  new_ident=$(gum input --placeholder "Path to private key (optional)" --value "$ident")
  ident="${new_ident:-}"

  # Review and confirm
  clear_screen
  style_step "Review changes for '$alias'"
  draw_rule
  echo "HostName: $host"
  [[ -n "$user" ]] && echo "User: $user" || echo "User: (default)"
  [[ -n "$port" ]] && echo "Port: $port" || echo "Port: (22 by default)"
  [[ -n "$ident" ]] && echo "IdentityFile: $ident" || echo "IdentityFile: (none)"
  local dest_cfg
  dest_cfg="${cfg:-$(config_path_default)}"
  style_hint "Target config: $dest_cfg"
  if ! gum confirm "Save changes to '$alias' in $dest_cfg?"; then
    echo "[skipped] edit cancelled"
    return 0
  fi

  # Remove any existing definitions, then write the updated stanza.
  delete_alias_everywhere "$alias" 0
  write_alias_stanza "$dest_cfg" "$alias" "$host" "$user" "$port" "$ident" 0 0 1
}

ssherpa_edit_single_alias() {
  # args: include_patterns filter_user prefilter no_color cfg_path alias
  local include_patterns="$1" filter_user="$2" prefilter="$3" no_color="$4" cfg_path="$5" alias="$6"
  local idx=-1 i
  for i in "${!NAMES[@]}"; do
    if [[ "${NAMES[$i]}" == "$alias" ]]; then
      idx="$i"
      break
    fi
  done
  if [[ "$idx" -lt 0 ]]; then
    clear_screen
    style_step "Edit mode"
    draw_rule
    echo_err "Alias '$alias' not found."
    return 0
  fi

  local host="${HOSTS[$idx]}" user="${USERS[$idx]}" port="${PORTS[$idx]}" ident="${KEYS[$idx]}"

  while true; do
    clear_screen
    style_step "Edit alias '$alias'"
    draw_rule
    echo "HostName: ${host:-"(none)"}"
    [[ -n "$user" ]] && echo "User: $user" || echo "User: (default)"
    [[ -n "$port" ]] && echo "Port: $port" || echo "Port: (22 by default)"
    [[ -n "$ident" ]] && echo "IdentityFile: $ident" || echo "IdentityFile: (none)"
    draw_rule
    local action
    action=$(printf '%s\n' \
      "Change host/user/port/identity" \
      "Delete this alias" \
      "Back" | gum choose --header "Choose action for '$alias'") || return 0
    case "$action" in
      "Change host/user/port/identity")
        ssherpa_edit_alias_fields "$alias" "$host" "$user" "$port" "$ident" "$cfg_path"
        return 0
        ;;
      "Delete this alias")
        if gum confirm "Delete alias '$alias' from all loaded SSH configs?"; then
          delete_alias_everywhere "$alias" 0
        else
          echo "[skipped] delete cancelled"
        fi
        return 0
        ;;
      "Back")
        return 0
        ;;
    esac
  done
}

ssherpa_edit_mode() {
  # args: include_patterns filter_user prefilter no_color cfg_path
  local include_patterns="$1" filter_user="$2" prefilter="$3" no_color="$4" cfg_path="$5"

  alt_screen_on
  clear_screen

  # Build alias list (same presets as main view), then drop synthetic rows.
  build_alias_lines "$include_patterns" "$filter_user" "$prefilter" "$no_color"
  local alias_lines=() l token
  for l in "${LINES[@]:-}"; do
    token=$(printf '%s' "$l" | awk -F '\t' '{print $1}')
    case "$token" in
      ADD|EDIT|AUTHKEYS|PROXY|JUMP) continue ;;
    esac
    alias_lines+=("$l")
  done

  if [[ ${#alias_lines[@]} -eq 0 ]]; then
    alt_screen_off
    echo "[skipped] no aliases available to edit"
    return 0
  fi

  # Create an edit list with a quick "delete all" row.
  local edit_lines=()
  edit_lines+=("DELETE_ALL"$'\t'"🗑 Delete ALL listed aliases…")
  for l in "${alias_lines[@]}"; do
    edit_lines+=("$l")
  done

  clear_screen
  style_step "Edit mode — pick alias or Delete ALL"
  draw_rule
  style_hint "Select an alias to edit/delete, or Delete ALL presets."
  local chosen
  chosen=$(printf '%s\n' "${edit_lines[@]}" | gum filter --placeholder "Filter SSH aliases…" --header "Edit mode — pick alias or Delete ALL" --limit 1)
  if [[ -z "$chosen" ]]; then
    alt_screen_off
    echo "[skipped] edit cancelled"
    return 0
  fi

  token=$(printf '%s' "$chosen" | awk -F '\t' '{print $1}')
  case "$token" in
    DELETE_ALL)
      # Collect all aliases currently listed (respecting filters).
      local to_delete=() line alias
      for line in "${alias_lines[@]}"; do
        alias=$(printf '%s' "$line" | awk -F '\t' '{print $1}')
        to_delete+=("$alias")
      done
      clear_screen
      style_step "Delete ALL presets"
      draw_rule
      style_hint "This will delete ${#to_delete[@]} aliases from your SSH config(s)."
      if gum confirm "Really delete ALL listed aliases?"; then
        local a
        for a in "${to_delete[@]}"; do
          delete_alias_everywhere "$a" 0
        done
        alt_screen_off
        echo "[removed] ${#to_delete[@]} aliases"
        return 0
      else
        alt_screen_off
        echo "[skipped] delete-all cancelled"
        return 0
      fi
      ;;
    *)
      local alias
      alias="$token"
      ssherpa_edit_single_alias "$include_patterns" "$filter_user" "$prefilter" "$no_color" "$cfg_path" "$alias"
      alt_screen_off
      return 0
      ;;
  esac
}

ssherpa_jump_flow() {
  # args: include_patterns filter_user prefilter no_color do_print do_exec ssh_args...
  local include_patterns="$1" filter_user="$2" prefilter="$3" no_color="$4" do_print="$5" do_exec="$6"
  shift 6
  local jump_ssh_args=("$@")

  alt_screen_on
  clear_screen

  # Build a fresh alias list with current filters, then drop synthetic rows.
  build_alias_lines "$include_patterns" "$filter_user" "$prefilter" "$no_color"
  local alias_lines=() l token
  for l in "${LINES[@]:-}"; do
    token=$(printf '%s' "$l" | awk -F '\t' '{print $1}')
    case "$token" in
      ADD|EDIT|AUTHKEYS|PROXY|JUMP) continue ;;
    esac
    alias_lines+=("$l")
  done

  if [[ ${#alias_lines[@]} -eq 0 ]]; then
    alt_screen_off
    echo "[skipped] no aliases available for jump"
    return 0
  fi

  # Step 1: pick destination
  local dest_line dest_token dest_display
  while true; do
    clear_screen
    style_step "Jump mode — destination"
    draw_rule
    style_hint "Pick the final destination host."
    dest_line=$(printf '%s\n' "${alias_lines[@]}" | gum filter --placeholder "Filter destination…" --header "Jump mode — destination" --limit 1) || {
      alt_screen_off
      echo "[skipped] jump cancelled (destination)"
      return 0
    }
    [[ -n "$dest_line" ]] || continue
    dest_token=$(printf '%s' "$dest_line" | awk -F '\t' '{print $1}')
    dest_display=$(printf '%s' "$dest_line" | awk -F '\t' '{print $2}')
    break
  done

  # Step 2: pick the first hop
  local hops=()
  local first_choices=() line
  for line in "${alias_lines[@]}"; do
    token=$(printf '%s' "$line" | awk -F '\t' '{print $1}')
    [[ "$token" == "$dest_token" ]] && continue
    first_choices+=("$line")
  done

  if [[ ${#first_choices[@]} -eq 0 ]]; then
    alt_screen_off
    echo "[skipped] not enough distinct hosts for a jump"
    return 0
  fi

  local hop_line hop_token
  while true; do
    clear_screen
    style_step "Jump mode — first hop"
    draw_rule
    style_hint "Pick the first hop before '$dest_token'."
    hop_line=$(printf '%s\n' "${first_choices[@]}" | gum filter --placeholder "Filter first hop…" --header "Pick first hop" --limit 1) || {
      alt_screen_off
      echo "[skipped] jump cancelled (first hop)"
      return 0
    }
    [[ -n "$hop_line" ]] || continue
    hop_token=$(printf '%s' "$hop_line" | awk -F '\t' '{print $1}')
    break
  done
  hops+=("$hop_token")

  # Step 3: optionally add more hops, with ALL DONE as a top choice
  while true; do
    clear_screen
    style_step "Jump mode — hops"
    draw_rule
    style_hint "Route so far:"
    local path=""
    local h
    for h in "${hops[@]}"; do
      if [[ -n "$path" ]]; then
        path+=" → "
      fi
      path+="$h"
    done
    path+=" → $dest_token"
    printf '%s\n' "$path"
    draw_rule
    style_hint "Pick another hop, or choose ALL DONE to connect."

    # Choices for next hop: all aliases except destination + previously chosen hops.
    local choices=()
    for line in "${alias_lines[@]}"; do
      token=$(printf '%s' "$line" | awk -F '\t' '{print $1}')
      # Skip destination
      if [[ "$token" == "$dest_token" ]]; then continue; fi
      # Skip already chosen hops
      local skip=0 h2
      for h2 in "${hops[@]}"; do
        if [[ "$h2" == "$token" ]]; then
          skip=1
          break
        fi
      done
      [[ $skip -eq 1 ]] && continue
      choices+=("$line")
    done

    local menu_lines=()
    menu_lines+=("DONE"$'\t'"ALL DONE — connect using route above")
    local c
    for c in "${choices[@]}"; do
      menu_lines+=("$c")
    done

    hop_line=$(printf '%s\n' "${menu_lines[@]}" | gum filter --placeholder "Filter hops or ALL DONE…" --header "Pick next hop or ALL DONE" --limit 1) || {
      alt_screen_off
      echo "[skipped] jump cancelled (additional hops)"
      return 0
    }
    [[ -n "$hop_line" ]] || continue
    hop_token=$(printf '%s' "$hop_line" | awk -F '\t' '{print $1}')
    if [[ "$hop_token" == "DONE" ]]; then
      break
    fi
    hops+=("$hop_token")
  done

  # Step 4: review and execute/print
  clear_screen
  style_step "Jump mode — review"
  draw_rule
  local summary=""
  local h3
  for h3 in "${hops[@]}"; do
    if [[ -n "$summary" ]]; then
      summary+=" → "
    fi
    summary+="$h3"
  done
  summary+=" → $dest_token"
  printf 'Route: %s\n' "$summary"
  draw_rule

  # Build ProxyJump argument
  local jump_arg=""
  local first=1
  for h3 in "${hops[@]}"; do
    if [[ $first -eq 1 ]]; then
      jump_arg="$h3"
      first=0
    else
      jump_arg+=",$h3"
    fi
  done

  if [[ "$do_print" -eq 1 ]]; then
    alt_screen_off
    if [[ -n "$jump_arg" ]]; then
      echo "[print] ssh -J $jump_arg $dest_token${jump_ssh_args:+ }${jump_ssh_args[*]:-}"
    else
      echo "[print] ssh $dest_token${jump_ssh_args:+ }${jump_ssh_args[*]:-}"
    fi
    return 0
  fi

  if [[ "$do_exec" -eq 1 ]]; then
    alt_screen_off
    if [[ -n "$jump_arg" ]]; then
      echo "[exec] ssh -J $jump_arg $dest_token${jump_ssh_args:+ }${jump_ssh_args[*]:-}"
      exec ssh -J "$jump_arg" "$dest_token" "${jump_ssh_args[@]:-}"
    else
      echo "[exec] ssh $dest_token${jump_ssh_args:+ }${jump_ssh_args[*]:-}"
      exec ssh "$dest_token" "${jump_ssh_args[@]:-}"
    fi
  fi

  alt_screen_off
}

ssherpa_proxy_flow() {
  # SOCKS proxy helper that reuses the regular alias list.
  # Args: include_patterns filter_user prefilter no_color ssh_args...
  local include_patterns="$1" filter_user="$2" prefilter="$3" no_color="$4"
  shift 4
  local ssh_args=("$@")
  local default_port="1080"
  local port
  while :; do
    port=$(gum input --placeholder "Local SOCKS proxy port (default 1080)")
    [[ -z "${port:-}" ]] && port="$default_port"
    if [[ "$port" =~ ^[0-9]+$ ]]; then
      break
    fi
    gum style --foreground 196 "Port must be digits only."
  done

  # Build alias list (same presets as main view), then drop synthetic rows.
  build_alias_lines "$include_patterns" "$filter_user" "$prefilter" "$no_color"
  local alias_lines=() l token
  for l in "${LINES[@]:-}"; do
    token=$(printf '%s' "$l" | awk -F '\t' '{print $1}')
    case "$token" in
      ADD|EDIT|AUTHKEYS|PROXY|JUMP) continue ;;
    esac
    alias_lines+=("$l")
  done

  if [[ ${#alias_lines[@]} -eq 0 ]]; then
    gum style --foreground 196 "No aliases available for proxy."
    return 0
  fi

  # Let the user pick which alias will run the SOCKS proxy.
  local chosen alias display
  while :; do
    chosen=$(printf '%s\n' "${alias_lines[@]}" | gum filter --placeholder "Filter SSH aliases…" --header "Pick host for SOCKS proxy" --limit 1) || {
      printf '%s\n' "[skipped] proxy cancelled"
      return 0
    }
    [[ -n "$chosen" ]] || continue
    alias=$(printf '%s' "$chosen" | awk -F '\t' '{print $1}')
    display=$(printf '%s' "$chosen" | awk -F '\t' '{print $2}')
    break
  done

  local remote="$alias"

  gum style --bold --foreground 212 "Starting SSH SOCKS proxy"
  gum style --faint "Command: ssh -D $port -C -N $remote${ssh_args:+ }${ssh_args[*]:-}"
  gum style --faint "Press Ctrl-C to stop the proxy."

  # After SSH successfully connects, run a local gum command to announce it.
  local local_cmd
  local_cmd="gum style --foreground 46 'Proxy connected on port $port.'"

  exec ssh -oPermitLocalCommand=yes -oLocalCommand="$local_cmd" -D "$port" -C -N "$remote" "${ssh_args[@]:-}"
}

authorized_keys_path_default() {
  if [[ -n "${SSHERPA_AUTHORIZED_KEYS_PATH:-}" ]]; then
    printf '%s\n' "$SSHERPA_AUTHORIZED_KEYS_PATH"
  else
    printf '%s\n' "$HOME/.ssh/authorized_keys"
  fi
}

authkeys_parse_pubkey_line() {
  # Input: single authorized_keys / .pub line.
  # Output globals (on success): PUBKEY_TYPE, PUBKEY_DATA, PUBKEY_COMMENT, PUBKEY_FP.
  local line="$1"
  line=$(trim "$line")
  [[ -z "$line" ]] && return 1
  case "$line" in
    \#*) return 1 ;;
  esac
  local words=()
  IFS=' ' read -r -a words <<<"$line"
  local n=${#words[@]}
  [[ $n -lt 2 ]] && return 1
  local i w key_type="" key_data="" comment=""
  for ((i=0; i<n; i++)); do
    w=${words[$i]}
    case "$w" in
      ssh-rsa|ssh-ed25519|ssh-dss|ecdsa-sha2-*|sk-ssh-ed25519@openssh.com|sk-ecdsa-sha2-nistp256@openssh.com)
        key_type="$w"
        if (( i + 1 < n )); then
          key_data="${words[$((i+1))]}"
        fi
        if (( i + 2 < n )); then
          comment="${words[*]:$((i+2))}"
        fi
        break
        ;;
    esac
  done
  if [[ -z "$key_type" || -z "$key_data" ]]; then
    return 1
  fi
  PUBKEY_TYPE="$key_type"
  PUBKEY_DATA="$key_data"
  PUBKEY_COMMENT="$comment"
  PUBKEY_FP="$PUBKEY_TYPE $PUBKEY_DATA"
  return 0
}

authkeys_validate_parsed_pubkey() {
  # Uses ssh-keygen when available; falls back to structural checks only.
  if ! command -v ssh-keygen >/dev/null 2>&1; then
    return 0
  fi
  local line="$PUBKEY_TYPE $PUBKEY_DATA"
  if [[ -n "${PUBKEY_COMMENT:-}" ]]; then
    line+=" $PUBKEY_COMMENT"
  fi
  printf '%s\n' "$line" | ssh-keygen -lf - >/dev/null 2>&1
}

authkeys_fp_in_array() {
  # args: needle list...
  local needle="$1" x
  shift || true
  for x in "$@"; do
    [[ "$x" == "$needle" ]] && return 0
  done
  return 1
}

authkeys_load_existing_fps() {
  # args: path
  local path="$1" line
  AUTHKEYS_EXISTING_FP=()
  [[ -f "$path" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    if authkeys_parse_pubkey_line "$line"; then
      AUTHKEYS_EXISTING_FP+=("$PUBKEY_FP")
    fi
  done < "$path"
}

authkeys_collect_from_dir() {
  # args: dir
  local dir="$1"
  AUTHKEYS_DIR_LINES=()
  AUTHKEYS_DIR_FP=()
  AUTHKEYS_DIR_SOURCE=()
  AUTHKEYS_DIR_TOTAL=0
  AUTHKEYS_DIR_INVALID=0
  AUTHKEYS_DIR_DUPLICATE=0

  local special="$dir/authorized_keys"
  local files=() f
  if [[ -d "$special" ]]; then
    for f in "$special"/*; do
      [[ -f "$f" ]] || continue
      files+=("$f")
    done
  else
    for f in "$dir"/*.pub; do
      [[ -f "$f" ]] || continue
      files+=("$f")
    done
  fi

  if [[ ${#files[@]} -eq 0 ]]; then
    return 1
  fi

  local line fp normalized exists
  for f in "${files[@]}"; do
    while IFS= read -r line || [[ -n "$line" ]]; do
      line=$(trim "$line")
      [[ -z "$line" ]] && continue
      if ! authkeys_parse_pubkey_line "$line"; then
        AUTHKEYS_DIR_INVALID=$((AUTHKEYS_DIR_INVALID+1))
        continue
      fi
      if ! authkeys_validate_parsed_pubkey; then
        AUTHKEYS_DIR_INVALID=$((AUTHKEYS_DIR_INVALID+1))
        continue
      fi
      fp="$PUBKEY_FP"
      exists=0
      if authkeys_fp_in_array "$fp" "${AUTHKEYS_DIR_FP[@]:-}"; then
        AUTHKEYS_DIR_DUPLICATE=$((AUTHKEYS_DIR_DUPLICATE+1))
        continue
      fi
      normalized="$PUBKEY_TYPE $PUBKEY_DATA"
      if [[ -n "${PUBKEY_COMMENT:-}" ]]; then
        normalized+=" $PUBKEY_COMMENT"
      fi
      AUTHKEYS_DIR_LINES+=("$normalized")
      AUTHKEYS_DIR_FP+=("$fp")
      AUTHKEYS_DIR_SOURCE+=("$f")
      AUTHKEYS_DIR_TOTAL=$((AUTHKEYS_DIR_TOTAL+1))
    done < "$f"
  done
  return 0
}

authkeys_ensure_permissions() {
  local path="$1"
  chmod 600 "$path" 2>/dev/null || chmod 644 "$path" 2>/dev/null || true
}

authkeys_dir_has_keys() {
  # args: dir
  local dir="$1" special f
  special="$dir/authorized_keys"
  if [[ -d "$special" ]]; then
    for f in "$special"/*; do
      [[ -f "$f" ]] || continue
      return 0
    done
  fi
  for f in "$dir"/*.pub; do
    [[ -f "$f" ]] || continue
    return 0
  done
  return 1
}

ssherpa_authkeys_prompt_dir() {
  # Sets AUTHKEYS_PROMPT_DIR_RESULT on success.
  local title="$1" current dir
  current="${AUTHKEYS_LAST_DIR:-${PWD:-$HOME}}"

  # If we're already in a folder with keys, offer to use it immediately.
  if authkeys_dir_has_keys "$current"; then
    clear_screen
    style_step "$title"
    draw_rule
    style_hint "Directory contains SSH public keys or authorized_keys files:"
    echo "  $current"
    if gum confirm "Use this folder for authorized_keys operations?"; then
      AUTHKEYS_LAST_DIR="$current"
      AUTHKEYS_PROMPT_DIR_RESULT="$current"
      return 0
    fi
    # If no, fall through into directory navigation below.
  fi
  while :; do
    clear_screen
    style_step "$title"
    draw_rule
    style_hint "Current directory:"
    echo "  $current"
    draw_rule
    style_hint "Pick a folder. If it contains SSH .pub keys or an authorized_keys"
    style_hint "subfolder, you'll be asked to confirm it as the key source."

    local entries=() labels=() line idx choice

    # Navigation: parent
    if [[ "$current" != "/" ]]; then
      entries+=("..")
      labels+=(".. (up one level)")
    fi

    # Subdirectories
    local d base
    for d in "$current"/*; do
      [[ -d "$d" ]] || continue
      base=$(basename "$d")
      labels+=("$base/")
      entries+=("$d")
    done

    if [[ ${#entries[@]} -eq 0 ]]; then
      if authkeys_dir_has_keys "$current"; then
        style_hint "No subdirectories, but this folder contains SSH keys."
        if gum confirm "Use $current as the key folder?"; then
          AUTHKEYS_LAST_DIR="$current"
          AUTHKEYS_PROMPT_DIR_RESULT="$current"
          return 0
        fi
      fi
      echo "[skipped] no subdirectories or SSH key files found under $current"
      return 1
    fi

    local menu_lines=()
    for idx in "${!entries[@]}"; do
      menu_lines+=("$idx"$'\t'"${labels[$idx]}")
    done

    choice=$(printf '%s\n' "${menu_lines[@]}" | gum choose --header "Navigate to a folder with SSH keys") || {
      echo "[skipped] no directory selected"
      return 1
    }
    [[ -z "$choice" ]] && continue
    idx=$(printf '%s' "$choice" | awk -F '\t' '{print $1}')
    dir="${entries[$idx]}"

    if [[ "$dir" == ".." ]]; then
      current=$(dirname "$current")
      continue
    fi

    if authkeys_dir_has_keys "$dir"; then
      clear_screen
      style_step "$title"
      draw_rule
      style_hint "Directory contains SSH public keys or authorized_keys files:"
      echo "  $dir"
      if gum confirm "Use this folder for authorized_keys operations?"; then
        AUTHKEYS_LAST_DIR="$dir"
        AUTHKEYS_PROMPT_DIR_RESULT="$dir"
        return 0
      fi
      # Treat as navigation on cancel
      current="$dir"
      continue
    fi

    # No keys here; treat as navigation and re-render.
    current="$dir"
  done
}

ssherpa_authkeys_add_single() {
  local auth_path="$1"
  while :; do
    clear_screen
    style_step "authorized_keys — add a single key"
    draw_rule
    style_hint "Paste a single SSH public key line (ssh-ed25519, ssh-rsa, ecdsa…)."
    style_hint "Example: ssh-ed25519 AAAAC3... you@device"
    local line
    line=$(gum input --placeholder "ssh-ed25519 AAAAC3... you@device")
    line=$(trim "${line:-}")
    if [[ -z "$line" ]]; then
      echo "[skipped] empty key; nothing added"
      gum input --placeholder "Press Enter to return to menu" >/dev/null 2>&1 || true
      return 0
    fi
    if ! authkeys_parse_pubkey_line "$line"; then
      gum style --foreground 196 "Not a recognized SSH public key line."
      if gum confirm "Try again?"; then
        continue
      fi
      return 0
    fi
    authkeys_validate_parsed_pubkey || gum style --foreground 214 "Key did not fully validate; format looks like an SSH key."
    authkeys_load_existing_fps "$auth_path"
    if authkeys_fp_in_array "$PUBKEY_FP" "${AUTHKEYS_EXISTING_FP[@]:-}"; then
      clear_screen
      style_step "authorized_keys — add a single key"
      draw_rule
      echo "[up-to-date] Key already present in $(authorized_keys_path_default)"
      gum input --placeholder "Press Enter to return to menu" >/dev/null 2>&1 || true
      return 0
    fi
    local normalized="$PUBKEY_TYPE $PUBKEY_DATA"
    if [[ -n "${PUBKEY_COMMENT:-}" ]]; then
      normalized+=" $PUBKEY_COMMENT"
    fi
    local tmp
    tmp=$(mktemp)
    if [[ -f "$auth_path" ]]; then
      cp "$auth_path" "$tmp"
    else
      mkdir -p "$(dirname "$auth_path")"
      printf '# Created by ssherpa authkeys\n' > "$tmp"
    fi
    printf '%s\n' "$normalized" >> "$tmp"
    atomic_write_file "$tmp" "$auth_path"
    rm -f "$tmp" 2>/dev/null || true
    authkeys_ensure_permissions "$auth_path"
    clear_screen
    style_step "authorized_keys — add a single key"
    draw_rule
    echo "[added] 1 key to $auth_path"
    gum input --placeholder "Press Enter to return to menu" >/dev/null 2>&1 || true
    return 0
  done
}

ssherpa_authkeys_add_from_dir() {
  local auth_path="$1"
  if ! ssherpa_authkeys_prompt_dir "authorized_keys — add from directory (merge)"; then
    return 0
  fi
  local dir="$AUTHKEYS_PROMPT_DIR_RESULT"
  if ! authkeys_collect_from_dir "$dir"; then
    clear_screen
    style_step "authorized_keys — add from directory"
    draw_rule
    echo "[skipped] No authorized_keys subfolder or *.pub files found in $dir"
    gum input --placeholder "Press Enter to return to menu" >/dev/null 2>&1 || true
    return 0
  fi
  authkeys_load_existing_fps "$auth_path"
  local new_lines=() line fp
  local i
  for i in "${!AUTHKEYS_DIR_LINES[@]}"; do
    fp="${AUTHKEYS_DIR_FP[$i]}"
    line="${AUTHKEYS_DIR_LINES[$i]}"
    if authkeys_fp_in_array "$fp" "${AUTHKEYS_EXISTING_FP[@]:-}"; then
      continue
    fi
    new_lines+=("$line")
  done
  if [[ ${#new_lines[@]} -eq 0 ]]; then
    clear_screen
    style_step "authorized_keys — add from directory"
    draw_rule
    echo "[up-to-date] All keys from $dir are already present in $auth_path"
    gum input --placeholder "Press Enter to return to menu" >/dev/null 2>&1 || true
    return 0
  fi
  local tmp
  tmp=$(mktemp)
  if [[ -f "$auth_path" ]]; then
    cp "$auth_path" "$tmp"
  else
    mkdir -p "$(dirname "$auth_path")"
    printf '# Created by ssherpa authkeys\n' > "$tmp"
  fi
  for line in "${new_lines[@]}"; do
    printf '%s\n' "$line" >> "$tmp"
  done
  atomic_write_file "$tmp" "$auth_path"
  rm -f "$tmp" 2>/dev/null || true
  authkeys_ensure_permissions "$auth_path"
  clear_screen
  style_step "authorized_keys — add from directory"
  draw_rule
  echo "[added] ${#new_lines[@]} new key(s) into $auth_path from $dir"
  gum input --placeholder "Press Enter to return to menu" >/dev/null 2>&1 || true
}

ssherpa_authkeys_replace_from_dir() {
  local auth_path="$1"
  if ! ssherpa_authkeys_prompt_dir "authorized_keys — replace from directory (overwrite)"; then
    return 0
  fi
  local dir="$AUTHKEYS_PROMPT_DIR_RESULT"
  if ! authkeys_collect_from_dir "$dir"; then
    clear_screen
    style_step "authorized_keys — replace from directory"
    draw_rule
    echo "[skipped] No authorized_keys subfolder or *.pub files found in $dir"
    gum input --placeholder "Press Enter to return to menu" >/dev/null 2>&1 || true
    return 0
  fi
  clear_screen
  style_step "authorized_keys — replace from directory"
  draw_rule
  style_hint "This will overwrite $(authorized_keys_path_default) with keys from:"
  echo "  $dir"
  echo
  echo "Valid keys discovered: $AUTHKEYS_DIR_TOTAL"
  echo "Invalid/ignored lines: $AUTHKEYS_DIR_INVALID"
  echo "Duplicates (within dir): $AUTHKEYS_DIR_DUPLICATE"
  echo
  if ! gum confirm "Replace all entries in $(authorized_keys_path_default) with these keys?"; then
    echo "[skipped] replace cancelled"
    gum input --placeholder "Press Enter to return to menu" >/dev/null 2>&1 || true
    return 0
  fi
  local tmp
  tmp=$(mktemp)
  mkdir -p "$(dirname "$auth_path")"
  printf '# Managed by ssherpa authkeys — replaced from directory\n' > "$tmp"
  local line
  for line in "${AUTHKEYS_DIR_LINES[@]}"; do
    printf '%s\n' "$line" >> "$tmp"
  done
  atomic_write_file "$tmp" "$auth_path"
  rm -f "$tmp" 2>/dev/null || true
  authkeys_ensure_permissions "$auth_path"
  clear_screen
  style_step "authorized_keys — replace from directory"
  draw_rule
  echo "[replaced] Wrote ${#AUTHKEYS_DIR_LINES[@]} key(s) to $auth_path from $dir"
  gum input --placeholder "Press Enter to return to menu" >/dev/null 2>&1 || true
}

authkeys_scan_for_delete() {
  # args: path
  local path="$1" line
  AUTHKEYS_ALL_LINES=()
  AUTHKEYS_KEY_IDX=()
  AUTHKEYS_KEY_DISPLAY=()
  [[ -f "$path" ]] || return 1
  local lineno=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    AUTHKEYS_ALL_LINES+=("$line")
    if authkeys_parse_pubkey_line "$line"; then
      local short="${PUBKEY_DATA:0:16}"
      local disp="$PUBKEY_TYPE $short…"
      if [[ -n "${PUBKEY_COMMENT:-}" ]]; then
        disp+=" ($PUBKEY_COMMENT)"
      fi
      AUTHKEYS_KEY_IDX+=("$lineno")
      AUTHKEYS_KEY_DISPLAY+=("$disp")
    fi
    lineno=$((lineno+1))
  done < "$path"
  [[ ${#AUTHKEYS_KEY_IDX[@]} -gt 0 ]]
}

ssherpa_authkeys_delete_keys() {
  local auth_path="$1"
  if ! authkeys_scan_for_delete "$auth_path"; then
    clear_screen
    style_step "authorized_keys — delete entries"
    draw_rule
    echo "[skipped] No authorized_keys file or no keys found at $auth_path"
    gum input --placeholder "Press Enter to return to menu" >/dev/null 2>&1 || true
    return 0
  fi
  local menu_lines=() i
  for i in "${!AUTHKEYS_KEY_IDX[@]}"; do
    menu_lines+=("$i"$'\t'"${AUTHKEYS_KEY_DISPLAY[$i]}")
  done
  menu_lines+=("BACK"$'\t'"Back without deleting")

  clear_screen
  style_step "authorized_keys — delete entries"
  draw_rule
  style_hint "Select one or more keys to remove from $(authorized_keys_path_default)."
  style_hint "Space toggles, Enter confirms."
  local selection
  selection=$(printf '%s\n' "${menu_lines[@]}" | gum choose --no-limit --header "Select keys to delete") || {
    echo "[skipped] delete cancelled"
    gum input --placeholder "Press Enter to return to menu" >/dev/null 2>&1 || true
    return 0
  }
  local sel_indices=() line token
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    token=$(printf '%s' "$line" | awk -F '\t' '{print $1}')
    if [[ "$token" == "BACK" ]]; then
      sel_indices=()
      break
    fi
    sel_indices+=("$token")
  done <<<"$selection"
  if [[ ${#sel_indices[@]} -eq 0 ]]; then
    echo "[skipped] no keys selected for delete"
    gum input --placeholder "Press Enter to return to menu" >/dev/null 2>&1 || true
    return 0
  fi

  local chosen_lines=() idx
  for idx in "${sel_indices[@]}"; do
    chosen_lines+=("${AUTHKEYS_KEY_IDX[$idx]}")
  done

  local tmp
  tmp=$(mktemp)
  local total=${#AUTHKEYS_ALL_LINES[@]}
  local ln i2 skip lno
  lno=0
  for ((i2=0; i2<total; i2++)); do
    skip=0
    for ln in "${chosen_lines[@]}"; do
      if [[ "$lno" -eq "$ln" ]]; then
        skip=1
        break
      fi
    done
    if [[ $skip -eq 0 ]]; then
      printf '%s\n' "${AUTHKEYS_ALL_LINES[$i2]}" >> "$tmp"
    fi
    lno=$((lno+1))
  done
  atomic_write_file "$tmp" "$auth_path"
  rm -f "$tmp" 2>/dev/null || true
  authkeys_ensure_permissions "$auth_path"
  clear_screen
  style_step "authorized_keys — delete entries"
  draw_rule
  echo "[removed] ${#chosen_lines[@]} key(s) from $auth_path"
  gum input --placeholder "Press Enter to return to menu" >/dev/null 2>&1 || true
}

ssherpa_authkeys_menu() {
  local auth_path
  auth_path=$(authorized_keys_path_default)
  alt_screen_on
  while :; do
    clear_screen
    style_step "authorized_keys manager"
    draw_rule
    style_hint "File: $auth_path"
    style_hint "Manage which SSH keys can log into this device."
    local choice
    choice=$(printf '%s\n' \
      "Add single key (paste)" \
      "Add keys from directory (merge)" \
      "Replace keys from directory (overwrite)" \
      "Delete keys" \
      "Back" | gum choose --header "authorized_keys manager") || {
      alt_screen_off
      echo "[skipped] authkeys cancelled"
      return 0
    }
    case "$choice" in
      "Add single key (paste)")
        ssherpa_authkeys_add_single "$auth_path"
        ;;
      "Add keys from directory (merge)")
        ssherpa_authkeys_add_from_dir "$auth_path"
        ;;
      "Replace keys from directory (overwrite)")
        ssherpa_authkeys_replace_from_dir "$auth_path"
        ;;
      "Delete keys")
        ssherpa_authkeys_delete_keys "$auth_path"
        ;;
      "Back")
        alt_screen_off
        return 0
        ;;
    esac
  done
}

main() {
  local sub=""
  if [[ $# -gt 0 ]]; then
    case "$1" in
      add|edit|authkeys) sub="$1"; shift ;;
    esac
  fi
  local include_patterns=0 do_print=0 do_exec=1 filter_user="" no_color=0 prefilter="" cfg_path="" ssh_args=()
  local alias="" host="" user="" port="" ident="" dry_run=0 yes=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --all) include_patterns=1; shift ;;
      --print) do_print=1; do_exec=0; shift ;;
      --exec) do_exec=1; do_print=0; shift ;;
      --filter) prefilter="$2"; shift 2 ;;
      --filter=*) prefilter="${1#*=}"; shift ;;
      --user) filter_user="$2"; shift 2 ;;
      --user=*) filter_user="${1#*=}"; shift ;;
      --no-color) no_color=1; shift ;;
      --config) cfg_path="$2"; shift 2 ;;
      --config=*) cfg_path="${1#*=}"; shift ;;
      # add-subcommand flags
      --alias) alias="$2"; shift 2 ;;
      --alias=*) alias="${1#*=}"; shift ;;
      --host) host="$2"; shift 2 ;;
      --host=*) host="${1#*=}"; shift ;;
      --port) port="$2"; shift 2 ;;
      --port=*) port="${1#*=}"; shift ;;
      --identity) ident="$2"; shift 2 ;;
      --identity=*) ident="${1#*=}"; shift ;;
      --dry-run) dry_run=1; shift ;;
      --yes|-y) yes=1; shift ;;
      --help|-h) print_usage; exit 0 ;;
      --) shift; while [[ $# -gt 0 ]]; do ssh_args+=("$1"); shift; done; break ;;
      --*) echo_err "Unknown flag: $1"; print_usage; exit 1 ;;
      *) ssh_args+=("$1"); shift ;;
    esac
  done

  if [[ "$sub" == "authkeys" ]]; then
    ensure_gum || exit 1
    ssherpa_authkeys_menu
    exit 0
  fi

  ensure_gum || exit 1

  # Load config (used by both main and edit flows)
  load_config_files
  [[ -n "${cfg_path:-}" ]] && CONFIG_FILES=("$cfg_path")
  parse_configs

  if [[ "$sub" == "add" ]]; then
    ssherpa_add_flow "$alias" "$host" "$user" "$port" "$ident" "${cfg_path:-}" "$dry_run" "$yes"
    exit 0
  fi

  if [[ "$sub" == "edit" ]]; then
    ssherpa_edit_mode "$include_patterns" "$filter_user" "$prefilter" "$no_color" "${cfg_path:-}"
    exit 0
  fi

  # Build selection list (aliases only + synthetic add row)
  build_alias_lines "$include_patterns" "$filter_user" "$prefilter" "$no_color"
  local acount=${#NAMES[@]} line_count=${#LINES[@]}
  echo "[loaded] $acount aliases"

  # If there are zero aliases, present starter options: Add, Learn more, Exit
  if [[ $acount -eq 0 ]]; then
    while true; do
      local choice
      choice=$(printf '%s\n' "Add alias" "Manage authorized_keys" "Learn more" "Exit" | gum choose --header "No SSH aliases found") || { echo "[skipped] no selection made"; exit 0; }
      case "$choice" in
        "Add alias")
          ssherpa_add_flow "" "" "" "" "" "${cfg_path:-}" 0 0
          exit 0
          ;;
        "Manage authorized_keys")
          ssherpa_authkeys_menu
          exit 0
          ;;
        "Learn more")
          if command -v gum >/dev/null 2>&1; then
            gum pager <<'EOF'
SSH and ssherpa — quick start

What is SSH?
- “Secure Shell” — it lets you open a secure terminal session on another computer to run commands, copy files, and manage servers.

What is ssherpa, and why use it?
- ssherpa helps you create and use friendly names (aliases) for servers.
- Instead of typing long commands like: ssh user@server -p 2222 -i ~/.ssh/id_ed25519
  you save an alias once and then connect with: ssh <alias>
- Benefits: faster to remember, fewer mistakes, consistent across machines (copy one config file).

Where does this live?
- SSH reads settings from ~/.ssh/config. ssherpa guides you to add entries safely.

What information do you need?
- HostName: the server's hostname or IP (required)
- User: your login user on the server (optional)
- Port: usually 22 unless your server uses a custom port (optional)
- IdentityFile: path to your private key (optional)

Example entry that ssherpa can write:

  Host work-prod
    HostName 203.0.113.42
    User farmer
    Port 22
    IdentityFile ~/.ssh/id_ed25519

Tips
- You can keep many Host entries; ssherpa will list them and let you pick.
- You can include extra files using "Include ~/.ssh/config.d/*.conf" in ~/.ssh/config.
- You can update an alias later by re-adding it via ssherpa add.

Press q to close this help.
EOF
          else
            printf '%s\n' \
"SSH (Secure Shell) opens a secure terminal on another computer." \
"ssherpa helps you save short names (aliases) so you can run 'ssh <alias>'" \
"instead of 'ssh user@host -p 22 -i ~/.ssh/key'." \
"It writes safe entries to ~/.ssh/config. You’ll need:" \
"- HostName (host/IP), optional User, Port, IdentityFile." \
"Example:" \
"Host my-server" \
"  HostName 203.0.113.42" \
"  User farmer" \
"  Port 22" \
"  IdentityFile ~/.ssh/id_ed25519"
          fi
          ;;
        "Exit")
          echo "[skipped] user exited"
          exit 0
          ;;
      esac
    done
  fi

  if [[ $line_count -eq 0 ]]; then
    echo "[skipped] no hosts match filter"
    exit 2
  fi

  # Show via gum filter
  local chosen
  chosen=$(printf '%s\n' "${LINES[@]}" | gum filter --placeholder "Filter SSH aliases…" --header "Pick an SSH alias, or ADD/EDIT/AUTHKEYS/PROXY/JUMP" --limit 1)
  if [[ -z "$chosen" ]]; then
    echo "[skipped] no selection made"
    exit 0
  fi

  # Extract token (left of tab) and display (right of tab)
  local token display
  token=$(printf '%s' "$chosen" | awk -F '\t' '{print $1}')
  display=$(printf '%s' "$chosen" | awk -F '\t' '{print $2}')

  case "$token" in
    ADD)
      ssherpa_add_flow "" "" "" "" "" "${cfg_path:-}" 0 0
      ;;
    EDIT)
      ssherpa_edit_mode "$include_patterns" "$filter_user" "$prefilter" "$no_color" "${cfg_path:-}"
      ;;
    AUTHKEYS)
      ssherpa_authkeys_menu
      ;;
    PROXY)
      ssherpa_proxy_flow "$include_patterns" "$filter_user" "$prefilter" "$no_color" "${ssh_args[@]:-}"
      ;;
    JUMP)
      ssherpa_jump_flow "$include_patterns" "$filter_user" "$prefilter" "$no_color" "$do_print" "$do_exec" "${ssh_args[@]:-}"
      ;;
    *)
      local alias
      alias="$token"
      # Find entry for nicer log (best-effort)
      local idx i user host port
      idx=-1
      for i in "${!NAMES[@]}"; do
        if [[ "${NAMES[$i]}" == "$alias" ]]; then idx=$i; break; fi
      done
      if [[ $idx -ge 0 ]]; then
        user="${USERS[$idx]}"; host="${HOSTS[$idx]}"; port="${PORTS[$idx]}"
      fi
      local disp=""; [[ -n "$user" ]] && disp+="$user@"; disp+="$host"; [[ -n "$port" ]] && disp+=":$port"
      echo "[selected] $alias → ${disp:-$alias}"
      if [[ $do_print -eq 1 ]]; then
        echo "[print] ssh $alias${ssh_args:+ }${ssh_args[*]:-}"; exit 0
      fi
      if [[ $do_exec -eq 1 ]]; then
        echo "[exec] ssh $alias${ssh_args:+ }${ssh_args[*]:-}"
        exec ssh "$alias" "${ssh_args[@]:-}"
      fi
      ;;
  esac
}

main "$@"
