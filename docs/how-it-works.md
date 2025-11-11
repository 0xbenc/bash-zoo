# Bash Zoo — How It Works (For Agents)

This document is a deep, implementation-oriented overview intended for AI agents (humans welcome). It captures the mental model, data flows, invariants, and portability constraints that shape the Bash Zoo toolkit.

The goal is to speed up contributions, debugging, and safe automation by conveying not just “what”, but “why” and “how” decisions are encoded in the repo.

---

## Quick Facts

- Shell: Bash with `set -euo pipefail`. Target macOS (Bash 3.2+) and Debian/Ubuntu.
- No Bash 4-only features on macOS (no associative arrays, no `mapfile`). Indexed arrays are allowed.
- Atomic file updates and safe directory swaps are first-class design constraints.
- UX is minimal: clear status lines and summaries; interactive flows use `gum` only where already required by installers/uninstallers.
- The meta CLI is always installed and self-updatable. Tools can be installed as binaries or as aliases in the user’s RC file.

---

## Key Components (Files & Roles)

- `install.sh` — Interactive installer and alias configurator. Detects OS, provisions binaries or aliases, embeds version/repo URL into the meta CLI (falling back to the canonical URL when no git remote is found), and writes `installed.json`.
- `scripts/bash-zoo.sh` — Meta CLI that provides:
  - `version` — prints `version: <label>` where `<label>` is the short commit hash or a dev label (e.g., `Local - Uncommitted`, `Local - <hash> (pushed)`).
  - `uninstall [--all]` — remove installed tools/aliases (with interactive selection via `gum` unless `--all`)
  - `update passwords` — per-folder `git` pull under `~/.password-store`
  - `update zoo` — refresh installed tools and the meta CLI (self-update)
- `scripts/*.sh` — User-facing tools (e.g., `mfa.sh`, `uuid.sh`, `zapp.sh`, `zapper.sh`, `forgit.sh`, `gpgobble.sh`, `passage.sh`, `killport.sh`, `ssherpa.sh`).
- `setup/<os>/<tool>.sh` — Per-tool setup helpers for Debian/macOS.
- `docs/update-zoo.md` — High-level self-update design (kept aligned with the code).
- `docs/how-it-works.md` — This document.

---

## Paths and OS Resolution

- Target bin directory:
  - Debian/Ubuntu: `~/.local/bin`
  - macOS and other: `~/bin`
  - Implemented via `resolve_target_dir()` in `scripts/bash-zoo.sh`.

- Share root (data directory) via `resolve_share_root()` in `scripts/bash-zoo.sh`:
  - macOS: `~/Library/Application Support/bash-zoo`
  - Linux: `${XDG_DATA_HOME:-$HOME/.local/share}/bash-zoo`

These helpers are single sources of truth used across install, update, and runtime logic.

---

## Metadata: installed.json

Location: `$(resolve_share_root)/installed.json`

Schema (written by installer and updater; both tolerate missing fields):

```json
{
  "version": "<string>",
  "commit": "<string|unknown>",
  "repo_url": "<string|empty>",
  "installed": ["tool1", "tool2", ...]
}
```

- `version` — From repo `VERSION` at install/update time. The value is a monotonic revision string in the form `rN` (e.g., `r3`). Revisions supersede legacy semantic versions used previously; any `rN` is considered newer than any `0.x.y`.
- `commit` — `git rev-parse HEAD` when available (unknown if not a git context).
- `repo_url` — `git remote get-url origin` when available (empty otherwise).
- `installed` — Union of tools installed as binaries and tools installed as aliases; excludes the meta CLI itself.

Reading is performed with portable `sed`/string ops (no JSON parser dependency). Writing is performed by both `install.sh` and `scripts/bash-zoo.sh` (update path).

---

## Installing (install.sh)

High-level flow:

