# Bash Zoo: Self‑Update Plan (update zoo)

This document records the current, agreed design for adding self‑update capabilities to the Bash Zoo meta CLI.

## Scope & Goals
- Add `bash-zoo update zoo` to refresh installed tools and the meta CLI.
- Support two modes:
  - Regular: clone the repo into a temp dir and update changed files.
  - Dev: use a specified local folder (may have unpushed changes) as the source.
- Be portable (Debian/macOS), Bash 3.2+ compatible, and safe (atomic swaps).

## CLI Surface
- Command: `bash-zoo update zoo [--from PATH] [--repo URL] [--branch BR] [--dry-run] [--force] [--no-meta]`
- Optional compatibility alias: `bash-zoo update tools` → behaves the same.
- Flags:
  - `--from PATH`: Dev mode, use local folder as source; no git required.
  - `--repo URL`: Override repo URL for cloning (regular mode only).
  - `--branch BR`: Clone a specific branch/tag/commit (default: remote default).
  - `--dry-run`: Print planned actions only; do not modify the system.
  - `--force`: Apply updates regardless of version/commit (permits downgrades).
  - `--no-meta`: Skip meta CLI update.
- Env defaults:
  - `BASH_ZOO_REPO_URL`: Default repo URL when `--repo` is not provided.
  - `BASH_ZOO_BRANCH`: Default branch/ref when `--branch` is not provided.
  - Embedded default: the installed meta CLI embeds a `BASH_ZOO_REPO_URL` constant (set at install time) used if neither flag nor env is provided.

## Source Resolution (precedence)
1. If `--from PATH` is given, use it (must contain `scripts/` and `VERSION`).
2. Else, determine repo URL in this order:
   - `--repo URL` flag, if provided.
   - `BASH_ZOO_REPO_URL` env var, if set.
   - Embedded `BASH_ZOO_REPO_URL` constant inside the installed meta CLI (set by `install.sh` from `git remote get-url origin` when available).
3. Branch/ref determination:
   - `--branch BR` flag, if provided; else `BASH_ZOO_BRANCH` env; else clone default remote HEAD.

## Targets to Update
- Installed tools discovered via `discover_installed_tools()` and presence in bin dir.
- Meta CLI (`bash-zoo`) itself.
- Astra runtime assets if `astra` is installed (share root sync).
- Note: alias-installed tools are not overwritten; they are reported as “alias-installed (skipped)”.
  - Detection: treat a tool as alias-installed when no executable is present in either `~/.local/bin` or `~/bin`, but an alias is present in `~/.bashrc` or `~/.zshrc`. Such tools are reported as `[skipped-alias] name`.

## “Newer” Semantics
- No per-tool versions; use repo-level gate + per-file content diff.
- Regular mode (clone):
  - Read installed `installed.json` fields: `version` and `commit` (see Metadata below).
  - Read source `VERSION` and source commit (`git rev-parse HEAD`).
  - Update is allowed when either:
    - Source version > installed version (semantic numeric compare), or
    - Versions equal and installed commit is an ancestor of source commit, or
    - `--force` is set.
  - Never downgrade unless `--force`.
  - Shallow clones: to perform the ancestry check reliably, ensure sufficient history:
    - Attempt `merge-base`/`--is-ancestor` on the shallow clone.
    - If ancestry cannot be determined due to shallow history, fetch additional depth (e.g., `git fetch --depth 1000` or `--unshallow`) and retry.
    - If still indeterminate, do not update on equal versions (unless `--force`) and print a clear reason (e.g., “[skipped] ancestry unknown due to shallow clone”).
- Dev mode (`--from PATH`):
  - Skip forward-only gating; treat working tree as authoritative.
  - No git required; do not invoke any git commands in this mode.
- Per-file check: for each candidate, update when `cmp -s` detects content difference.

## Meta CLI Update Policy
- Default: update meta CLI when rendered content differs and the repo gate passes.
- Dev mode: update when rendered content differs (ignores forward-only gate).
- Overrides: `--no-meta` to skip; `--force` to allow downgrades.
- Render by substituting placeholders (`@VERSION@`, `@REPO_URL@`) into the meta CLI to produce `BASH_ZOO_VERSION` and `BASH_ZOO_REPO_URL`, compare vs installed file, and swap atomically.

