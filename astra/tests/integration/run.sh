#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export ASTRA_LOG_LEVEL=error

"$ROOT/bin/astra" --version > /dev/null

echo "Integration smoke test passed"
