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
their upstream. Shows the current branch for each flagged repository.
Exits with code 1 if any issues are found, else 0.

Environment:
  NO_COLOR=1    Disable colored output
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

# Color helpers (ANSI; disabled if NO_COLOR or non-tty)
is_tty=0
if [[ -t 1 ]]; then is_tty=1; fi
if [[ ${NO_COLOR:-} != "" ]]; then is_tty=0; fi

if [[ $is_tty -eq 1 ]]; then
  RESET=$'\033[0m'
  BOLD=$'\033[1m'
  DIM=$'\033[2m'
  FG_YELLOW=$'\033[33m'
  FG_MAGENTA=$'\033[35m'
  FG_CYAN=$'\033[36m'
  FG_GREEN=$'\033[32m'
else
  RESET=""; BOLD=""; DIM=""; FG_YELLOW=""; FG_MAGENTA=""; FG_CYAN=""; FG_GREEN=""
fi

# Resolve absolute base path for nicer relative names
base_abs=$(cd "$start_dir" && pwd)

# Collect all repos by locating entries named ".git" (file or dir)
repos=()
while IFS= read -r -d '' git_path; do
  repo_dir="${git_path%/.git}"
  repos+=("$repo_dir")
done < <(find "$start_dir" -name .git -print0 2>/dev/null)

if [[ ${#repos[@]} -eq 0 ]]; then
  echo "No Git repositories found under: $start_dir"
  exit 0
fi

echo "${DIM}Scanning ${#repos[@]} Git repos under: ${start_dir}${RESET}"

# Gather results first to format neatly
out_repo=()
out_has_changes=()
out_ahead=() # values: number | no-upstream | 0
out_branch=()

changes_count=0
ahead_count_total=0
ahead_no_upstream_count=0

for repo in "${repos[@]}"; do
  # Verify it's a working tree (skip bare or invalid entries)
  if ! git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    continue
  fi

  # Build a display path relative to base_abs when possible
  rep_abs=$(cd "$repo" && pwd)
  disp="$rep_abs"
  case "$rep_abs" in
    "$base_abs"/*) disp="${rep_abs#"$base_abs"/}" ;;
    "$base_abs")    disp="." ;;
  esac

  has_changes=0
  has_unpushed=0
  ahead_state="0"

  # Uncommitted/untracked changes
  if [[ -n "$(git -C "$repo" status --porcelain 2>/dev/null || true)" ]]; then
    has_changes=1; changes_count=$((changes_count+1))
  fi

  # Determine current branch (robustly) and ahead state
  # Prefer symbolic-ref (quiet) to avoid odd outputs and exit statuses
  branch_name="$(git -C "$repo" symbolic-ref --short -q HEAD 2>/dev/null || true)"
  if [[ -n "$branch_name" ]]; then
    branch_disp="$branch_name"
  else
    # Detached HEAD; try to show short commit
    shorthash="$(git -C "$repo" rev-parse --short HEAD 2>/dev/null || true)"
    if [[ -n "$shorthash" ]]; then
      branch_disp="detached@$shorthash"
    else
      branch_disp="detached"
    fi
  fi
  # Sanitize any stray newlines/carriage returns
  branch_disp=${branch_disp//$'\r'/}
  branch_disp=${branch_disp//$'\n'/ }

  if [[ -n "$branch_name" ]]; then
    if git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
      ahead_n="$(git -C "$repo" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
      if [[ "${ahead_n:-0}" -gt 0 ]]; then
        has_unpushed=1
        ahead_state="$ahead_n"
        ahead_count_total=$((ahead_count_total+1))
      fi
    else
      if git -C "$repo" rev-parse HEAD >/dev/null 2>&1; then
        has_unpushed=1
        ahead_state="no-upstream"
        ahead_no_upstream_count=$((ahead_no_upstream_count+1))
        ahead_count_total=$((ahead_count_total+1))
      fi
    fi
  fi

  if [[ $has_changes -eq 1 || $has_unpushed -eq 1 ]]; then
    out_repo+=("$disp")
    out_has_changes+=("$has_changes")
    out_ahead+=("$ahead_state")
    out_branch+=("$branch_disp")
  fi
done

if [[ ${#out_repo[@]} -eq 0 ]]; then
  echo "${FG_GREEN}All repositories are clean and pushed.${RESET}"
  exit 0
fi

# Compute padding width for repo names
pad=0
for name in "${out_repo[@]}"; do
  # crude byte-length; fine for typical ASCII paths
  n=${#name}
  if [[ $n -gt $pad ]]; then pad=$n; fi
done

echo "${BOLD}Needs attention (${#out_repo[@]}):${RESET}"

for i in "${!out_repo[@]}"; do
  name="${out_repo[$i]}"
  chg="${out_has_changes[$i]}"
  ahead="${out_ahead[$i]}"
  branch_disp="${out_branch[$i]}"

  parts=()
  if [[ "$chg" == "1" ]]; then
    parts+=("${FG_YELLOW}changes${RESET}")
  fi
  if [[ "$ahead" == "no-upstream" ]]; then
    parts+=("${FG_MAGENTA}ahead${RESET} ${DIM}(no upstream)${RESET}")
  elif [[ "$ahead" != "0" ]]; then
    parts+=("${FG_MAGENTA}ahead${RESET} ${DIM}(${ahead})${RESET}")
  fi

  # Join parts with comma + space without touching inner spaces
  status=""
  for j in "${!parts[@]}"; do
    if [[ $j -gt 0 ]]; then status+=", "; fi
    status+="${parts[$j]}"
  done

  # Print repo name, branch, then status
  if [[ -n "$status" ]]; then
    printf "  • %-${pad}s   ${FG_CYAN}(%s)${RESET}   %s\n" "$name" "$branch_disp" "$status"
  else
    printf "  • %-${pad}s   ${FG_CYAN}(%s)${RESET}\n" "$name" "$branch_disp"
  fi
done

# Summary line
printf "${DIM}%s${RESET}\n" "changes: $changes_count  |  ahead: $ahead_count_total (${ahead_no_upstream_count} no-upstream)"

exit 1
