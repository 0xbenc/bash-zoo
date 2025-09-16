# 🐚 Bash Zoo

<p align="center">
  <a href="https://github.com/0xbenc/bash-zoo">
    <img src="https://img.shields.io/badge/Bash-CLI%20toolkit-222831?style=for-the-badge&logo=gnu-bash&logoColor=white" alt="Bash" />
  </a>
  <a href="#platform-support">
    <img src="https://img.shields.io/badge/macOS%20%7C%20Debian-supported-6C63FF?style=for-the-badge" alt="Platforms" />
  </a>
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/license-MIT-orange?style=for-the-badge" alt="License" />
  </a>
</p>

> Terminal-grade automation animals you can install in minutes. Opt into the tricks you want, keep the rest in the habitat.

## TL;DR

```bash
git clone https://github.com/0xbenc/bash-zoo
cd bash-zoo
./wizard.sh
```

The guided wizard detects macOS or Debian/Ubuntu, checks dependencies, and lets you cherry-pick scripts. Restart your shell and the aliases are ready anywhere.

## Table of Contents

- [Why Bash Zoo](#why-bash-zoo)
- [Tools at a Glance](#tools-at-a-glance)
- [Installation](#installation)
- [Platform Support](#platform-support)
- [Daily Use](#daily-use)
- [Upgrading](#upgrading)
- [Uninstall](#uninstall)
- [Credits](#credits)
- [License](#license)

## Why Bash Zoo

- **Curated shortcuts** · Everything is battle-tested for fast terminal workflows.
- **Zero-boilerplate install** · `wizard.sh` handles dependency checks, per-OS installers, and aliases.
- **Portable by design** · Scripts are POSIX-friendly Bash and ship with Debian + macOS installers.
- **Pick-your-pack** · Install individual tools or the whole enclosure — nothing gets forced into your path.

## Tools at a Glance

| Script | Superpower | Platforms | Extra Packages |
| --- | --- | --- | --- |
| `mfa` | Generate TOTP codes from `pass` and copy them to your clipboard | macOS, Debian/Ubuntu | `pass`, platform clipboard utility |
| `share` | Secure one-time file, folder, or clipboard transfer through a relay | Debian/Ubuntu | `curl`, `openssl`, `socat` |
| `uuid` | Create and copy a fresh UUID without leaving the terminal | Debian/Ubuntu | `xclip` |
| `zapp` | Launch an AppImage or unpacked app stored under `~/zapps` | Debian/Ubuntu | none |
| `zapper` | Prepare, validate, and register new apps for `zapp` with desktop entries | Debian/Ubuntu | `desktop-file-utils` |
| `forgit` | Scan directories for Git repos needing commits or pushes | macOS, Debian/Ubuntu | `git` |

> All installers live in `installers/<os>/<script>.sh` and match the script names one-to-one.

## Installation

### Option A — Guided wizard (recommended)

```bash
git clone https://github.com/0xbenc/bash-zoo
cd bash-zoo
./wizard.sh
```

- Auto-detects macOS vs. Debian/Ubuntu
- Shows which tools need additional packages before enabling
- Groups complementary tools (like the `zapps` pair) for easy onboarding
- Stores aliases so the commands travel with every new shell session

### Option B — Manual pick-and-run

```bash
./installers/<os>/<script>.sh
```

- OS-specific installers live under `installers/macos` and `installers/debian`
- Scripts themselves sit in `scripts/` — copy or fork as needed
- Aliases reference the project root, so keep it somewhere permanent (e.g. `~/bin/bash-zoo`)

## Platform Support

| Feature | macOS | Debian / Ubuntu |
| --- | --- | --- |
| `mfa` | ✅ | ✅ |
| `share` | ⛔️ | ✅ |
| `uuid` | ⛔️ | ✅ |
| `zapp` + `zapper` | ⛔️ | ✅ |
| `forgit` | ✅ | ✅ |
| `wizard.sh` | ✅ *(Homebrew required for dependencies)* | ✅ *(APT and friends)* |

> The wizard gracefully exits on unsupported platforms without touching your system.

## Daily Use

After installation, reload your shell (`exec "$SHELL" -l`) or open a fresh terminal. The commands are now global:

```bash
mfa work/email        # Copy a TOTP token from pass
share send ./build    # Turn a folder into a one-time drop
forgit                # Audit every git repo under the current directory
```

Need a refresher inside the CLI? Run `<tool> --help` or read the source — each script is tiny and documented inline.

## Upgrading

```bash
cd path/to/bash-zoo
git pull
./wizard.sh          # Re-run to pick up new tools or dependencies
```

The wizard is idempotent: re-running only tweaks what changed and offers new toys as they land.

## Uninstall

```bash
./uninstall.sh
```

Then restart your shell so aliases disappear: `exec "$SHELL" -l`.

## Credits

- [Ben Chapman](https://github.com/0xbenc) — Maintainer
- [Ben Cully](https://github.com/BenCully) — Contributor

## License

[MIT](LICENSE)
