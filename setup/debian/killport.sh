#!/usr/bin/env bash
set -euo pipefail

echo "Installing dependencies for killport (Debian/Ubuntu)..."

sudo apt update -y
# lsof is required; iproute2 provides 'ss' which we prefer on Linux when present
sudo apt install -y lsof iproute2

echo "Verifying installations..."
for cmd in lsof ss; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "  - $cmd OK"
  else
    echo "  - $cmd not found (will fall back where possible)"
  fi
done

echo "killport dependencies installed (Debian)."

