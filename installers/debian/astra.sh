#!/usr/bin/env bash
set -euo pipefail

sudo apt update -y

sudo apt install -y bash fzf jq fd-find ripgrep bat chafa poppler-utils atool ffmpeg trash-cli

# Ensure fd is accessible as `fd`
if ! command -v fd >/dev/null 2>&1; then
  if command -v fdfind >/dev/null 2>&1; then
    mkdir -p "$HOME/.local/bin"
    if [[ ! -e "$HOME/.local/bin/fd" ]]; then
      ln -s "$(command -v fdfind)" "$HOME/.local/bin/fd"
      echo "Linked fdfind to $HOME/.local/bin/fd"
    fi
  fi
fi

echo "astra dependencies installed (Debian)."