1) Detect OS: macOS vs Debian-like Linux; bail out on unsupported.
2) Option parsing: `--all`, `--exp`, `--names <csv>` allow non-interactive flows and experimental tool inclusion.
3) Load registry `setup/registry.tsv` and filter tools by OS (and stability unless `--exp`).
4) Interactive selection via `gum` (unless `--all` or `--names`). On Linux, the installer ensures Homebrew is available: it uses the official script when non‑interactive sudo is available (system prefix), otherwise performs a user‑local install at `~/.linuxbrew`; then it installs `gum`.
5) For each selected tool:
   - Try to install a binary into `$(resolve_target_dir)`.
   - If the target dir is not writable, or copy fails: fall back to an alias in the user RC file (`~/.bashrc` or `~/.zshrc`).
6) Install the meta CLI unconditionally:
   - Render `scripts/bash-zoo.sh` by substituting `@VERSION@` and `@REPO_URL@` to embed `BASH_ZOO_VERSION` and `BASH_ZOO_REPO_URL`. If no git remote is available, embed the canonical default `https://github.com/0xbenc/bash-zoo.git`.
7) Ensure `PATH` contains the target bin directory (append a `# bash-zoo` tagged line in the RC file when needed).
8) Write `installed.json` with `version`, `commit`, `repo_url`, and the `installed` union.

Idempotency:
- Re-running the installer is safe and only updates what’s necessary (copy-on-change, alias update/replace, path line present check).
- Grouping: `zapp` and `zapper` are grouped as “zapps” in the interactive UI to simplify selection.

Portability constraints:
- No `sed -i` without handling BSD vs GNU differences. The installer probes `sed --version` to choose flags.
- Arrays are used, but not associative arrays.
- Always quote variables; prefer `$(...)` over backticks.

---

## Uninstalling (meta CLI)

Command: `bash-zoo uninstall [--all]`

Flow (scripts/bash-zoo.sh):

1) Build candidate list from known tools and detect presence as binaries and/or aliases in `~/.bashrc` and `~/.zshrc`.
2) Interactive selection via `gum` unless `--all`. On Linux, the CLI ensures Homebrew exists (system prefix with sudo, or user‑local at `~/.linuxbrew`) and installs `gum` if needed.
3) Apply removals:
   - Binaries: `rm -f` from the target bin directory.
   - Aliases: remove matching lines from RC files (portable `sed` handling for GNU/BSD).
   - Optional: remove the meta CLI itself if selected.
4) If no zoo binaries remain and the meta CLI was removed, strip `# bash-zoo` PATH lines from RC files.
5) Print a summary and recommend reloading the shell (`exec "$SHELL" -l`).

Design choice: Keep uninstall logic contained in the meta CLI so it works even if the repo is gone.

---

## Updating Password Stores (meta CLI)

Command: `bash-zoo update passwords`

Flow:
- Iterate each immediate child directory of `~/.password-store`.
- If a child is a git repo with an upstream configured, `git fetch` then compute state using `merge-base` and `rev-parse`:
  - `[up-to-date]`, `[updated]` (fast-forward), `[ahead]`, `[diverged]`, `[skipped]` (no upstream), `[failed]` (fetch/merge-base issues).
- Print a summary line with counters for each bucket.

Rationale: `pass` stores are commonly git-backed; this command centralizes “morning sync”.

---

## Self-Update (update zoo)

Command: `bash-zoo update zoo [--from PATH|URL] [--repo URL] [--branch BR] [--dry-run] [--force] [--no-meta]`

Concepts:
- Source resolution:
  - Dev mode: `--from PATH` uses a local working tree (no git required). The embedded version label becomes:
    - `Local - Uncommitted` — working tree has uncommitted changes
    - `Local - <short-hash> (pushed)` — clean; HEAD is contained in upstream
    - `Local - <short-hash> (unpushed)` — clean; ahead of upstream only
    - `Local - <short-hash> (diverged)` — clean; ahead and behind
    - `Local - <short-hash> (no upstream)` — clean; no upstream configured
  - URL mode: `--from URL` clones from the provided git URL (treated like regular mode).
  - Regular mode: clones a repo (depth 1 by default), with precedence: `--repo` → `BASH_ZOO_REPO_URL` → embedded `BASH_ZOO_REPO_URL` → `installed.json.repo_url` → canonical default URL.
  - Branch/ref: `--branch` or default remote HEAD.
