#!/usr/bin/env bash
set -euo pipefail

echo "Updating package list..."
sudo apt update -y

echo "Installing dependencies for passage (Debian/Ubuntu)..."
# Add oathtool so passage can generate TOTP codes inline
sudo apt install -y pass xclip wl-clipboard oathtool

echo "Verifying installations..."
for cmd in pass; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "  - $cmd OK"
  else
    echo "Error: $cmd not found after installation" >&2
    exit 1
  fi
done

echo "Optional clipboard adapters:"
for opt in xclip wl-copy xsel; do
  if command -v "$opt" >/dev/null 2>&1; then
    echo "  - $opt OK"
  else
    echo "  - $opt (optional) missing"
  fi
done

echo "passage dependencies installed (Debian)."
