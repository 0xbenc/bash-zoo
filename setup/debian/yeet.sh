#!/usr/bin/env bash
set -euo pipefail

echo "Updating package list..."
sudo apt update -y

echo "Installing dependencies for yeet (Debian/Ubuntu)..."
sudo apt install -y udisks2 util-linux eject

echo "Verifying installations..."
for cmd in lsblk udisksctl; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "  - $cmd OK"
  else
    echo "Error: $cmd not found after installation" >&2
    exit 1
  fi
done

echo "yeet dependencies installed (Debian)."

