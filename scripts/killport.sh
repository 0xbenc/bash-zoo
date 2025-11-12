#!/bin/bash

set -euo pipefail

# killport: Free a TCP/UDP port by locating and signaling owning processes.
# UX: gum-only TUI for selection and confirmation; safe defaults (TERM then optional KILL).
# Portability: macOS + Debian/Ubuntu. Uses ss when available on Linux; falls back to lsof.

print_usage() {
  cat <<'EOF'
Usage:
  killport <port> [--tcp|--udp]
           [--all]
           [--all-users]
           [--signal SIG]
           [--grace SECS]
           [--wait SECS]
           [--no-escalate]
           [--no-wait]
           [--list]
           [--user USER]
           [--dry-run]
           [--yes]
           [--help]

Defaults:
  --tcp, current user only, TERM, --grace 3, --wait 5

Examples:
  killport 3000
  killport 5353 --udp --all --yes
  killport 8080 --dry-run
EOF
}

echo_err() { printf '%s\n' "$*" >&2; }

## Colors (TTY-aware; disabled with NO_COLOR)
is_tty=0
if [[ -t 1 ]]; then is_tty=1; fi
if [[ ${NO_COLOR:-} != "" ]]; then is_tty=0; fi

BOLD=""; DIM=""; FG_BLUE=""; FG_GREEN=""; FG_YELLOW=""; FG_MAGENTA=""; FG_RED=""; FG_CYAN=""; RESET=""
if [[ $is_tty -eq 1 ]] && command -v tput >/dev/null 2>&1; then
  colors="$(tput colors 2>/dev/null || printf '0')"
  if [[ "$colors" =~ ^[0-9]+$ ]] && [[ "$colors" -ge 8 ]]; then
    BOLD="$(tput bold 2>/dev/null || printf '')"
    DIM="$(tput dim 2>/dev/null || printf '')"
    FG_BLUE="$(tput setaf 4 2>/dev/null || printf '')"
    FG_GREEN="$(tput setaf 2 2>/dev/null || printf '')"
    FG_YELLOW="$(tput setaf 3 2>/dev/null || printf '')"
    FG_MAGENTA="$(tput setaf 5 2>/dev/null || printf '')"
    FG_RED="$(tput setaf 1 2>/dev/null || printf '')"
    FG_CYAN="$(tput setaf 6 2>/dev/null || printf '')"
    RESET="$(tput sgr0 2>/dev/null || printf '')"
  else
    RESET="$(tput sgr0 2>/dev/null || printf '')"
  fi
fi

ensure_gum() {
  if command -v gum >/dev/null 2>&1; then return 0; fi
  echo_err "gum is required. Install it with Homebrew:"
  echo_err "  brew install gum"
  return 1
}

os_name() {
  local u; u=$(uname -s)
  if [[ "$u" == "Darwin" ]]; then
    printf '%s\n' macos
  elif [[ "$u" == "Linux" ]]; then
    printf '%s\n' linux
  else
    printf '%s\n' other
  fi
}

# Globals for discovery results (parallel arrays)
PIDS=()
USERS=()
CMDS=()

current_user() { id -un 2>/dev/null || printf '%s\n' "${USER:-}"; }

port_is_numeric() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( "$1" >= 1 && "$1" <= 65535 ))
}

