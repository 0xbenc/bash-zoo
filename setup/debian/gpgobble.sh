#!/usr/bin/env bash
set -euo pipefail

echo "Updating package list..."
sudo apt update -y

echo "Installing dependencies for gpgobble (Debian/Ubuntu)..."
sudo apt install -y gnupg

echo "Verifying installations..."
for cmd in gpg; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "  - $cmd OK"
  else
    echo "Error: $cmd not found after installation" >&2
    exit 1
  fi
done

echo "gpgobble dependencies installed (Debian)."

