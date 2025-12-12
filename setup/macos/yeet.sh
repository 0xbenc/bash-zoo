#!/usr/bin/env bash
set -euo pipefail

echo "Checking dependencies for yeet (macOS)..."

for cmd in diskutil mount; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "  - $cmd OK"
  else
    echo "Error: $cmd not found" >&2
    exit 1
  fi
done

echo "yeet dependencies installed (macOS)."

