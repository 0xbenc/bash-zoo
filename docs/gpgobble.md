# gpgobble

`gpgobble` bulk‑imports public keys from a directory and upgrades ownertrust to FULL (4) for keys that do not have a local secret key. It never downgrades trust and leaves ULTIMATE (5) alone.

## Usage

```bash
gpgobble               # import all files in the current directory
gpgobble ./keys/work   # import from a specific folder
GNUPGHOME=/tmp/gnupg gpgobble ./keys
gpgobble -n ./keys     # dry-run: preview imports, localsigns, and trust changes
```

## Notes

- Requires `gpg` (`gnupg`).
- Works with the default macOS Bash 3.2; no GNU `find` required.
- Add `-n`/`--dry-run` to preview all actions without changing your keyring.

