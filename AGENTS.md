# Repository Guidelines

## Project Structure & Modules
- `scripts/`: User-facing tools (`mfa.sh`, `share.sh`, `uuid.sh`, `zapper.sh`, `zapp.sh`).
- `installers/`: Per-OS installers named after each script.
  - `installers/debian/*.sh` (apt-based)
  - `installers/macos/*.sh` (Homebrew)
- `install.sh`: Interactive installer/alias configurator (detects Debian-like Linux vs. macOS).
- `README.md`: Usage and platform notes.

## Coding Style & Naming
- Shell: Bash with `set -euo pipefail`; prefer portable constructs.
- macOS-only code must avoid Bash 4 features (no associative arrays, no `mapfile`). See `scripts/mfa.sh`.
- Filenames: lowercase-kebab, suffix `.sh` (matches installers by name).
- Indentation: 2 spaces; wrap long pipelines; quote variables; prefer `$(...)` over backticks.
- Functions/vars: `lower_snake_case`; constants in all caps.

## Commit & Pull Requests
- Messages: short, imperative, and scoped (e.g., `mfa: handle empty store`). Current history favors concise, present-tense summaries.
- PRs should include:
  - Purpose and behavior change; commands run to verify (`./install.sh`, direct script calls).
  - Platform(s) tested and outputs (Debian/macOS).
  - Screenshots/terminal snippets where interactive flows are affected.
