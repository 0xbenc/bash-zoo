#!/usr/bin/env bash
set -euo pipefail

tmp_dir=""

cleanup_tmp_dir() {
  if [[ -n "$tmp_dir" && -d "$tmp_dir" ]]; then
    rm -rf "$tmp_dir"
  fi
  tmp_dir=""
}

trap cleanup_tmp_dir EXIT

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

install_homebrew() {
  if find_brew_bin >/dev/null 2>&1; then
    return
  fi

  echo "Installing Homebrew for Linux..."
  tmp_dir=$(mktemp -d)
  local installer="$tmp_dir/install-homebrew.sh"
  curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$installer"
  chmod +x "$installer"
  NONINTERACTIVE=1 /bin/bash "$installer"
  cleanup_tmp_dir
}

sudo apt update -y

sudo apt install -y \
  atool \
  bash \
  bat \
  build-essential \
  chafa \
  curl \
  fd-find \
  ffmpeg \
  file \
  git \
  jq \
  poppler-utils \
  ripgrep \
  trash-cli

install_homebrew

brew_bin=""
if brew_bin=$(find_brew_bin); then
  eval "$($brew_bin shellenv)"
else
  echo "Failed to install Homebrew." >&2
  exit 1
fi

if "$brew_bin" list --versions fzf >/dev/null 2>&1; then
  "$brew_bin" upgrade fzf
else
  "$brew_bin" install fzf
fi

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