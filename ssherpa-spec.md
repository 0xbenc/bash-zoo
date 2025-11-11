# Bash Zoo — Spec: ssherpa (gum‑only)

This document specifies `ssherpa`, a gum‑driven SSH helper that lists Host aliases from your OpenSSH config and makes it easy to add new ones interactively. It adheres to Bash Zoo constraints: Bash 3.2+ compatible, `set -euo pipefail`, no associative arrays, careful quoting, and atomic file writes.

---

## Goals & UX

- Make connecting to SSH hosts fast and memorable via aliases.
- Be helpful on fresh machines: if there are no aliases, drop straight into an interactive “add alias” flow.
- Keep the flow gum‑first and minimal for beginners, with power flags for experienced users.

---

## CLI

Primary usage (pick and connect):

```
ssherpa [--all] [--print|--exec] [--filter SUBSTR] [--user USER]
        [--no-color] [--config PATH]
        [--] [ssh-args...]
```

Subcommands (interactive authoring and fallback views):

```
ssherpa add [--alias NAME] [--host HOST] [--user USER]
            [--port 22] [--identity PATH]
            [--config PATH] [--dry-run] [--yes]
```

Defaults:
- Executes ssh after selection (`--exec`); use `--print` to echo the command.
- Shows only concrete Host aliases (no wildcards) unless `--all`.
- Config path defaults to `~/.ssh/config`.

Exit codes:
- `0` success (selection made or printed; or alias added)
- `1` usage or parsing failure
- `2` no hosts matched filter (picker) or write error (add)

---

## Behavior

### Config Loading

- Start from `~/.ssh/config` (or `--config`), if present.
- Parse `Include` directives and expand globs (e.g., `~/.ssh/config.d/*.conf`) breadth‑first, avoiding duplicates.
- Ignore `Match` blocks and conditionals (documented limitation).

### Alias Parsing

- On `Host` line, begin a new stanza; multiple names produce multiple entries sharing the same properties.
- Capture first occurrence of `HostName`, `User`, `Port`, and `IdentityFile`.
- Mark entries whose names contain `*` or `?` as patterns.
- Hide pattern entries by default; show with `--all`.

### Picker Behavior (Aliases Only)

- Build labels for each alias: `alias<TAB>user@hostname:port [key]`.
- Always include a synthetic option: `Add new alias…` as a dedicated picker row.
- If there are zero aliases, skip the picker and go straight into the add flow with a brief explainer.
- Output lines:
  - `[loaded] A alias(es)`
  - `[selected] alias → user@host:port`
  - `[exec] ssh <alias> …` or `[print] …`

### Add Flow (Interactive Authoring)

- Entry point: `ssherpa add` or picking “Add new alias…” from the empty picker.
- Prompts via gum:
  - Alias: `gum input` (must be a non‑empty token without spaces or wildcards).
  - HostName: `gum input` (hostname or IP).
  - User: `gum input` (default `$USER`).
  - Port: `gum input` (default `22`, digits only).
  - IdentityFile: `gum choose` from private keys under `~/.ssh` (e.g., `id_*`, excluding `*.pub`), plus “Other…” → `gum input` for a path.
- If an alias already exists:
  - Show a summary diff (old vs new key lines) and ask `gum confirm` to overwrite.
- Writing the stanza:
  - Format:
    ```
    Host <alias>
      HostName <hostname>
      User <user>
      Port <port>
      IdentityFile <path>
    ```
  - If the config file does not exist, create it with a header comment and a trailing newline.
  - Atomic write: write to a sibling temp file and `mv -f` into place.
  - Output: `[added] alias` or `[updated] alias`; on `--dry-run`, prefix with `would-`.
 - Quality of life: propose a sensible alias from the HostName (convert dots/hyphens to dashes, e.g., `db-10-0-0-5`).

### Picking & Connecting

- Build labels as tab‑delimited rows: `alias<TAB>user@hostname:port [key]` (use tab to extract alias reliably).
- `gum filter --limit 1` for selection; on confirm:
- `[selected] alias → user@host:port`
- `[exec] ssh alias ...` or `[print] ssh alias ...`

---

## Gum Usage

- Filtering/selection: `gum filter --placeholder "Filter SSH hosts…" --limit 1`.
- Inputs: `gum input --placeholder "..."` for alias/host/user/port.
- Choices: `gum choose` for identity file candidates.
- Confirms: `gum confirm` before overwriting existing aliases or writing a new config.

---

## Portability & Safety Notes

- Works with the default macOS Bash 3.2 (no associative arrays, no `mapfile`).
- Known_hosts parsing skips hashed entries (`|1|...`), which are not reversible.
- Add flow never escalates privileges and only writes the target config path.
- Atomic writes prevent partial config states.
- Duplicate alias names: last one wins (OpenSSH behavior); overwrite path replaces the prior stanza.

---

## Examples

```
ssherpa                       # pick an alias and connect; always offers “Add new alias…”
ssherpa --print -- -L 8080:localhost:8080
ssherpa add                   # guided creation of a new Host alias
ssherpa add --alias db --host 10.0.0.5 --user alice --identity ~/.ssh/id_ed25519 --yes
```

---

## Validation Recipes

- No config present:
  - `mv ~/.ssh/config ~/.ssh/config.bak` (temporarily) → `ssherpa` should open the add flow and create a new config after confirmation.
- Minimal config with two hosts → selection and connect/print
- Include globs under `~/.ssh/config.d/*.conf` → `[loaded]` reflects includes
- Add flow collision: create alias A, then re‑add A and confirm overwrite → `[updated] A`

---

## Acceptance Criteria

- Gum‑only UI; no fzf or other fallback.
- Helpful on new machines: seamless add flow when no aliases exist.
- Deterministic, grep‑friendly output lines for picker and add flows.
- Portable Bash 3.2+ code and atomic writes for config edits.
