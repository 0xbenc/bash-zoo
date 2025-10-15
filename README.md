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

| Script | State | Superpower | Platforms | Extra Packages |
| --- | --- | --- | --- | --- |
| `airplane` | 🧪 experimental | Per-terminal offline mode: LAN allowed, WAN blocked | Debian/Ubuntu | installer applies firewall rules (root) |
| `astra` | 🧪 experimental | Terminal file manager with fuzzy search and previews | macOS, Debian/Ubuntu | `bash`, `fzf`, `jq`, `fd`/`fd-find`, `ripgrep`, `bat`, `chafa`, `poppler-utils`, `atool` |
| `forgit` | ✅ stable | Scan directories for Git repos needing commits or pushes | macOS, Debian/Ubuntu | `git` |
| `mfa` | ✅ stable | Generate TOTP codes from `pass` and copy them to your clipboard | macOS, Debian/Ubuntu | `pass`, `oathtool`, `fzf`, clipboard tool (`pbcopy`/`xclip`/`xsel`), optional `figlet` |
| `passage` | 🧪 experimental | Interactive GNU Pass browser with pins and MRU; copy or reveal password | macOS, Debian/Ubuntu | `pass`, platform clipboard utility |
| `share` | 🧪 experimental | Secure one-time file, folder, or clipboard transfer via magic‑wormhole | Debian/Ubuntu | `magic-wormhole`, `gnupg`, `tar`, clipboard tool (`xclip`/`xsel`) |
| `uuid` | ✅ stable | Create and copy a fresh UUID without leaving the terminal | macOS, Debian/Ubuntu | `uuidgen` (or Python 3), clipboard tool (`pbcopy`/`xclip`/`xsel`) |
| `zapp` | ✅ stable | Launch an AppImage or unpacked app stored under `~/zapps` | Debian/Ubuntu | none |
| `zapper` | ✅ stable | Prepare, validate, and register new apps for `zapp` with desktop entries | Debian/Ubuntu | `desktop-file-utils` |

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

`mfa` pulls TOTP codes from your [`pass`](https://www.passwordstore.org/) store, copies them to the clipboard, and shows a countdown until the next code rotation. It features fuzzy search (via `fzf`), optional big‑font display (`figlet`), and smart key‑bindings for quick selection. To make it work you need:

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

`passage` is an interactive browser for your GNU Pass store. It lists entries with search, supports favorites (pins) and MRU ordering, and uses a simple text menu (no fzf). You can:

- Copy the password (first line) directly.
- Reveal the password on screen until you clear it (also copies to clipboard).
- Toggle pin on an entry; pinned entries sort first.

Notes
- Requires `pass` and a clipboard adapter (`pbcopy`, `wl-copy`, `xclip`, or `xsel`).
- No TOTP (use `mfa` for TOTP codes).
- Safe defaults: no secrets printed unless you choose Reveal.
- Commands:
  - Type a number to select an entry; then choose an action (Enter copies by default).
  - `rN` reveal entry `N` (also copies). `pN` pin/unpin entry `N`.
  - `/term` filter list by substring; empty filter shows all again.
  - `O` via Options menu clears pins; `R` via Options menu clears recents.
  - `x` clears clipboard; `o` opens options; `q` quits.

### share

`share` turns a local file, directory, text string, or clipboard contents into a one‑time, PIN‑protected payload using symmetric GPG encryption and transfers it over magic‑wormhole. The receiver enters the human‑memorable wormhole code and the same PIN to decrypt; the original filename is preserved.

Examples:

```bash
# Send a file or directory (you’ll be prompted for a 4‑digit PIN)
share ./file.png
share ./some-folder/

# Send clipboard contents or ad‑hoc text
share --clipboard
share --text "Hello from Bash Zoo!"

# Receive on another machine
share --receive 23-barn-animal   # prompts for the PIN to decrypt
```

Notes:
- Directories are auto‑tarred before encryption; after receive you’re offered extraction.
- Clipboard mode uses `xclip`/`xsel` on Linux. macOS isn’t supported by this script yet (GNU `mktemp` flags used); Debian/Ubuntu is supported and packaged by the installer.

### uuid

`uuid` prints a fresh RFC 4122 v4 identifier and copies it to your clipboard so you can paste immediately into logs or dashboards. It prefers `uuidgen` when available, falls back to `/proc/sys/kernel/random/uuid` on Linux, and finally to Python 3’s `uuid` module.

Examples:

```bash
uuid               # prints and copies a v4 UUID
uuid | tee /dev/tty | pbcopy   # macOS: alternative copy path
```

Platform note:
- The script works on macOS and Linux. The guided installer currently provisions it on Debian/Ubuntu; on macOS you can still use it by running it directly from `scripts/uuid.sh` or adding your own alias.

### zapp

`zapp` launches AppImages or unpacked Linux apps staged under `~/zapps`. It lists available apps, accepts a single‑letter selection, and runs the best match inside the chosen folder:

1) `zapp.AppImage` if present and executable
2) The executable path named in `zapp.md`
3) Otherwise, it prompts you to pick from detected executables in the folder (or its single subfolder)

Example:

```bash
zapp   # interactive launcher; pick by letter
```

### zapper

`zapper` prepares new entries for `zapp` by validating the payload, creating a `zapp.md` pointing to the chosen executable, and writing a `.desktop` file so the app shows up in your launcher with an icon.

Examples:

```bash
zapper ~/Downloads/Foo.AppImage
zapper ~/Downloads/bar-1.2.3-linux-x64.tar.gz
```

What it does:
- Moves or extracts the payload into `~/zapps/<name>`
- Detects (or lets you choose) the main executable; records it in `zapp.md`
- Scans for icons near the executable and writes `~/.local/share/applications/zapp-<name>.desktop`

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
| `uuid` | ✅ | ✅ |
| `zapp` + `zapper` | ⛔️ | ✅ |
| `install.sh` | ✅ *(Homebrew required for dependencies)* | ✅ *(APT and friends)* |

Notes:
- The guided installer offers `uuid` on Debian/Ubuntu today; on macOS the script works out‑of‑the‑box if `uuidgen` and `pbcopy` exist, but we haven’t added a Homebrew installer yet.
- `share` currently targets Debian/Ubuntu because it uses GNU `mktemp` flags; macOS support would require minor script tweaks and a Homebrew formula set.

> The installer gracefully exits on unsupported platforms without touching your system.

## Daily Use

After installation, reload your shell (`exec "$SHELL" -l`) or open a fresh terminal. The commands are now global:

```bash
mfa work/email        # Copy a TOTP token from pass
share ./build         # Turn a folder into a one-time drop
forgit                # Audit every git repo under the current directory
astra                 # Launch the fuzzy-driven file manager in the current directory
uuid                  # Generate + copy a v4 UUID
zapper ~/Downloads/Foo.AppImage   # Prepare a new app for zapp
zapp                  # List and launch apps in ~/zapps
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

- [Vik Bhaduri](https://github.com/basedvik) — Contributor
- [Ben Chapman](https://github.com/0xbenc) — Maintainer
- [Ben Cully](https://github.com/BenCully) — Contributor


## License

[MIT](LICENSE)