## Astra Runtime Update
- If `astra` is installed, sync `astra` runtime (`astra/bin`, `astra/lib`, `astra/share`) into the share root.
- Use same-filesystem temp + double-rename to replace the runtime folder safely:
  - Stage the new runtime in a temp directory under the parent of the target.
  - Atomically rename the existing dir to a `.bak` sibling, then atomically rename the staged dir into place, then remove the `.bak` dir.

## Safety & Portability
- Bash with `set -euo pipefail`; avoid Bash 4-only features.
- No `sed -i`; write to temp files and `mv`.
- Atomic installs: copy to `*.tmp` and `mv -f` for files; for directories, use the double-rename strategy described above (portable across GNU/BSD `mv`).
- Use `mktemp -d`, `git clone --depth 1` when cloning; clean up temp dirs.
- No `gum` dependency; minimal stdout logging.
- Locate installed meta CLI path by checking both `~/.local/bin/bash-zoo` and `~/bin/bash-zoo` and prefer the existing one (mirrors uninstall logic).

## Metadata (installed.json)
- Location: share root from `resolve_share_root()`; file: `installed.json`.
- Extend schema to include:
  - `version`: repo VERSION string.
  - `commit`: short or full SHA of the source used to install/update (or `"unknown"`).
  - `repo_url`: source repo URL used.
  - `installed`: array of installed tool names (bins and aliases).
- `install.sh` and `update zoo` both maintain this file.
 - On update, preserve the existing `installed` array (merge with discovery results) and handle a missing or partial file gracefully by defaulting unspecified fields.

## UX & Output
- Progress lines per item: `[updated] name`, `[up-to-date] name`, `[skipped-alias] name`, `[failed] name (reason)`.
- Final summary: counts for updated / up-to-date / skipped / failed, plus the new repo `version` and `commit` if changed.
- `--dry-run` prints identical lines prefixed with `would-` (no changes made).
- When skipping an update due to indeterminate ancestry in shallow clones, print a clear reason and suggest `--force` if the user intends to accept equal-version updates without ancestry.

## Backward Compatibility
- Keep `bash-zoo update tools` as an alias for a few releases.
- Help text: document `update zoo` (and `update tools` alias) alongside `update passwords`.

## Implementation Outline
- scripts/bash-zoo.sh
  - Add constants via placeholders: `BASH_ZOO_VERSION` and `BASH_ZOO_REPO_URL`.
  - Add `update_zoo_cmd()` implementing the flow above.
  - Wire handler: `bash-zoo update zoo` (and alias `update tools`).
  - Helpers: `ensure_dir`, `atomic_install_file`, `atomic_replace_dir` (double-rename), `render_meta_cli`, `version_compare` (Bash 3-compatible), `read_installed_metadata`, `write_installed_metadata`.
  - Locate installed meta CLI by checking both bin dirs and operating on the one that exists.
  - Option parsing implemented with portable `while`/`case` (no `getopt`).
- install.sh
  - In `install_bash_zoo()`, substitute both `@VERSION@` and `@REPO_URL@` (URL from `git remote get-url origin` if available; else leave empty and require `--repo`/env for updates).
  - Extend `write_installed_metadata()` to add `commit` (`git rev-parse HEAD` if available) and `repo_url` when available.

## Verification Steps
1. Regular mode: `bash-zoo update zoo --dry-run` then `bash-zoo update zoo`.
2. Dev mode: edit a tool in a local clone; run `bash-zoo update zoo --from /path/to/clone --dry-run` then without `--dry-run`.
3. Confirm `bash-zoo version` matches source `VERSION` after update; compare binaries with `cmp -s`.
4. Verify `installed.json` contains `version`, `commit`, `repo_url` and the installed list.
5. Shallow clone gating: with equal versions and older installed commit, ensure ancestry gating works; if shallow history prevents determination, confirm a clear skip message and behavior unless `--force`.
6. Alias-only installs: verify `[skipped-alias]` behavior and that bin installs are not overwritten.
7. Meta CLI path resolution: verify updates work when installed in `~/.local/bin` and `~/bin`.
8. macOS/GNU differences: test `sed` and `mv` behavior on macOS to confirm portability of file swaps and directory double-rename.

## Future Enhancements
- Optional `--only name1,name2` filter flag.
- Report current vs source SHAs per tool by embedding a short hash comment in scripts at build time (if desired).
- Optional `--aliases` mode to refresh alias targets or convert aliases to bins.

Status: approved design; ready to implement.
