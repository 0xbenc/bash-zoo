#!/bin/bash
set -euo pipefail

# airplane: Per-terminal offline mode for WAN egress while allowing LAN and loopback.
#
# Modes
# - strict: if system is prepared (installer ran), spawns subshell in group 'airplane'.
#           Firewall rules drop WAN egress for that group; LAN/loopback allowed.
# - soft:   no system prep required; sets proxy env to a blackhole with NO_PROXY
#           allowlist for LAN/loopback. Covers many CLI/dev tools, but not all.
#
# Usage
#   airplane            Enter airplane subshell (strict if available, else soft).
#   airplane on         Same as above.
#   airplane run <cmd>  Run single command under airplane.
#   airplane status     Show ON/OFF and mode.
#   airplane off        Alias for 'exit'
#
# Notes
# - Exiting the subshell turns airplane OFF for that terminal.
# - On strict mode, traffic from processes in the subshell is filtered by group 'airplane'.
# - On soft mode, HTTP(S)/proxy-aware tools are blocked; raw sockets may still egress.

PROG="airplane"

detect_os() {
  local u
  u=$(uname -s 2>/dev/null || printf 'Unknown')
  case "$u" in
    Linux)  echo debian ;;
    *)      echo other ;;
  esac
}

in_strict_shell() {
  # Primary group is 'airplane' when strict subshell is active.
  # Fall back to env marker if needed.
  if [[ "$(id -gn 2>/dev/null || true)" == "airplane" ]]; then
    return 0
  fi
  return 1
}

in_soft_shell() {
  # Marker env var we set in soft mode.
  [[ "${AIRPLANE_SOFT_MODE:-0}" == "1" ]]
}

airplane_status() {
  if in_strict_shell; then
    printf 'airplane: ON (strict)\n'
    return 0
  fi
  if in_soft_shell; then
    printf 'airplane: ON (soft)\n'
    return 0
  fi
    printf 'airplane: OFF\n'
}

airplane_exit() {
  # Exit only if we are inside an airplane subshell
  if in_strict_shell || in_soft_shell; then
    # Prefer matching a recorded shell PID when available
    if [[ -n "${AIRPLANE_SHELL_PID:-}" && "${AIRPLANE_SHELL_PID}" = "${PPID}" ]]; then
      kill -TERM "${PPID}" >/dev/null 2>&1 || kill -HUP "${PPID}" >/dev/null 2>&1 || true
      exit 0
    fi
    # Fallback: parent should be the interactive shell
    kill -TERM "${PPID}" >/dev/null 2>&1 || kill -HUP "${PPID}" >/dev/null 2>&1 || true
    exit 0
  fi
  echo "airplane: not inside an airplane shell; nothing to exit." >&2
  exit 1
}

have_group_airplane() {
  # User must be a member of 'airplane' group for strict mode.
  # Check both primary and supplementary groups.
  if command -v id >/dev/null 2>&1; then
    if id -nG 2>/dev/null | tr ' ' '\n' | grep -qx "airplane"; then
      return 0
    fi
  fi
  return 1
}

strict_available() {
  # Strict is available if group membership exists. We do not attempt to
  # verify firewall rule installation here (no root). The installer sets them.
  if command -v id >/dev/null 2>&1; then
    if id -nG 2>/dev/null | tr ' ' '\n' | grep -qx "airplane"; then
      return 0
    fi
  fi
  return 1
}

build_no_proxy() {
  # Build a conservative NO_PROXY allowlist for LAN/loopback.
  # Note: NO_PROXY handling varies across tools; CIDR is not consistently supported.
  # We use common patterns.
  local items
  items=(
    localhost
    127.0.0.1
    ::1
    .local
    *.local
    10.*
    172.16.* 172.17.* 172.18.* 172.19.* 172.20.* 172.21.* 172.22.* 172.23.* \
    172.24.* 172.25.* 172.26.* 172.27.* 172.28.* 172.29.* 172.30.* 172.31.*
    192.168.*
    169.254.*
  )
  local IFS=,
  printf '%s' "${items[*]}"
}

soft_env_exports() {
  # Point proxies at a local blackhole; allowlist localnets via NO_PROXY.
  local no_proxy
  no_proxy=$(build_no_proxy)
  # Use a high, likely closed port on loopback to fail fast.
  # Some tools respect lowercase, some uppercase.
  printf 'export AIRPLANE_SOFT_MODE=1; '
  printf 'export NO_PROXY=%q; ' "$no_proxy"
  printf 'export no_proxy=%q; ' "$no_proxy"
  printf 'export HTTP_PROXY=%q; '  "http://127.0.0.1:9"
  printf 'export HTTPS_PROXY=%q; ' "http://127.0.0.1:9"
  printf 'export ALL_PROXY=%q; '   "socks5://127.0.0.1:9"
  printf 'export http_proxy=%q; '  "http://127.0.0.1:9"
  printf 'export https_proxy=%q; ' "http://127.0.0.1:9"
  printf 'export all_proxy=%q; '   "socks5://127.0.0.1:9"
}

