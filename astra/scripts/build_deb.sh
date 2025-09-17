#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-0.1.0}"
BUILD_ROOT="$ROOT/build/deb"
PKG_DIR="$BUILD_ROOT/astra_${VERSION}_all"

rm -rf "$PKG_DIR"
mkdir -p "$PKG_DIR/DEBIAN" "$PKG_DIR/usr/bin" "$PKG_DIR/usr/lib/astra" "$PKG_DIR/usr/share/astra"

install -m 0755 "$ROOT/bin/astra" "$PKG_DIR/usr/bin/astra"
cp -R "$ROOT/lib" "$PKG_DIR/usr/lib/astra/"
cp -R "$ROOT/share" "$PKG_DIR/usr/share/astra/"

cat >"$PKG_DIR/DEBIAN/control" <<CONTROL
Package: astra
Version: $VERSION
Section: utils
Priority: optional
Architecture: all
Maintainer: Astra Shell <astra@example.com>
Depends: bash (>= 5), fzf, jq, fd-find | fd, ripgrep, bat
Description: Astra terminal file manager
 A bash-driven terminal file manager with previews and fuzzy search.
CONTROL

dpkg-deb --build "$PKG_DIR"

echo "Created package at ${PKG_DIR}.deb"
