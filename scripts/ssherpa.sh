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

Defaults:
  Interactive gum filter, executes ssh after selection.
  Only concrete Host aliases (no wildcards) unless --all.

Examples:
  ssherpa
  ssherpa --print -- -L 8080:localhost:8080
  ssherpa --filter prod --user alice
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
  LINES=()
  local i name host user port key ispat info
  for i in "${!NAMES[@]}"; do
    name="${NAMES[$i]}"; host="${HOSTS[$i]}"; user="${USERS[$i]}"; port="${PORTS[$i]}"; key="${KEYS[$i]}"; ispat="${PATTERNS[$i]}"
    if [[ "$include_patterns" != "1" && "$ispat" == "1" ]]; then continue; fi
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
  # Synthetic Add row
  LINES+=("ADD"$'\t'"$ADD_ROW_LABEL")
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

:

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

write_alias_stanza() {
  # args: config_path alias host user port identity dry_run yes
  local cfg="$1" alias="$2" host="$3" user="$4" port="$5" ident="$6" dry_run="$7" yes="$8"
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
  local f
  local out=()
  if [[ -d "$dir" ]]; then
    for f in "$dir"/id_*; do
      [[ -e "$f" ]] || continue
      case "$f" in *.pub) continue ;; esac
      out+=("$f")
    done
  fi
  printf '%s\n' "${out[@]:-}"
}

ssherpa_add_flow() {
  # args: alias host user port identity config dry_run yes
  local alias="$1" host="$2" user="$3" port="$4" ident="$5" cfg="$6" dry_run="$7" yes="$8"
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
    user=$(gum input --placeholder "e.g., alice (blank = default)")
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
      sel=$( { list_private_keys; printf '%s\n' "Other…" "None"; } | gum choose --header "IdentityFile (optional)") || sel="None"
      case "$sel" in
        "Other…") ident=$(gum input --placeholder "Path to private key (e.g., ~/.ssh/id_ed25519)") ;;
        "None") ident="" ;;
        *) ident="$sel" ;;
      esac
    else
      ident=$(gum input --placeholder "IdentityFile (optional)" --value "")
    fi
  fi

  # Clear and show concise review + confirmation
  clear_screen
  style_step "Review"
  echo "Alias: $alias"
  echo "HostName: $host"
  [[ -n "$user" ]] && echo "User: $user" || echo "User: (default)"
  [[ -n "$port" ]] && echo "Port: $port" || echo "Port: (22 by default)"
  [[ -n "$ident" ]] && echo "IdentityFile: $ident" || echo "IdentityFile: (none)"
  # Confirm path unless --yes
  if [[ "$yes" -ne 1 ]]; then
    gum confirm "Write to $(printf '%s' "${cfg:-$(config_path_default)}")?" || { echo "[skipped] cancelled"; alt_screen_off; return 0; }
  fi
  write_alias_stanza "${cfg:-$(config_path_default)}" "$alias" "$host" "$user" "$port" "$ident" "$dry_run" "$yes"
  alt_screen_off
}

main() {
  local sub=""; [[ $# -gt 0 ]] && case "$1" in add) sub="$1"; shift ;; esac
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

  ensure_gum || exit 1

  if [[ "$sub" == "add" ]]; then
    ssherpa_add_flow "$alias" "$host" "$user" "$port" "$ident" "${cfg_path:-}" "$dry_run" "$yes"
    exit 0
  fi

  # Load config
  load_config_files
  [[ -n "${cfg_path:-}" ]] && CONFIG_FILES=("$cfg_path")
  parse_configs

  # Build selection list (aliases only + synthetic add row)
  build_alias_lines "$include_patterns" "$filter_user" "$prefilter" "$no_color"
  local acount=${#NAMES[@]} line_count=${#LINES[@]}
  echo "[loaded] $acount aliases"

  # If there are zero aliases, present starter options: Add, Learn more, Exit
  if [[ $acount -eq 0 ]]; then
    while true; do
      local choice
      choice=$(printf '%s\n' "Add alias" "Learn more" "Exit" | gum choose --header "No SSH aliases found") || { echo "[skipped] no selection made"; exit 0; }
      case "$choice" in
        "Add alias")
          ssherpa_add_flow "" "" "" "" "" "${cfg_path:-}" 0 0
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
    User alice
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
"  User alice" \
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
  chosen=$(printf '%s\n' "${LINES[@]}" | gum filter --placeholder "Filter SSH aliases…" --header "Pick an SSH alias — Enter to connect — type to filter" --limit 1)
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
