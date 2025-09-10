# Bash Zoo

A small set of helpful terminal tools you can install in minutes and run from anywhere. 
Works on Debian/Ubuntu and macOS.

## Quick Start
```bash
git clone https://github.com/0xbenc/bash-zoo
cd bash-zoo
sudo chmod +x wizard.sh
./wizard.sh
```

## What You Get

- mfa — Generate 2FA codes from your pass store; copies to clipboard (macOS + Debian/Ubuntu).
- share — Securely send/receive files, folders, or clipboard via a one‑time code (Debian/Ubuntu).
- uuid — Create a random UUID and copy it to the clipboard (Debian/Ubuntu).
- zapp — Launch an app from a folder under `~/zapps` (Debian/Ubuntu).
- zapper — Prepare and add apps (AppImage or archives) into `~/zapps`, with a desktop entry (Debian/Ubuntu).
- forgit — Scan the current directory for Git repos and report any with uncommitted or unpushed work (macOS + Debian/Ubuntu).

> All tools are opt-in during the install process

## Uninstall

```bash
./uninstall.sh
```

Then reload your shell (or open a new terminal): `exec "$SHELL" -l`.

## Credits

- Ben Chapman (0xbenc) — Maintainer
- Ben Cully (BenCully) — Contributor
