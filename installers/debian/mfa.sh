#!/usr/bin/env bash
set -euo pipefail

echo "Updating package list..."
sudo apt update -y

echo "Installing dependencies for mfa (Debian/Ubuntu)..."
sudo apt install -y pass oathtool figlet git xclip

echo "Verifying installations..."
for cmd in pass oathtool figlet xclip; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "  - $cmd OK"
  else
    echo "Error: $cmd not found after installation" >&2
    exit 1
  fi
done

echo "mfa dependencies installed (Debian)."

