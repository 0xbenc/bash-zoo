# bash-zoo

<p align="left">
  <a href="https://github.com/0xbenc/bash-zoo">
    <img src="https://img.shields.io/badge/bash-CLI%20toolkit-4EAA25?style=flat-square&logo=gnu-bash&logoColor=white" alt="Bash" />
  </a>
  <a href="#platform-support">
    <img src="https://img.shields.io/badge/platform-macOS%20%7C%20Debian-6C63FF?style=flat-square" alt="Platforms" />
  </a>
  <a href="LICENSE">
    <img src="https://img.shields.io/github/license/0xbenc/bash-zoo?style=flat-square" alt="License" />
  </a>
</p>

## TLDR

The prerequisites are `brew`, `figlet`, and `gum`. 

The installer below will guide you through the prereqs if you don't have them.

```shell
curl -fsSL https://bash.occ.farm | bash
```
or

```shell
curl -fsSL https://raw.githubusercontent.com/0xbenc/bash-zoo/HEAD/install-remote.sh | bash
```
or

```shell
git clone https://github.com/0xbenc/bash-zoo.git
cd bash-zoo
./install.sh
```

## Table of Contents

- [Tools at a Glance](#tools-at-a-glance)
- [Upgrading](#upgrading)
- [Uninstall](#uninstall)
- [Meta CLI](#meta-cli)
- [Dependencies & References](#dependencies--references)
- [Credits](#credits)
- [License](#license)

## Tools at a Glance

| Script | State | Superpower | Platforms | Extra Packages |
| --- | --- | --- | --- | --- |
| [forgit](docs/forgit.md) | ✅ stable | Scan directories for Git repos needing commits or pushes | macOS, Debian/Ubuntu | `git` |
| [gpgobble](docs/gpgobble.md) | ✅ stable | Bulk‑import public keys and set ownertrust to FULL (4) for non‑local keys | macOS, Debian/Ubuntu | `gnupg` |
| [killport](docs/killport.md) | ✅ stable | Free a TCP/UDP port with gum selection, TERM→KILL, and wait | macOS, Debian/Ubuntu | `lsof` (Linux optionally `iproute2` for `ss`) |
| [hostshelper](docs/hostshelper.md) | ✅ stable | Save host/IP pairs + presets and write them into `/etc/hosts` | macOS, Debian/Ubuntu | none |
| [ssherpa](docs/ssherpa.md) | ✅ stable | Alias-first SSH host picker + interactive config writer | macOS, Debian/Ubuntu | none |
| [yeet](docs/yeet.md) | ✅ stable | Eject removable flash drives with gum multi‑select | macOS, Debian/Ubuntu | `udisks2` (Linux) |
| [passage](docs/passage.md) | ✅ stable | Interactive GNU Pass browser with pins and MRU; copy or reveal password; built‑in TOTP (MFA) helpers | macOS, Debian/Ubuntu | `pass`, `oathtool`, platform clipboard utility |
| [uuid](docs/uuid.md) | ✅ stable | Create and copy a fresh UUID without leaving the terminal | macOS, Debian/Ubuntu | `uuidgen` (or Python 3), clipboard tool (`pbcopy`/`xclip`/`xsel`) |
| [zapp](docs/zapp.md) | ✅ stable | Launch an AppImage or unpacked app stored under `~/zapps` | Debian/Ubuntu | none |
| [zapper](docs/zapper.md) | ✅ stable | Prepare, validate, and register new apps for `zapp` with desktop entries | Debian/Ubuntu | `desktop-file-utils` |

> All setup scripts live in `setup/<os>/<script>.sh` and match the script names one-to-one.

## Upgrading

If you’ve installed the meta CLI, prefer the self-update command:

```bash
bash-zoo update zoo             # refresh installed tools + meta CLI
```

Developing locally? Point updates at a working tree:

```bash
bash-zoo update zoo --from /path/to/local/clone
```

You can still update via git + installer when working in the repo:

```bash
cd path/to/bash-zoo
git pull
./install.sh         # re-run to pick up new tools or dependencies
```

The installer is idempotent: re-running only tweaks what changed and offers new toys as they land.

## Uninstall

```bash
./uninstall.sh
./uninstall.sh --all  # remove every Bash Zoo alias and binary in one go
```

The interactive uninstaller uses `gum` and also includes an "All" option for quick removal. Prerequisite: `gum` must be installed and in PATH.

Then restart your shell so aliases disappear: `exec "$SHELL" -l`.

## Meta CLI

`bash-zoo` is an always-installed meta CLI:

- `bash-zoo version` — print the installed meta CLI version.
- `bash-zoo uninstall [--all]` — remove installed tools and aliases without needing the repo.
- `bash-zoo update passwords` — run `git pull` in each first-level folder of `~/.password-store` and summarize results.
- `bash-zoo update zoo` — refresh installed tools and the meta CLI from a source repo (or a local folder via `--from`).

Examples

```bash
bash-zoo version
bash-zoo update passwords
bash-zoo update zoo --dry-run
bash-zoo uninstall --all
```

## Dependencies & References

Bash Zoo depends on (and is inspired by) these upstream projects:

- Homebrew Core: https://github.com/Homebrew/homebrew-core
- Homebrew installer script: https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh
- figlet: https://www.figlet.org/
- gum: https://github.com/charmbracelet/gum

## Credits

- [Vik Bhaduri](https://github.com/basedvik) — Contributor
- [Ben Chapman](https://github.com/0xbenc) — Maintainer
- [Ben Cully](https://github.com/BenCully) — Contributor

## License

[MIT](LICENSE)
