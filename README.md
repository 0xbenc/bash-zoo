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

```bash
curl -fsSL https://raw.githubusercontent.com/0xbenc/bash-zoo/HEAD/install-remote.sh | sh

# pass install.sh flags like this:
# curl -fsSL https://raw.githubusercontent.com/0xbenc/bash-zoo/HEAD/install-remote.sh | sh -s -- --all

git clone https://github.com/0xbenc/bash-zoo.git
cd bash-zoo
./install.sh
```

## Table of Contents

- [Why Bash Zoo](#why-bash-zoo)
- [Tools at a Glance](#tools-at-a-glance)
- [Tool Details](#tool-details)
  - [forgit](#forgit)
  - [gpgobble](#gpgobble)
  - [killport](#killport)
  - [hostshelper](#hostshelper)
  - [ssherpa](#ssherpa)
  - [yeet](#yeet)
  - [passage](#passage)
  - [uuid](#uuid)
  - [zapp](#zapp)
  - [zapper](#zapper)
- [Installation](#installation)
- [Platform Support](#platform-support)
- [Daily Use](#daily-use)
- [Upgrading](#upgrading)
- [Uninstall](#uninstall)
- [Meta CLI](#meta-cli)
- [Dependencies & References](#dependencies--references)
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
| `forgit` | ✅ stable | Scan directories for Git repos needing commits or pushes | macOS, Debian/Ubuntu | `git` |
| `gpgobble` | ✅ stable | Bulk‑import public keys and set ownertrust to FULL (4) for non‑local keys | macOS, Debian/Ubuntu | `gnupg` |
| `killport` | ✅ stable | Free a TCP/UDP port with gum selection, TERM→KILL, and wait | macOS, Debian/Ubuntu | `lsof` (Linux optionally `iproute2` for `ss`) |
| `hostshelper` | ✅ stable | Save host/IP pairs + presets and write them into `/etc/hosts` | macOS, Debian/Ubuntu | none (gum UI; sudo to write `/etc/hosts`) |
| `ssherpa` | ✅ stable | Alias-first SSH host picker + interactive config writer | macOS, Debian/Ubuntu | none (gum UI only) |
| `yeet` | ✅ stable | Eject removable flash drives with gum multi‑select | macOS, Debian/Ubuntu | `udisks2` (Linux) |
| `passage` | ✅ stable | Interactive GNU Pass browser with pins and MRU; copy or reveal password; built‑in TOTP (MFA) helpers | macOS, Debian/Ubuntu | `pass`, `oathtool`, platform clipboard utility |
| `uuid` | ✅ stable | Create and copy a fresh UUID without leaving the terminal | macOS, Debian/Ubuntu | `uuidgen` (or Python 3), clipboard tool (`pbcopy`/`xclip`/`xsel`) |
| `zapp` | ✅ stable | Launch an AppImage or unpacked app stored under `~/zapps` | Debian/Ubuntu | none |
| `zapper` | ✅ stable | Prepare, validate, and register new apps for `zapp` with desktop entries | Debian/Ubuntu | `desktop-file-utils` |

## Tool Details

### forgit

`forgit` sweeps the directories beneath your current working tree and flags every Git repository with uncommitted changes or pending pushes. It also shows the current branch for each flagged repository so you can jump directly to the right place. Use it as a morning ritual to catch forgotten work: run `forgit` from `~/code` (or similar) and drill into repositories that show up with red or yellow markers. The script respects Git status output, so clean repos never clutter the list.

Usage

```bash
forgit                       # audit every git repo under the current directory
forgit ~/code                # audit a specific path
forgit --timeout-secs 5      # per-repo remote check timeout (default: 10s)
FORGIT_NO_NETWORK=1 forgit   # skip remote checks (no network)
```

Notes
- The timeout applies to remote checks and helps skip slow/hung remotes.

### gpgobble

`gpgobble` bulk‑imports public keys from a directory and upgrades ownertrust to FULL (4) for keys that do not have a local secret key. It never downgrades trust and leaves ULTIMATE (5) alone.

Usage

```bash
gpgobble               # import all files in the current directory
gpgobble ./keys/work   # import from a specific folder
GNUPGHOME=/tmp/gnupg gpgobble ./keys
gpgobble -n ./keys     # dry-run: preview imports, localsigns, and trust changes
```

Notes
- Requires `gpg` (`gnupg`).
- Works with the default macOS Bash 3.2; no GNU `find` required.
 - Add `-n`/`--dry-run` to preview all actions without changing your keyring.

### killport

`killport` frees a TCP or UDP port by discovering listeners, letting you select them with a gum UI, and sending a gentle `TERM` followed by an optional `KILL` after a short grace. It never escalates privileges and defaults to your own processes only.

Usage

```bash
killport 3000                      # interactive select + confirm (TCP)
killport 5353 --udp --all --yes    # target all UDP listeners non-interactively
killport 8080 --list               # list found processes without acting
```

Notes
- gum-only UI. On Linux, prefers `ss` if available; otherwise uses `lsof`.
- Safe defaults: TERM → optional KILL after 3s; wait up to 5s for the port to free; never sudo.

### hostshelper

`hostshelper` keeps host/IP pairs and named presets in `~/.bash-zoo/hosthelper.toml`, then writes them into a managed block inside `/etc/hosts` with a gum UI. Add entries one field at a time, merge a single host into the block, or swap the block to a preset like `at-home`.

Usage

```bash
hostshelper   # gum TUI for adding hosts, building presets, and applying to /etc/hosts
```

Notes
- Gum-only UI; writing to `/etc/hosts` prompts for sudo.
- Managed block is wrapped with `# hostshelper start/end` and de-duplicates hostnames.
- Applying a preset replaces the managed block; applying a single host merges with the current block.

### ssherpa

`ssherpa` scans your `~/.ssh/config` and any `Include`d files, lists your Host entries, and lets you fuzzy-pick one with gum to connect. By default it hides pattern hosts (those with `*` or `?`), but you can include them with `--all`. It also includes an interactive “Add new alias…” flow to create or update Host stanzas in your config (atomic write, no sudo).

Usage

```bash
ssherpa                          # pick and connect (always offers “Add new alias…”)
ssherpa --print -- -L 8080:localhost:8080    # print the ssh command
ssherpa --filter prod --user alice            # prefilter by text and user
ssherpa --all                                 # include wildcard patterns too
```

Notes
- Gum-only UI; no fzf. It parses `Host`, `HostName`, `User`, `Port`, and first `IdentityFile`. `Match` blocks are ignored.
- Labels show `user@host:port [key]` when present; connection is always `ssh <alias>` so your config fully applies.
- Entries with `User git` are hidden by default; set `SSHERPA_IGNORE_USER_GIT=0` in your shell config to include them.

### yeet

`yeet` scans for removable USB drives and lets you eject one or more at once with a gum multi‑select UI. It shows a friendly volume/device name alongside the raw device path, then safely ejects via `diskutil eject` on macOS or `udisksctl power-off`/`eject` on Linux.

Usage

```bash
yeet   # select one or more drives to eject
```

Notes
- On Linux, `udisksctl` is preferred; `eject` is used as a fallback.

Passage’s built‑in TOTP support uses the same `/mfa` convention as the former `mfa` helper. To make MFA work smoothly you need:

1. **Dependencies** — Install `pass`, `oathtool`, and your platform clipboard helper (`pbcopy` on macOS, `xclip`/`xsel` on Debian).
2. **Initialize pass** — Generate (or reuse) a GPG key, then run `pass init <gpg-id>`. This creates `~/.password-store` as your encrypted vault.
3. **Store MFA secrets** — Create an entry for each service that ends in `/mfa`. The entry must contain a single-line base32 secret (no URIs, no extra lines). For example:

   ```bash
   export PASSWORD_STORE_DIR=~/.password-store  # optional if using the default
   pass insert work/github/mfa                  # paste base32 secret on one line
   ```

   Paste the raw base32 TOTP secret when prompted (single line). The file lands at `~/.password-store/work/github/mfa.gpg`.
4. **Sync across devices (optional)** — If you use git to sync your password store, commit the new entry so other machines can see it. Passage respects `PASSWORD_STORE_DIR` if you keep the store somewhere else.

Once the store contains at least one `*/mfa` entry, run `passage mfa` to start directly in an MFA-only view, fuzzy-search the account, and copy the current 6‑digit code.

Security note: Passage never passes your secret as a command argument. It reads the single-line secret from `pass` and feeds it to `oathtool` via stdin to avoid exposure in process listings.

> All setup scripts live in `setup/<os>/<script>.sh` and match the script names one-to-one.

### passage

`passage` is an interactive browser for your GNU Pass store. It lists entries with search, supports favorites (pins) and MRU ordering, and uses a simple text menu (no fzf). It also includes built‑in TOTP for entries that store a sibling `mfa` secret. You can:

- Copy the password (first line) directly.
- Reveal the password on screen until you clear it (also copies to clipboard).
- Toggle pin on an entry; pinned entries sort first.
- Start directly in MFA-only view with `passage mfa`.

Notes
- Requires `pass` and a clipboard adapter (`pbcopy`, `wl-copy`, `xclip`, or `xsel`). For TOTP actions, install `oathtool`.
- Built‑in TOTP: entries ending in `/mfa` (or with a sibling `…/mfa`) expose OTP actions. Use `tN`/`Nt` to show the current code (also copies). Press `m` to toggle an MFA‑only view.
- Safe defaults: no secrets printed unless you choose Reveal.
- Commands:
  - Type a number to select an entry; then choose an action (Enter copies by default).
  - `cN` or `Nc` copy entry `N`. `rN` or `Nr` reveal entry `N` (also copies). `tN` or `Nt` show a TOTP for entry `N` when available (also copies). `pN` or `Np` pin/unpin entry `N`.
  - `m` toggles an MFA‑only view (shows only entries with `/mfa`).
  - `/term` filter list by substring; empty filter shows all again.
  - `O` via Options menu clears pins; `R` via Options menu clears recents.
  - `x` clears clipboard; `o` opens options; `q` quits.

 

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

Prerequisites
- Install Homebrew, gum, and figlet before running the installer.
  - macOS
    - Install Homebrew: `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
    - Install gum: `brew install gum`
    - Install figlet: `brew install figlet`
  - Debian/Ubuntu
    - Install Homebrew (Linuxbrew): `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
    - Ensure brew is in PATH for this shell: `eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"`
    - Install gum: `brew install gum`
    - Install figlet: `brew install figlet`

### Option A — Guided installer (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/0xbenc/bash-zoo/HEAD/install-remote.sh | sh

# pass install.sh flags like this:
# curl -fsSL https://raw.githubusercontent.com/0xbenc/bash-zoo/HEAD/install-remote.sh | sh -s -- --all

git clone https://github.com/0xbenc/bash-zoo
cd bash-zoo
./install.sh
```

- Auto-detects macOS vs. Debian/Ubuntu
- Shows which tools need additional packages before enabling
- Groups complementary tools (like the `zapps` pair) for easy onboarding
- Stores aliases so the commands travel with every new shell session
- By default shows only stable tools (`uuid`, `forgit`, `gpgobble`, and `zapp`/`zapper`).
- Include experimental tools by adding `--exp` (e.g., `./install.sh --exp`).
- Skip prompts with `./install.sh --all` (respects `--exp` filtering).
- Interactive picker also includes an "All" option to select everything.
- Gum and figlet are required dependencies for the interactive selector and large-code displays. The installer does not install prerequisites; ensure `brew`, `gum`, and `figlet` are set up first.

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
 
| `forgit` | ✅ | ✅ |
| `gpgobble` | ✅ | ✅ |
| `passage` | ✅ | ✅ |
 
| `uuid` | ✅ | ✅ |
| `zapp` + `zapper` | ⛔️ | ✅ |
| `install.sh` | ✅ *(Homebrew required for dependencies)* | ✅ *(APT and friends)* |

Notes:
- The guided installer offers `uuid` on Debian/Ubuntu today; on macOS the script works out‑of‑the‑box if `uuidgen` and `pbcopy` exist, but we haven’t added a Homebrew installer yet.

> The installer gracefully exits on unsupported platforms without touching your system.

## Daily Use

After installation, reload your shell (`exec "$SHELL" -l`) or open a fresh terminal. The commands are now global:

```bash
passage mfa           # Start in MFA-only view for TOTP codes
forgit                # Audit every git repo under the current directory
uuid                  # Generate + copy a v4 UUID
zapper ~/Downloads/Foo.AppImage   # Prepare a new app for zapp
zapp                  # List and launch apps in ~/zapps
```

Need a refresher inside the CLI? Run `<tool> --help` or read the source — each script is tiny and documented inline.

## Upgrading

If you’ve installed the meta CLI, prefer the self-update command:

```bash
bash-zoo update zoo             # refresh installed tools + meta CLI
bash-zoo update zoo --dry-run   # show what would change
```

Developing locally? Point updates at a working tree:

```bash
bash-zoo update zoo --from /path/to/local/clone --dry-run
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
