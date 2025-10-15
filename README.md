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
git clone https://github.com/0xbenc/bash-zoo.git && cd bash-zoo && ./install.sh
```

## Table of Contents

- [Why Bash Zoo](#why-bash-zoo)
- [Tools at a Glance](#tools-at-a-glance)
- [Tool Details](#tool-details)
  - [airplane](#airplane)
  - [astra](#astra)
  - [forgit](#forgit)
  - [mfa](#mfa)
  - [passage](#passage)
  - [share](#share)
  - [uuid](#uuid)
  - [zapp](#zapp)
  - [zapper](#zapper)
- [Installation](#installation)
- [Platform Support](#platform-support)
- [Daily Use](#daily-use)
- [Upgrading](#upgrading)
- [Uninstall](#uninstall)
- [Credits](#credits)
- [License](#license)

## Why Bash Zoo

- **Curated shortcuts** · Everything is battle-tested for fast terminal workflows.
- **Zero-boilerplate install** · `install.sh` handles dependency checks, per-OS setup helpers, and aliases.
- **Portable by design** · Scripts are POSIX-friendly Bash and ship with Debian + macOS setup scripts.
- **Pick-your-pack** · Install individual tools or the whole enclosure — nothing gets forced into your path.

## Tools at a Glance

| Script | Superpower | Platforms | Extra Packages |
| --- | --- | --- | --- |
| `airplane` | Per-terminal offline mode: LAN allowed, WAN blocked | Debian/Ubuntu | installer applies firewall rules (root) |
| `astra` | Terminal file manager with fuzzy search and previews | macOS, Debian/Ubuntu | `bash`, `fzf`, `jq`, `fd`/`fd-find`, `ripgrep`, `bat`, `chafa`, `poppler-utils`, `atool` |
| `forgit` | Scan directories for Git repos needing commits or pushes | macOS, Debian/Ubuntu | `git` |
| `mfa` | Generate TOTP codes from `pass` and copy them to your clipboard | macOS, Debian/Ubuntu | `pass`, platform clipboard utility |
| `passage` | Interactive GNU Pass browser with pins and MRU; copy or reveal password | macOS, Debian/Ubuntu | `pass`, `fzf`, platform clipboard utility |
| `share` | Secure one-time file, folder, or clipboard transfer through a relay | Debian/Ubuntu | `curl`, `openssl`, `socat` |
| `uuid` | Create and copy a fresh UUID without leaving the terminal | Debian/Ubuntu | `xclip` |
| `zapp` | Launch an AppImage or unpacked app stored under `~/zapps` | Debian/Ubuntu | none |
| `zapper` | Prepare, validate, and register new apps for `zapp` with desktop entries | Debian/Ubuntu | `desktop-file-utils` |

## Tool Details

### airplane

`airplane` flips a single terminal into “offline mode” so tools you start there can serve the LAN but cannot reach the wider internet. Think: run `npm run dev` and your dev server is reachable from your phone/laptop on Wi‑Fi, but any outbound fetches to CDNs/APIs time out. Other terminals stay online. Linux only.

- Per‑terminal: `airplane` spawns a child shell. Leave with `exit`.
- LAN allowed: loopback and RFC1918 ranges (10/8, 172.16/12, 192.168/16, 169.254/16).
- WAN blocked: all other outbound traffic from that shell’s processes.
- Two modes:
  - strict (recommended, Linux): installer creates an `airplane` group plus iptables/ip6tables rules. `airplane` runs a subshell under that group so only those processes are restricted.
  - soft (fallback): if not installed system‑wide, `airplane` sets proxy env vars to a local blackhole with `NO_PROXY` for LAN/loopback. Covers most HTTP(S) tools, but not raw sockets.

Common flows
- `airplane` or `airplane on` — enter an offline subshell. Prompt shows `[airplane]` when possible.
- `airplane run <cmd>` — run a single command inside the offline environment.
- `airplane status` — print ON/OFF and mode.
- `airplane exit` (alias: `airplane land`, `airplane off`) — leave the airplane subshell; `exit` also works.

Notes
- Linux (Debian/Ubuntu): uses `iptables`/`ip6tables` to filter egress in the OUTPUT chain for group `airplane`. Requires sudo during install.
- IPv6: LAN link‑local (`fe80::/10`) and ULA (`fc00::/7`) are allowed in strict mode; everything else is blocked.

### astra

`astra` is a Bash-first terminal file manager that wraps `fzf`, `fd`, and `ripgrep` to stay fast while remaining approachable. The standalone UI streams directory listings through `fzf` with a live preview pane powered by `bat`, `chafa`, `pdftotext`, and friends. A static control panel now anchors to the bottom-right beneath the preview so shortcuts stay visible without crowding results. Core features include one-keystroke navigation, batch file operations, and JSON-based configuration. Headline keys: `Enter`/`→` to descend, `←`/`h` or the `[↑] ..` row to walk up, `.` to toggle hidden files, `Ctrl-G` for fuzzy name search, `Ctrl-Y` copy, `Alt-M` move, `Ctrl-D` delete, `Space` to tag multiple rows. See `astra/USAGE.md` for the full walkthrough. macOS and Debian users get the same code path; the setup scripts pull in Homebrew or APT dependencies so previews “just work.”

### forgit

`forgit` sweeps the directories beneath your current working tree and flags every Git repository with uncommitted changes or pending pushes. It also shows the current branch for each flagged repository so you can jump directly to the right place. Use it as a morning ritual to catch forgotten work: run `forgit` from `~/code` (or similar) and drill into repositories that show up with red or yellow markers. The script respects Git status output, so clean repos never clutter the list.

### mfa

`mfa` pulls TOTP codes from your [`pass`](https://www.passwordstore.org/) store, copies them to the clipboard, and shows a countdown until the next code rotation. To make it work you need:

1. **Dependencies** — Install `pass`, `oathtool`, and your platform clipboard helper (`pbcopy` on macOS, `xclip`/`xsel` on Debian).
2. **Initialize pass** — Generate (or reuse) a GPG key, then run `pass init <gpg-id>`. This creates `~/.password-store` as your encrypted vault.
3. **Store MFA secrets** — Create an entry for each service that ends in `/mfa`, because the script searches for files named `mfa.gpg`. The entry must contain a single-line base32 secret (no URIs, no extra lines). For example:

   ```bash
   export PASSWORD_STORE_DIR=~/.password-store  # optional if using the default
   pass insert work/github/mfa                  # paste base32 secret on one line
   ```

   Paste the raw base32 TOTP secret when prompted (single line). The file lands at `~/.password-store/work/github/mfa.gpg`.
4. **Sync across devices (optional)** — If you use git to sync your password store, commit the new entry so other machines running `mfa` can see it. The script respects `PASSWORD_STORE_DIR` if you keep the store somewhere else.

Once the store contains at least one `*/mfa` entry, run `mfa`, fuzzy-search the account, and the current 6-digit code lands in your clipboard. The countdown banner helps you see how long the code remains valid.

Security note: `mfa` never passes your secret as a command argument. It reads the single-line secret from `pass` and feeds it to `oathtool` via stdin to avoid exposure in process listings.

> All setup scripts live in `setup/<os>/<script>.sh` and match the script names one-to-one.

### passage

`passage` is an interactive browser for your GNU Pass store. It lists entries with fuzzy search, supports favorites (pins) and MRU ordering, and uses a persistent right-side preview to show instructions and results without leaving the main list. You can:

- Copy the password (first line) directly.
- Reveal the password on screen until you clear it (also copies to clipboard).
- Toggle pin on an entry; pinned entries sort first.

Notes
- Requires `pass` and `fzf` and a clipboard adapter (`pbcopy`, `wl-copy`, `xclip`, or `xsel`).
- No TOTP (use `mfa` for TOTP codes).
- Safe defaults: no secrets printed unless you choose Reveal.
- Keys (act on current selection; preview shows results):
  - `c`: Copy password (stays in fzf, preview shows “Copied”).
  - `r`: Reveal password in preview (also copies). `h` or `b` hides.
  - `p`: Pin/Unpin current entry (list reloads to reflect order).
  - `O`: Unpin all; `R`: Clear recents.
  - `x`: Clear clipboard.
  - `Esc`: Quit.
- Slot hotkeys (fast index jump like `mfa`):
  - `Ctrl+Letter` or `Alt+Letter`: copy that slot; `Alt+Shift+Letter`: reveal that slot.
  - These operate in-place and update the side preview.

### share

`share` turns a local file, directory, or even clipboard contents into a one-time payload that can be pulled down with a shell command on another machine. It wraps `curl`, `openssl`, and `socat` to encrypt the payload, create a temporary relay, and print the matching `share receive` command for your recipient. When the download completes, the relay tears itself down so nothing lingers on disk or over the wire.

### uuid

`uuid` gives you a fresh RFC 4122 identifier and handles clipboard copy so you can paste immediately into logs or dashboards. It ships with a subcommand layout (`uuid print`, `uuid copy`, etc.) but the bare command defaults to copying, which keeps your keystrokes minimal when filling out forms or provisioning new infra.

### zapp

`zapp` launches AppImages or unpacked Linux apps you have staged under `~/zapps`. It normalizes the environment so you do not need to remember `chmod +x` or where a particular binary lives. Drop an AppImage or directory into `~/zapps/<name>` and run `zapp <name>` to execute it with sensible defaults.

### zapper

`zapper` prepares new entries for `zapp` by validating the payload, creating desktop files, and wiring up icons so the app shows up in launchers. It is the on-ramp for new AppImages: point it at a download, answer the prompts, then use `zapp` for day-to-day launching. Re-running `zapper` lets you update icons or fix metadata without touching the existing installation.

## Installation

### Option A — Guided installer (recommended)

```bash
git clone https://github.com/0xbenc/bash-zoo
cd bash-zoo
./install.sh
```

- Auto-detects macOS vs. Debian/Ubuntu
- Shows which tools need additional packages before enabling
- Groups complementary tools (like the `zapps` pair) for easy onboarding
- Stores aliases so the commands travel with every new shell session
- By default shows only stable tools (`uuid`, `mfa`, `forgit`, and `zapp`/`zapper`).
- Include experimental tools by adding `--exp` (e.g., `./install.sh --exp`).
- Skip prompts with `./install.sh --all` (respects `--exp` filtering).

### Option B — Manual pick-and-run

```bash
./setup/<os>/<script>.sh
```

- OS-specific setup scripts live under `setup/macos` and `setup/debian`
- Scripts themselves sit in `scripts/` — copy or fork as needed
- Aliases reference the project root, so keep it somewhere permanent (e.g. `~/bin/bash-zoo`)

## Platform Support

| Feature | macOS | Debian / Ubuntu |
| --- | --- | --- |
| `airplane` | ⛔️ | ✅ |
| `astra` | ✅ *(Homebrew bash + deps required)* | ✅ |
| `forgit` | ✅ | ✅ |
| `mfa` | ✅ | ✅ |
| `passage` | ✅ | ✅ |
| `share` | ⛔️ | ✅ |
| `uuid` | ⛔️ | ✅ |
| `zapp` + `zapper` | ⛔️ | ✅ |
| `install.sh` | ✅ *(Homebrew required for dependencies)* | ✅ *(APT and friends)* |

> The installer gracefully exits on unsupported platforms without touching your system.

## Daily Use

After installation, reload your shell (`exec "$SHELL" -l`) or open a fresh terminal. The commands are now global:

```bash
mfa work/email        # Copy a TOTP token from pass
share send ./build    # Turn a folder into a one-time drop
forgit                # Audit every git repo under the current directory
astra                 # Launch the fuzzy-driven file manager in the current directory
```

Need a refresher inside the CLI? Run `<tool> --help` or read the source — each script is tiny and documented inline.

## Upgrading

```bash
cd path/to/bash-zoo
git pull
./install.sh         # Re-run to pick up new tools or dependencies
```

The installer is idempotent: re-running only tweaks what changed and offers new toys as they land.

## Uninstall

```bash
./uninstall.sh
./uninstall.sh --all  # remove every Bash Zoo alias and binary in one go
```

Then restart your shell so aliases disappear: `exec "$SHELL" -l`.

## Credits

- [Ben Chapman](https://github.com/0xbenc) — Maintainer
- [Ben Cully](https://github.com/BenCully) — Contributor

## License

[MIT](LICENSE)