# Discover listener PIDs for proto/port; filter by user unless all_users.
discover_listeners() {
  local proto="$1" port="$2" all_users="$3" user_filter="$4"
  PIDS=(); USERS=(); CMDS=()
  local os; os=$(os_name)
  local seen="," # cheap dedup by PID
  local pid

  # Helper to push if passes user filters
  _push_pid() {
    local pid="$1" u c
    # Resolve user + command
    u=$(ps -o user= -p "$pid" 2>/dev/null | awk '{print $1}' || true)
    c=$(ps -o comm= -p "$pid" 2>/dev/null | awk '{print $1}' || true)
    [[ -z "$u" ]] && u="?"
    [[ -z "$c" ]] && c="?"
    # User scoping
    if [[ -n "$user_filter" ]]; then
      [[ "$u" == "$user_filter" ]] || return 0
    else
      if [[ "$all_users" != "1" ]]; then
        [[ "$u" == "$(current_user)" ]] || return 0
      fi
    fi
    # Dedup by PID
    case "$seen" in
      *",$pid,"*) return 0 ;;
      *) seen="$seen$pid," ;;
    esac
    PIDS+=("$pid"); USERS+=("$u"); CMDS+=("$c")
  }

  if [[ "$os" == linux ]] && command -v ss >/dev/null 2>&1; then
    if [[ "$proto" == tcp ]]; then
      # shellcheck disable=SC2009
      while IFS= read -r pid; do
        [[ -n "$pid" ]] || continue
        _push_pid "$pid"
      done < <(ss -lptn "sport = :$port" 2>/dev/null | sed -n 's/.*pid=\([0-9]\+\).*/\1/p')
    else
      while IFS= read -r pid; do
        [[ -n "$pid" ]] || continue
        _push_pid "$pid"
      done < <(ss -lpun "sport = :$port" 2>/dev/null | sed -n 's/.*pid=\([0-9]\+\).*/\1/p')
    fi
  else
    # Fallback to lsof on macOS or Linux
    if [[ "$proto" == tcp ]]; then
      while IFS= read -r pid; do
        [[ -n "$pid" ]] || continue
        _push_pid "$pid"
      done < <(lsof -nP -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null || true)
    else
      while IFS= read -r pid; do
        [[ -n "$pid" ]] || continue
        _push_pid "$pid"
      done < <(lsof -nP -iUDP:"$port" -t 2>/dev/null || true)
    fi
  fi
}

print_found_lines() {
  local i proto="$1" port="$2"
  for i in "${!PIDS[@]}"; do
    printf '%s[found]%s\n' "$FG_BLUE" "$RESET"
    printf '  • pid=%s%s%s\n'   "$BOLD$FG_CYAN" "${PIDS[$i]}" "$RESET"
    printf '  • user=%s%s%s\n'  "$BOLD$FG_CYAN" "${USERS[$i]}" "$RESET"
    printf '  • proto=%s%s%s\n' "$BOLD$FG_CYAN" "$proto" "$RESET"
    printf '  • port=%s%s%s\n'  "$BOLD$FG_CYAN" "$port" "$RESET"
    printf '  • cmd=%s%s%s\n'   "$BOLD$FG_CYAN" "${CMDS[$i]}" "$RESET"
  done
}

pid_in_current_scan() {
  local target_pid="$1" proto="$2" port="$3" all_users="$4" user_filter="$5"
  local _pids=() _users=() _cmds=()
  # Save globals and restore after
  local __PIDS __USERS __CMDS
  __PIDS=("${PIDS[@]:-}"); __USERS=("${USERS[@]:-}"); __CMDS=("${CMDS[@]:-}")
  discover_listeners "$proto" "$port" "$all_users" "$user_filter"
  local i found=0
  for i in "${!PIDS[@]}"; do
    if [[ "${PIDS[$i]}" == "$target_pid" ]]; then found=1; break; fi
  done
  # restore
  PIDS=("${__PIDS[@]:-}"); USERS=("${__USERS[@]:-}"); CMDS=("${__CMDS[@]:-}")
  return $(( found == 1 ? 0 : 1 ))
}

