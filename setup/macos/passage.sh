#!/usr/bin/env bash
set -euo pipefail

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required on macOS. Install from https://brew.sh" >&2
  exit 1
fi

echo "Installing dependencies for passage (macOS via Homebrew)..."
brew list gnupg >/dev/null 2>&1 || brew install gnupg
brew list pinentry-mac >/dev/null 2>&1 || brew install pinentry-mac
brew list pass >/dev/null 2>&1 || brew install pass
:

echo "Verifying installations..."
for cmd in pass pbcopy; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "  - $cmd OK"
  else
    echo "Error: $cmd not found" >&2
    exit 1
  fi
done

echo "passage dependencies installed (macOS)."
