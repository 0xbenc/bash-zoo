#!/usr/bin/env bash

set -Eeuo pipefail

os_open() {
  open "$@"
}

os_clipboard_copy() {
  if command -v pbcopy >/dev/null 2>&1; then
    pbcopy
  fi
}
