#!/usr/bin/env bash
set -euo pipefail

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required on macOS. Install from https://brew.sh" >&2
  exit 1
fi

echo "Installing dependencies for mfa (macOS via Homebrew)..."
brew list gnupg >/dev/null 2>&1 || brew install gnupg
brew list pinentry-mac >/dev/null 2>&1 || brew install pinentry-mac
brew list oath-toolkit >/dev/null 2>&1 || brew install oath-toolkit
brew list figlet >/dev/null 2>&1 || brew install figlet
brew list pass >/dev/null 2>&1 || brew install pass
brew list git >/dev/null 2>&1 || brew install git
brew list fzf >/dev/null 2>&1 || brew install fzf

echo "Verifying installations..."
for cmd in pass oathtool figlet fzf gpg pbcopy; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "  - $cmd OK"
  else
    echo "Error: $cmd not found" >&2
    exit 1
  fi
done

echo "mfa dependencies installed (macOS)."
