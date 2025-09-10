#!/usr/bin/env bash
set -euo pipefail

echo "Updating package list..."
sudo apt update -y

echo "Installing dependencies for forgit (Debian/Ubuntu)..."
sudo apt install -y git

echo "Verifying installations..."
if command -v git >/dev/null 2>&1; then
  echo "  - git OK"
else
  echo "Error: git not found after installation" >&2
  exit 1
fi

echo "forgit dependencies installed (Debian)."

