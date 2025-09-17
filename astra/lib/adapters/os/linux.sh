#!/usr/bin/env bash

set -Eeuo pipefail

os_open() {
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$@"
  else
    log_warn "xdg-open not available"
  fi
}

os_clipboard_copy() {
  if command -v xclip >/dev/null 2>&1; then
    xclip -selection clipboard
  elif command -v wl-copy >/dev/null 2>&1; then
    wl-copy
  fi
}
