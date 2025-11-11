#!/usr/bin/env bash
set -euo pipefail

# macOS ships lsof; no additional packages needed.
echo "Verifying dependencies for killport (macOS)..."
if command -v lsof >/dev/null 2>&1; then
  echo "  - lsof OK"
else
  echo "Warning: lsof not found. Install via Homebrew: brew install lsof" >&2
fi

echo "killport ready (macOS)."