quote_cmd() {
  # Safely quote a command array for -c
  # Usage: quote_cmd cmd args...
  local out=""
  local s
  for s in "$@"; do
    # portable %q alternative for bash 3/4+ fallback
    # Use printf %s with single-quote wrapping and escaping
    s=${s//\'/\'\'\'}
    if [[ -z "$out" ]]; then
      out="'$s'"
    else
      out+=" '$s'"
    fi
  done
  printf '%s' "$out"
}

prepare_bash_rcfile_shim() {
  # Create a temporary bash rcfile that sources user's rc then defines an
  # 'airplane' function so 'airplane exit/off/land' can terminate this shell.
  local rc
  rc=$(mktemp "${TMPDIR:-/tmp}/airplane-bashrc.XXXXXX" 2>/dev/null || mktemp)
  cat >"$rc" <<'EOS'
#!/usr/bin/env bash
if [[ -f "$HOME/.bashrc" ]]; then
  # shellcheck source=/dev/null
  . "$HOME/.bashrc"
fi

airplane() {
  case "$1" in
    exit|off|land)
      exit 0
      ;;
    *)
      command airplane "$@"
      ;;
  esac
}
EOS
  printf '%s' "$rc"
}

prepare_zsh_zdotdir_shim() {
  # Create a temporary ZDOTDIR containing a .zshrc that sources user rc then
  # defines an 'airplane' function with an exit subcommand.
  local dir
  dir=$(mktemp -d "${TMPDIR:-/tmp}/airplane-zdot.XXXXXX" 2>/dev/null || mktemp -d)
  local zrc="$dir/.zshrc"
  cat >"$zrc" <<'EOS'
if [ -f "$HOME/.zshrc" ]; then
  . "$HOME/.zshrc"
fi

airplane() {
  case "$1" in
    exit|off|land)
      exit 0
      ;;
    *)
      command airplane "$@"
      ;;
  esac
}
EOS
  printf '%s' "$dir"
}

make_macos_tool_stubs() { :; }

prepare_newgrp_shell_wrapper() {
  # Build a small wrapper that newgrp will execute as the shell. The wrapper
  # sets prompt, ensures macOS stubs are in PATH (if present), wires the
  # airplane() function for exit, then execs the real shell interactively.
  local shell_bin
  shell_bin=${SHELL:-/bin/bash}
  local base
  base=$(basename "$shell_bin")

  local zd rc wrap
  case "$base" in
    zsh)
      zd=$(prepare_zsh_zdotdir_shim)
      ;;
    bash)
      rc=$(prepare_bash_rcfile_shim)
      ;;
  esac

  wrap=$(mktemp "${TMPDIR:-/tmp}/airplane-wrap.XXXXXX" 2>/dev/null || mktemp)
  cat >"$wrap" <<EOS
#!/bin/sh
export AIRPLANE_ACTIVE=1
export AIRPLANE_SHELL_PID=
if [ -n "\${AIRPLANE_STUB_DIR:-}" ]; then
  export PATH="\$AIRPLANE_STUB_DIR:\${PATH:-}"
fi
if [ -n "\${PS1-}" ]; then export PS1="[airplane] \${PS1}"; fi
if [ -n "\${PROMPT-}" ]; then export PROMPT="[airplane] \${PROMPT}"; fi
case "$base" in
  zsh)
    export ZDOTDIR='$zd'
    exec "$shell_bin" -i
    ;;
  bash)
    exec "$shell_bin" --rcfile '$rc' -i
    ;;
  *)
    exec "$shell_bin" -i
    ;;
esac
EOS
  chmod +x "$wrap" 2>/dev/null || true
  printf '%s' "$wrap"
}