- Forward-only gate (regular mode):
  - Compare `source VERSION` vs `installed.version` as revisions. If greater, allow.
    - Revisions are `rN`; if either side is a legacy semver (`0.x.y`), treat any `rN` as newer than any semver.
  - If equal, ensure `installed.commit` is an ancestor of `source HEAD`.
    - If history is too shallow to check ancestry, deepen (`--deepen 1000` or `--unshallow`) and retry.
    - If still indeterminate, skip equal-version updates unless `--force`.
  - `--force` bypasses the gate and permits downgrades.
- Per-file decision:
  - Candidate tools are the union of discovered installed tools and `installed.json.installed`.
  - Alias-only tools are skipped (`[skipped-alias] name`).
  - For binaries, update when `cmp -s` indicates content differs.
- Meta CLI update:
  - Unless `--no-meta`, render the meta CLI with placeholders and compare; update atomically on content difference (subject to gate in regular mode; dev mode always updates when content differs).
 
- Metadata write:
  - On non-dry runs, write `installed.json` with new `version`, `commit` (unknown in dev mode), `repo_url`, and merged installed list.

Additional runtime hardening:
- If placeholders `@VERSION@`/`@REPO_URL@` are encountered at runtime (e.g., when invoking an unrendered script), the updater treats them as unset and falls back to metadata or the canonical default URL. The `version` command reports the short commit hash when available, otherwise `unknown`.

User-visible output:
- Per-item lines: `[updated] name`, `[up-to-date] name`, `[skipped] name (reason)`, `[skipped-alias] name`, `[failed] name (reason)`.
- `--dry-run` prefixes with `would-` (e.g., `[would-updated]`).
- Final summary: `updated / up-to-date / failed / skipped` counters.

Safety and portability:
- No interactive dependencies (`gum` not required).
- Atomic file writes (temp + `mv -f`), and atomic directory swaps for runtimes.
- Portable `sed` and `tar` usage; avoid `sed -i` without OS checks.

Pseudocode (condensed):

```bash
# resolve source
if --from: mode=dev; source_dir=$FROM
else: repo=flag||env||embedded||installed.json; git clone --depth 1 repo [--branch]

# read versions/commits
src_version=$(cat source_dir/VERSION)
installed = read_installed_metadata()

# gate
if !force && mode==clone:
  case version_compare(src_version, installed.version):
    1 -> allow
    -1 -> deny
    0 -> allow if is-ancestor(installed.commit, source HEAD) else try deepen else deny

# collect candidates: discover_installed_tools ∪ installed.installed

# per-tool
for tool in candidates:
  if alias-only(tool): print [skipped-alias]
  elif no bin: print [skipped]
  elif cmp source/scripts/tool.sh vs bin: [up-to-date]
  else if gate denies: [up-to-date] (repo gate reason)
  else atomic_install_file -> [updated] or [failed]

 

# meta CLI
if !--no-meta:
  render with @VERSION@/@REPO_URL@ then cmp vs installed meta path
  update subject to gate (or always in dev) using atomic_install_file

# write metadata unless --dry-run
write_installed_metadata_update(version=src_version, commit, repo_url, names...)
```

---

## Atomicity Strategies

- Files: copy new content to a sibling temp file and `mv -f` into place (`atomic_install_file`). Ensures readers either see old or new content; never a partially written file.
- Directories (runtime payloads): stage the new directory under the parent, then swap with double-rename, and finally remove the backup (`atomic_replace_dir`). Works around differing GNU/BSD `mv` behavior and avoids partial states.

---

## Portability Notes

- `sed` — GNU vs BSD differences handled by probing `sed --version` where in-place edits are needed; otherwise write to new files.
- Arrays — Only indexed arrays used (macOS Bash 3 compatible). No associative arrays or `mapfile`.
- `mktemp` — Use `mktemp -d` for directories; always clean up best-effort.
- `tar` — Used to copy directory trees portably without non-POSIX options.
- Quoting — All paths are quoted; prefer `$(...)` over backticks.
- Port discovery — `killport` prefers `ss` on Linux (from `iproute2`) and falls back to `lsof`; on macOS it uses `lsof`. It never escalates privileges and defaults to the current user’s processes.

