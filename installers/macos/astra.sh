#!/usr/bin/env bash
set -euo pipefail

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required on macOS. Install from https://brew.sh" >&2
  exit 1
fi

brew list bash >/dev/null 2>&1 || brew install bash
brew list fzf >/dev/null 2>&1 || brew install fzf
brew list jq >/dev/null 2>&1 || brew install jq
brew list fd >/dev/null 2>&1 || brew install fd
brew list ripgrep >/dev/null 2>&1 || brew install ripgrep
brew list bat >/dev/null 2>&1 || brew install bat
brew list tmux >/dev/null 2>&1 || brew install tmux
brew list chafa >/dev/null 2>&1 || brew install chafa
brew list poppler >/dev/null 2>&1 || brew install poppler
brew list atool >/dev/null 2>&1 || brew install atool
brew list ffmpeg >/dev/null 2>&1 || brew install ffmpeg
brew list trash >/dev/null 2>&1 || brew install trash

BREW_BASH=""
if brew info bash >/dev/null 2>&1; then
  BREW_BASH="$(brew --prefix bash)/bin/bash"
fi
if [[ -n "$BREW_BASH" && -x "$BREW_BASH" ]]; then
  if ! grep -q "$BREW_BASH" /etc/shells; then
    echo "$BREW_BASH" | sudo tee -a /etc/shells >/dev/null
  fi
fi

echo "astra dependencies installed (macOS)."
