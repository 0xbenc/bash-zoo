#!/bin/bash

set -euo pipefail

# forgit: scan current directory (or given path) for git repos
# and report any with uncommitted changes or unpushed commits.

usage() {
  cat <<'EOF'
forgit: find repos with work to finish

Usage:
  forgit [PATH]

Checks PATH (default: current directory) recursively for Git repositories
and reports any that have uncommitted changes or commits not pushed to
their upstream. Exits with code 1 if any issues are found, else 0.
EOF
}

start_dir="${1:-.}"
if [[ "$start_dir" == "-h" || "$start_dir" == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -d "$start_dir" ]]; then
  echo "Error: PATH is not a directory: $start_dir" >&2
  exit 2
fi

# Collect all repos by locating entries named ".git" (file or dir)
repos=()
while IFS= read -r -d '' git_path; do
  # Remove trailing '/.git' to get the repo root
  repo_dir="${git_path%/.git}"
  repos+=("$repo_dir")
done < <(find "$start_dir" -name .git -print0 2>/dev/null)

if [[ ${#repos[@]} -eq 0 ]]; then
  echo "No Git repositories found under: $start_dir"
  exit 0
fi

found_issues=0

echo "Scanning ${#repos[@]} Git repos under: $start_dir"

for repo in "${repos[@]}"; do
  # Verify it's a working tree (skip bare or invalid entries)
  if ! git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    continue
  fi

  # Determine repo display name (relative path if under CWD)
  disp="$repo"
  case "$disp" in
    ./*) disp="${disp#./}" ;;
  esac

  has_changes=0
  has_unpushed=0
  ahead_count="0"

  # Uncommitted/untracked changes
  status_out="$(git -C "$repo" status --porcelain 2>/dev/null || true)"
  if [[ -n "$status_out" ]]; then
    has_changes=1
  fi

  # Unpushed commits (ahead of upstream). If no upstream, consider as needing push
  branch="$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)"
  if [[ "$branch" != "HEAD" ]]; then
    if git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
      ahead_count="$(git -C "$repo" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
      if [[ "${ahead_count:-0}" -gt 0 ]]; then
        has_unpushed=1
      fi
    else
      # No upstream set; if repo has at least one commit, flag as unpushed
      if git -C "$repo" rev-parse HEAD >/dev/null 2>&1; then
        has_unpushed=1
        ahead_count="no-upstream"
      fi
    fi
  fi

  if [[ $has_changes -eq 1 || $has_unpushed -eq 1 ]]; then
    found_issues=1
    msg=""
    if [[ $has_changes -eq 1 ]]; then
      msg+="CHANGES"
    fi
    if [[ $has_unpushed -eq 1 ]]; then
      if [[ -n "$msg" ]]; then msg+=" | "; fi
      if [[ "$ahead_count" == "no-upstream" ]]; then
        msg+="AHEAD (no upstream)"
      else
        msg+="AHEAD ${ahead_count}"
      fi
    fi
    echo "- [$msg] $disp"
  fi
done

if [[ $found_issues -eq 0 ]]; then
  echo "All repositories are clean and pushed."
  exit 0
else
  exit 1
fi