---

## Logging Conventions

- Deterministic, grep-friendly lines:
  - `[updated] name`
  - `[up-to-date] name`
  - `[skipped] name (reason)`
  - `[skipped-alias] name`
  - `[failed] name (reason)`
- Dry runs prefix with `would-`.
- Final `-- summary --` line with counters.

---

## Extending the Zoo (Adding a New Tool)

1) Create the tool script at `scripts/<name>.sh` (portable Bash, `set -euo pipefail`).
2) Add per-OS setup helpers as needed under `setup/debian/<name>.sh` and/or `setup/macos/<name>.sh`.
3) Register the tool in `setup/registry.tsv` with OS allowlist and description.
4) Update `scripts/bash-zoo.sh` `known_tools()` set.
5) Update README “Tools at a Glance” and “Tool Details”.
6) Optional: if the tool has runtime assets, place them in a directory structure designed to live under `$(resolve_share_root)` and adopt a double-rename strategy for updates.
7) Verify installation, uninstallation, and update flows:
   - `./install.sh --names <name>`
   - `bash-zoo update zoo --from ./ --dry-run`
   - `bash-zoo update zoo --from ./`
   - `bash-zoo uninstall --all` (if you created test installs)

---

## Troubleshooting & Diagnostics

- “No repo URL available” — Provide `--repo` or set `BASH_ZOO_REPO_URL` env if the embedded URL is empty.
- “git is required for cloning updates” — Use `--from` with a local working tree to avoid network/git, or install git.
- “ancestry unknown due to shallow clone” — Use `--force` if accepting equal-version updates without ancestry proof.
- macOS `sed` in-place differences — The code handles this; if you extend logic that edits files, follow the same pattern (probe GNU vs BSD).
- PATH/RC edits — Lines are tagged with `# bash-zoo` for safe identification/removal.

---

## Invariants and Guarantees

- Installer and updater never write partial files; updates are atomic.
- Alias-only installs are not silently converted to binaries by updates.
- Updater does not require `gum` or Homebrew.
- With equal versions in regular mode, forward-only updates require installed commit to be an ancestor of source HEAD.
- Dev mode is authoritative: it always updates when content differs.

---

## Decision Log (Selected)

- Prefer atomic swaps over in-place writes to prevent transient inconsistencies.
- Avoid `sed -i` portability pitfalls by writing to temp files or probing GNU/BSD features.
- Keep uninstall in the meta CLI to function without the repo.
- Use `cmp -s` for per-file update decisions to reduce system churn.
- Track only repo-level version; combine with commit ancestry for safe forward-only gating.
- Keep UI minimal; interactivity exists for install/uninstall flows where user choices matter.

---

## Test Recipes (Quick)

- Install/update cycle:
  - `./install.sh --names uuid,mfa,forgit`
  - `bash-zoo update zoo --from ./ --dry-run`
  - `bash-zoo update zoo --from ./`
- Passwords update:
  - `bash-zoo update passwords`
- Kill a dev server binding:
  - `python3 -m http.server 8080 &` then `killport 8080`
  - UDP example: `nc -u -l 5353 &` then `killport 5353 --udp --all --yes`
- Uninstall:
  - `bash-zoo uninstall --all`
- Regular update against remote:
  - `bash-zoo update zoo --repo https://github.com/0xbenc/bash-zoo.git --branch main --dry-run`

---

## Glossary

- Meta CLI — The `bash-zoo` binary installed into the user’s PATH.
- Share root — Platform-specific data directory from `resolve_share_root()`.
- Alias-only install — A tool present via shell alias but not as an executable in the target bin dir(s).
- Dev mode — Self-update sourcing from a local working tree (`--from PATH`) without `git`.
- Forward-only gate — Update policy: newer version or equal version with installed commit ancestor; `--force` bypasses.

---

This document aims to encode the reasoning behind the implementation so agents can modify, extend, or debug the Bash Zoo with confidence while preserving its safety and portability guarantees.
