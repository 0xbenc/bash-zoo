# Repository Guidelines

> Agents: before making non-trivial changes, read `docs/how-it-works.md` for an architecture and workflow overview (install, uninstall, self-update, metadata, portability, atomicity). Treat it as required onboarding.

## Project Structure & Modules
- `scripts/`: User-facing tools (`mfa.sh`, `uuid.sh`, `zapper.sh`, `zapp.sh`).
- `setup/`: Per-OS setup scripts named after each script.
  - `setup/debian/*.sh` (apt-based)
  - `setup/macos/*.sh` (Homebrew)
- `install.sh`: Interactive installer/alias configurator (detects Debian-like Linux vs. macOS).
- `README.md`: Usage and platform notes.
 - `docs/how-it-works.md`: Deep, agent-focused overview; read first.

## Coding Style & Naming
- Shell: Bash with `set -euo pipefail`; prefer portable constructs.
- macOS-only code must avoid Bash 4 features (no associative arrays, no `mapfile`). See `scripts/mfa.sh`.
- Filenames: lowercase-kebab, suffix `.sh` (matches setup scripts by name).
- Indentation: 2 spaces; wrap long pipelines; quote variables; prefer `$(...)` over backticks.
- Functions/vars: `lower_snake_case`; constants in all caps.
 - Architecture and flow details (atomic updates, metadata schema, update gating): see `docs/how-it-works.md`.

## Commit & Pull Requests
- Messages: short, imperative, and scoped (e.g., `mfa: handle empty store`). Current history favors concise, present-tense summaries.
- PRs should include:
  - Purpose and behavior change; commands run to verify (`./install.sh`, direct script calls).
  - Platform(s) tested and outputs (Debian/macOS).
  - Screenshots/terminal snippets where interactive flows are affected.
