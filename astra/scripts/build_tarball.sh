#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-0.1.0}"
OUTPUT_DIR="$ROOT/build/tarball"
mkdir -p "$OUTPUT_DIR"
ARCHIVE="$OUTPUT_DIR/astra-${VERSION}.tar.gz"

tar -czf "$ARCHIVE" -C "$ROOT" bin lib share

echo "Created $ARCHIVE"
