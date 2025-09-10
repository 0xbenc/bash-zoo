#!/usr/bin/env bash
set -euo pipefail

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required on macOS. Install from https://brew.sh" >&2
  exit 1
fi

echo "Installing dependencies for forgit (macOS via Homebrew)..."
brew list git >/dev/null 2>&1 || brew install git

echo "Verifying installations..."
if command -v git >/dev/null 2>&1; then
  echo "  - git OK"
else
  echo "Error: git not found" >&2
  exit 1
fi

echo "forgit dependencies installed (macOS)."

