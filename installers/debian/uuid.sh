#!/usr/bin/env bash
set -euo pipefail

echo "Updating package list..."
sudo apt update -y

echo "Installing dependencies for uuid (Debian/Ubuntu)..."
sudo apt install -y xclip uuid-runtime

echo "Verifying installations..."
if command -v xclip >/dev/null 2>&1; then echo "  - xclip OK"; else echo "Error: xclip missing" >&2; exit 1; fi
if command -v uuidgen >/dev/null 2>&1; then echo "  - uuidgen OK"; else echo "Error: uuidgen missing" >&2; exit 1; fi

echo "uuid dependencies installed (Debian)."

