#!/usr/bin/env bash
set -euo pipefail

echo "Updating package list..."
sudo apt update -y

echo "Installing dependencies for share (Debian/Ubuntu)..."
sudo apt install -y xclip magic-wormhole figlet qrencode gnupg tar

echo "Verifying installations..."
for cmd in wormhole gpg tar xclip figlet qrencode; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "  - $cmd OK"
  else
    echo "Error: $cmd not found after installation" >&2
    exit 1
  fi
done

echo "share dependencies installed (Debian)."