main() {
  if [[ $# -lt 1 ]]; then print_usage; exit 1; fi

  local PORT="" PROTO="tcp" ALL=0 ALL_USERS=0 DRY_RUN=0 YES=0 LIST_ONLY=0
  local SIGNAL="TERM" GRACE=3 WAIT_SECS=5 NO_ESC=0 NO_WAIT=0 USER_FILTER=""

  # Parse args
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tcp) PROTO=tcp; shift ;;
      --udp) PROTO=udp; shift ;;
      --all) ALL=1; shift ;;
      --all-users) ALL_USERS=1; shift ;;
      --signal) SIGNAL="$2"; shift 2 ;;
      --signal=*) SIGNAL="${1#*=}"; shift ;;
      --grace) GRACE="$2"; shift 2 ;;
      --grace=*) GRACE="${1#*=}"; shift ;;
      --wait) WAIT_SECS="$2"; shift 2 ;;
      --wait=*) WAIT_SECS="${1#*=}"; shift ;;
      --no-escalate) NO_ESC=1; shift ;;
      --no-wait) NO_WAIT=1; shift ;;
      --list) LIST_ONLY=1; shift ;;
      --user) USER_FILTER="$2"; ALL_USERS=1; shift 2 ;;
      --user=*) USER_FILTER="${1#*=}"; ALL_USERS=1; shift ;;
      --dry-run) DRY_RUN=1; shift ;;
      --yes|-y) YES=1; shift ;;
      --help|-h) print_usage; exit 0 ;;
      --*) echo_err "Unknown flag: $1"; print_usage; exit 1 ;;
      *)
        if [[ -z "$PORT" ]]; then PORT="$1"; shift; else echo_err "Unexpected argument: $1"; exit 1; fi
        ;;
    esac
  done

  if ! port_is_numeric "$PORT"; then
    echo_err "Invalid or missing port: $PORT"; exit 1
  fi

  ensure_gum || exit 1

  # Discover
  discover_listeners "$PROTO" "$PORT" "$ALL_USERS" "$USER_FILTER"

  print_found_lines "$PROTO" "$PORT"

  if [[ $LIST_ONLY -eq 1 ]]; then exit 0; fi

  if [[ ${#PIDS[@]} -eq 0 ]]; then
    printf '%s[up-to-date]%s port %s (no listeners)\n' "$FG_GREEN" "$RESET" "$PORT"
    exit 0
  fi

  # Selection
  local sel_indices=()
  if [[ ${#PIDS[@]} -eq 1 ]]; then
    sel_indices=(0)
  else
    if [[ $ALL -eq 1 || $YES -eq 1 ]]; then
      # Non-interactive default: select all when --all or --yes
      sel_indices=()
      local i; for i in "${!PIDS[@]}"; do sel_indices+=("$i"); done
    else
      # Build lines for gum choose
      local lines=() i line
      for i in "${!PIDS[@]}"; do
        line="pid=${PIDS[$i]} user=${USERS[$i]} proto=$PROTO port=$PORT cmd=${CMDS[$i]}"
        lines+=("$line")
      done
      local chosen=()
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        chosen+=("$line")
      done < <(printf '%s\n' "${lines[@]}" | gum choose --no-limit --header "Select processes on :$PORT")
  if [[ ${#chosen[@]} -eq 0 ]]; then
        printf '%s[skipped]%s no selection made\n' "$FG_YELLOW" "$RESET"
        exit 0
      fi
      # Map chosen back to indices via pid
      local c pid iidx
      for c in "${chosen[@]}"; do
        pid=$(printf '%s' "$c" | sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p')
        for iidx in "${!PIDS[@]}"; do
          if [[ "${PIDS[$iidx]}" == "$pid" ]]; then sel_indices+=("$iidx"); break; fi
        done
      done
    fi
  fi

  # Pre-action summary
  local N=${#sel_indices[@]}
  local plan="Would send $SIGNAL to $N pid(s)"
  if [[ $NO_ESC -ne 1 && "$SIGNAL" == "TERM" ]]; then
    plan+="; escalate to KILL after ${GRACE}s"
  fi
  if [[ $NO_WAIT -ne 1 ]]; then
    plan+="; wait ${WAIT_SECS}s"
  fi
  gum style --border normal --margin "1 2" --padding "0 2" "$plan"

  # Cross-user guard: if selected contain other-user and ALL_USERS not set
  local need_cross_confirm=0 i u curr
  curr=$(current_user)
  if [[ $ALL_USERS -eq 1 ]]; then
    need_cross_confirm=0
  else
    for i in "${sel_indices[@]}"; do
      u="${USERS[$i]}"
      if [[ "$u" != "$curr" ]]; then need_cross_confirm=1; break; fi
    done
  fi
  if [[ $need_cross_confirm -eq 1 ]]; then
    if [[ $YES -eq 1 ]]; then
      : # skip prompt, but still do not attempt other-user without ALL_USERS; mark them skipped
    else
      if gum confirm "Other-user processes detected. Attempt to signal them? (may fail)"; then
        ALL_USERS=1
      fi
    fi
  fi

  # Final confirmation unless --yes
  if [[ $YES -ne 1 ]]; then
    if ! gum confirm "Proceed?"; then
      printf '%s[skipped]%s user cancelled\n' "$FG_YELLOW" "$RESET"
      exit 0
    fi
  fi

  # Execute
  local killed=0 escalated=0 skipped=0 failed=0
  local targets=() targets_users=()
  for i in "${sel_indices[@]}"; do
    targets+=("${PIDS[$i]}")
    targets_users+=("${USERS[$i]}")
  done

  local idx pid owner ok_owner=0
  for idx in "${!targets[@]}"; do
    pid="${targets[$idx]}"; owner="${targets_users[$idx]}"; ok_owner=1
    # Owner guard
    if [[ $ALL_USERS -ne 1 && "$owner" != "$(current_user)" ]]; then
      printf '%s[skipped]%s pid=%s %s-owned (use --all-users)\n' "$FG_YELLOW" "$RESET" "$pid" "$owner"; ((skipped+=1)); continue
    fi
    # Just-in-time check still listening
    if ! pid_in_current_scan "$pid" "$PROTO" "$PORT" "$ALL_USERS" "$USER_FILTER"; then
      printf '%s[skipped]%s pid=%s no longer listening\n' "$FG_YELLOW" "$RESET" "$pid"; ((skipped+=1)); continue
    fi
    if [[ $DRY_RUN -eq 1 ]]; then
      printf '%s[killed]%s pid=%s signal=%s (dry-run)\n' "$FG_GREEN" "$RESET" "$pid" "$SIGNAL"; ((killed+=1)); continue
    fi
    if kill -"$SIGNAL" "$pid" 2>/dev/null; then
      printf '%s[killed]%s pid=%s signal=%s\n' "$FG_GREEN" "$RESET" "$pid" "$SIGNAL"; ((killed+=1))
    else
      printf '%s[failed]%s pid=%s (permission denied or no such process)\n' "$FG_RED" "$RESET" "$pid"; ((failed+=1))
    fi
  done

  # Escalate where needed
  if [[ $DRY_RUN -ne 1 && $NO_ESC -ne 1 && "$SIGNAL" == "TERM" && $GRACE -gt 0 ]]; then
    sleep "$GRACE" || true
    for idx in "${!targets[@]}"; do
      pid="${targets[$idx]}"; owner="${targets_users[$idx]}"
      if ! pid_in_current_scan "$pid" "$PROTO" "$PORT" "$ALL_USERS" "$USER_FILTER"; then
        continue
      fi
      if kill -9 "$pid" 2>/dev/null; then
        printf '%s[escalated]%s pid=%s signal=KILL\n' "$FG_MAGENTA" "$RESET" "$pid"; ((escalated+=1))
      else
        printf '%s[failed]%s pid=%s (escalation failed)\n' "$FG_RED" "$RESET" "$pid"; ((failed+=1))
      fi
    done
  fi

  # Wait for port to be free (optional)
  local remaining=0
  if [[ $NO_WAIT -ne 1 ]]; then
    local sec
    for sec in $(seq 1 "$WAIT_SECS"); do
      # spinner tick
      gum spin --spinner points --title "Waiting for :$PORT to free... (${sec}/${WAIT_SECS})" -- sleep 1 || sleep 1
      discover_listeners "$PROTO" "$PORT" 1 "" # check any user
      if [[ ${#PIDS[@]} -eq 0 ]]; then remaining=0; break; else remaining=${#PIDS[@]}; fi
    done
    if [[ $remaining -gt 0 ]]; then
      printf '%s[timeout]%s port %s still bound after %ss\n' "$FG_RED" "$RESET" "$PORT" "$WAIT_SECS"
    fi
  else
    # Rough snapshot
    discover_listeners "$PROTO" "$PORT" 1 ""
    remaining=${#PIDS[@]}
  fi

  gum style \
    --border double \
    --align center \
    --margin "1 2" \
    --padding "1 4" \
    "Summary for :$PORT ($PROTO)" \
    "killed: $killed, escalated: $escalated, skipped: $skipped, failed: $failed, remaining: $remaining"
}

main "$@"
