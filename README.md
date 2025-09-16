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

> For power users and n00bs, anybody not afraid of the terminal emulator

## TL;DR

```bash
git clone https://github.com/xbenc/bash-zoo.git && cd bash-zoo && ./wizard.sh
```

## Table of Contents

- [Why Bash Zoo](#why-bash-zoo)
- [Tools at a Glance](#tools-at-a-glance)
- [Tool Details](#tool-details)
  - [forgit](#forgit)
  - [share](#share)
  - [uuid](#uuid)
  - [zapp](#zapp)
  - [zapper](#zapper)
  - [mfa](#mfa)
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

## Tool Details

### forgit

`forgit` sweeps the directories beneath your current working tree and flags every Git repository with uncommitted changes or pending pushes. Use it as a morning ritual to catch forgotten work: run `forgit` from `~/code` (or similar) and drill into repositories that show up with red or yellow markers. The script respects Git status output, so clean repos never clutter the list.

### share

`share` turns a local file, directory, or even clipboard contents into a one-time payload that can be pulled down with a shell command on another machine. It wraps `curl`, `openssl`, and `socat` to encrypt the payload, create a temporary relay, and print the matching `share receive` command for your recipient. When the download completes, the relay tears itself down so nothing lingers on disk or over the wire.

### uuid

`uuid` gives you a fresh RFC 4122 identifier and handles clipboard copy so you can paste immediately into logs or dashboards. It ships with a subcommand layout (`uuid print`, `uuid copy`, etc.) but the bare command defaults to copying, which keeps your keystrokes minimal when filling out forms or provisioning new infra.

### zapp

`zapp` launches AppImages or unpacked Linux apps you have staged under `~/zapps`. It normalizes the environment so you do not need to remember `chmod +x` or where a particular binary lives. Drop an AppImage or directory into `~/zapps/<name>` and run `zapp <name>` to execute it with sensible defaults.

### zapper

`zapper` prepares new entries for `zapp` by validating the payload, creating desktop files, and wiring up icons so the app shows up in launchers. It is the on-ramp for new AppImages: point it at a download, answer the prompts, then use `zapp` for day-to-day launching. Re-running `zapper` lets you update icons or fix metadata without touching the existing installation.

### mfa

`mfa` pulls TOTP codes from your [`pass`](https://www.passwordstore.org/) store, copies them to the clipboard, and shows a countdown until the next code rotation. To make it work you need:

1. **Dependencies** — Install `pass`, `oathtool`, and your platform clipboard helper (`pbcopy` on macOS, `xclip`/`xsel` on Debian).
2. **Initialize pass** — Generate (or reuse) a GPG key, then run `pass init <gpg-id>`. This creates `~/.password-store` as your encrypted vault.
3. **Store MFA secrets** — Create an entry for each service that ends in `/mfa`, because the script searches for files named `mfa.gpg`. For example:

   ```bash
   export PASSWORD_STORE_DIR=~/.password-store  # optional if using the default
   pass insert --multiline work/github/mfa
   ```

   Paste the raw TOTP secret (or URI) when prompted. The file lands at `~/.password-store/work/github/mfa.gpg`.
4. **Sync across devices (optional)** — If you use git to sync your password store, commit the new entry so other machines running `mfa` can see it. The script respects `PASSWORD_STORE_DIR` if you keep the store somewhere else.

Once the store contains at least one `*/mfa` entry, run `mfa`, fuzzy-search the account, and the current 6-digit code lands in your clipboard. The countdown banner helps you see how long the code remains valid.

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