enter_strict_shell() {
  # Prefer sg if available to run a command in group airplane; fallback to newgrp.
  local shell_bin
  shell_bin=${SHELL:-/bin/bash}

  # Build a small prelude to mark and tweak prompt without relying on rc files.
  # Avoid complex color; keep simple and portable.
  local prelude exec_line
  prelude='export AIRPLANE_ACTIVE=1; export AIRPLANE_SHELL_PID=$$; '
  prelude+='if [ -n "${PS1-}" ]; then export PS1="[airplane] ${PS1}"; fi; '
  prelude+='if [ -n "${PROMPT-}" ]; then export PROMPT="[airplane] ${PROMPT}"; fi; '

  # Prepare per-shell shims so 'airplane exit/off/land' can exit cleanly.
  case "$(basename "$shell_bin")" in
    zsh)
      local zd
      zd=$(prepare_zsh_zdotdir_shim)
      prelude+="export ZDOTDIR='$zd'; "
      exec_line="exec ${shell_bin} -i"
      ;;
    bash)
      local rc
      rc=$(prepare_bash_rcfile_shim)
      exec_line="exec ${shell_bin} --rcfile '$rc' -i"
      ;;
    *)
      exec_line="exec ${shell_bin} -i"
      ;;
  esac

  # macOS no longer supported; no stubs applied.

  if command -v sg >/dev/null 2>&1; then
    # shellcheck disable=SC2093
    exec sg airplane -c "$prelude$exec_line"
  fi

  echo "airplane: entering strict subshell via newgrp (type 'exit' to leave)..." >&2
  # Use a wrapper so we can augment the environment and define helpers.
  local wrap
  wrap=$(prepare_newgrp_shell_wrapper)
  export SHELL="$wrap"
  exec newgrp airplane
}

enter_soft_shell() {
  local shell_bin
  shell_bin=${SHELL:-/bin/bash}
  local exports
  exports=$(soft_env_exports)
  local prelude exec_line
  prelude="$exports"
  prelude+='export AIRPLANE_SHELL_PID=$$; '
  prelude+='if [ -n "${PS1-}" ]; then export PS1="[airplane] ${PS1}"; fi; '
  prelude+='if [ -n "${PROMPT-}" ]; then export PROMPT="[airplane] ${PROMPT}"; fi; '

  case "$(basename "$shell_bin")" in
    zsh)
      local zd
      zd=$(prepare_zsh_zdotdir_shim)
      prelude+="export ZDOTDIR='$zd'; "
      exec_line="exec ${shell_bin} -i"
      ;;
    bash)
      local rc
      rc=$(prepare_bash_rcfile_shim)
      exec_line="exec ${shell_bin} --rcfile '$rc' -i"
      ;;
    *)
      exec_line="exec ${shell_bin} -i"
      ;;
  esac

  # shellcheck disable=SC2093
  exec bash -lc "$prelude$exec_line" 2>/dev/null || exec sh -lc "$prelude$exec_line"
}

run_strict() {
  if [[ $# -eq 0 ]]; then
    echo "airplane: missing command for 'run'" >&2
    exit 1
  fi
  if command -v sg >/dev/null 2>&1; then
    local cmd
    cmd=$(quote_cmd "$@")
    exec sg airplane -c "env AIRPLANE_ACTIVE=1 $cmd"
  fi
  echo "airplane: 'sg' not found; try 'airplane' (interactive) which uses newgrp." >&2
  exit 1
}

run_soft() {
  if [[ $# -eq 0 ]]; then
    echo "airplane: missing command for 'run'" >&2
    exit 1
  fi
  local exports
  exports=$(soft_env_exports)
  local cmd
  cmd=$(quote_cmd "$@")
  # Use sh -lc to ensure env + command in one process
  exec sh -lc "$exports exec $cmd"
}

print_help() {
  cat <<'EOF'
airplane: Per-terminal offline mode (LAN allowed, WAN blocked)

Usage:
  airplane            Enter airplane subshell (strict if available, else soft)
  airplane on         Same as above
  airplane run <cmd>  Run a single command under airplane
  airplane status     Show current status
  airplane exit       Leave the airplane subshell
  airplane land       Same as 'exit'
  airplane off        Alias for 'exit'

Notes:
  - In strict mode, a subshell runs with group 'airplane' (requires installer).
  - In soft mode, proxy env vars block most HTTP(S) egress.
  - To leave airplane, type: exit
EOF
}

main() {
  local os
  os=$(detect_os)
  local subcmd
  subcmd="${1:-}"

  if [[ "$os" != "debian" ]]; then
    case "$subcmd" in
      -h|--help|help)
        print_help; exit 0 ;;
      status)
        airplane_status; exit 0 ;;
      *)
        echo "airplane: Linux-only. This system is unsupported." >&2
        exit 1
        ;;
    esac
  fi

  case "$subcmd" in
    -h|--help|help)
      print_help
      exit 0
      ;;
    status)
      airplane_status
      exit 0
      ;;
    off|exit|land)
      airplane_exit
      ;;
    run)
      shift || true
      if strict_available; then
        run_strict "$@"
      else
        run_soft "$@"
      fi
      ;;
    on|"")
      if strict_available; then
        enter_strict_shell
      else
        echo "airplane: strict mode not available; using soft mode (proxy-based)." >&2
        echo "          Run the installer to enable strict per-process egress filtering." >&2
        enter_soft_shell
      fi
      ;;
    *)
      echo "airplane: unknown command '$subcmd'" >&2
      print_help
      exit 1
      ;;
  esac
}

main "$@"
