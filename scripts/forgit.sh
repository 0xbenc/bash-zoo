#!/bin/bash

set -euo pipefail

# forgit: scan current directory (or given path) for git repos
# and report any with uncommitted changes or unpushed commits.
#
# UX: Uses gum spinner during discovery and for each repo during
# scanning, with the title showing "Scanning N/total: <repo>".
# Falls back to a single-line progress indicator if not a TTY or
# when gum isn't available. Final output remains unchanged.

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
  FORGIT_NO_NETWORK=1  Skip remote checks (no network)
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
  FG_RED=$'\033[31m'
else
  RESET=""; BOLD=""; DIM=""; FG_YELLOW=""; FG_MAGENTA=""; FG_CYAN=""; FG_GREEN=""; FG_RED=""
fi

# Resolve absolute base path for nicer relative names
base_abs=$(cd "$start_dir" && pwd)
# Derive a human-friendly root label; annotate when it's the current dir
cwd_abs=$(pwd)
root_disp="$start_dir"
if [[ "$base_abs" == "$cwd_abs" ]]; then
  root_disp="$(basename "$cwd_abs") (cwd)"
fi

# Small helpers for plain progress (TTY only, gum fallback)
progress_active=0
progress_update() { # $1 = message
  if [[ $is_tty -eq 1 ]]; then
    printf "\r\033[K%s%s%s" "$DIM" "$1" "$RESET"
    progress_active=1
  fi
}
progress_finish() {
  if [[ $is_tty -eq 1 && $progress_active -eq 1 ]]; then
    printf "\r\033[K\n"
    progress_active=0
  fi
}

# Ensure progress line is cleaned up on exit/interrupt
trap 'progress_finish || true' EXIT INT TERM

# Collect all repos by locating entries named ".git" (file or dir)
repos=()

# Use gum spinner during discovery; write to a temp file to preserve NUL separation
tmp_repos=$(mktemp "${TMPDIR:-/tmp}/forgit.repos.XXXXXX")
if [[ $is_tty -eq 1 ]]; then
  gum spin --spinner dot --title "Finding Git repositories under: $root_disp" -- \
    bash -c 'find "$1" -name .git -print0 > "$2" 2>/dev/null' _ "$start_dir" "$tmp_repos"
else
  bash -c 'find "$1" -name .git -print0 > "$2" 2>/dev/null' _ "$start_dir" "$tmp_repos"
fi
while IFS= read -r -d '' git_path; do
  repo_dir="${git_path%/.git}"
  repos+=("$repo_dir")
done <"$tmp_repos"
rm -f "$tmp_repos"

if [[ ${#repos[@]} -eq 0 ]]; then
  echo "No Git repositories found under: $root_disp"
  exit 0
fi

echo "${DIM}Scanning ${#repos[@]} Git repos under: ${root_disp}${RESET}"

# Gather results first to format neatly
out_repo=()
out_has_changes=()
out_ahead=() # values: number | no-upstream | 0
out_behind=() # values: number | unknown | stale | 0
out_branch=()

changes_count=0
ahead_count_total=0
ahead_no_upstream_count=0
behind_count_total=0
behind_unknown_total=0
behind_stale_total=0

total=${#repos[@]}
idx=0

# Build a small helper script to scan a single repo; used under gum spin
scan_script=$(mktemp "${TMPDIR:-/tmp}/forgit.scan.XXXXXX")
cat >"$scan_script" <<'EOS'
#!/bin/bash
set -euo pipefail
repo="$1"
no_network="${2:-}"

has_changes=0
has_remote_issue=0
ahead_state="0"
behind_state="0"

# Uncommitted/untracked changes
if [[ -n "$(git -C "$repo" status --porcelain 2>/dev/null || true)" ]]; then
  has_changes=1
fi

# Determine current branch (robustly)
branch_name="$(git -C "$repo" symbolic-ref --short -q HEAD 2>/dev/null || true)"
if [[ -n "$branch_name" ]]; then
  branch_disp="$branch_name"
else
  shorthash="$(git -C "$repo" rev-parse --short HEAD 2>/dev/null || true)"
  if [[ -n "$shorthash" ]]; then
    branch_disp="detached@$shorthash"
  else
    branch_disp="detached"
  fi
fi
branch_disp=${branch_disp//$'\r'/}
branch_disp=${branch_disp//$'\n'/ }

if [[ -n "$branch_name" ]]; then
  up_remote="$(git -C "$repo" config --get "branch.$branch_name.remote" 2>/dev/null || true)"
  up_merge="$(git -C "$repo" config --get "branch.$branch_name.merge" 2>/dev/null || true)"
  if [[ -z "$up_remote" || -z "$up_merge" || "$up_remote" == "." ]]; then
    if git -C "$repo" rev-parse HEAD >/dev/null 2>&1; then
      ahead_state="no-upstream"
      has_remote_issue=1
    fi
  else
    do_network=1
    if [[ -n "${no_network:-}" ]]; then do_network=0; fi
    remote_failed=0
    remote_commit=""
    if [[ $do_network -eq 1 ]]; then
      remote_commit="$(GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes" \
        git -C "$repo" ls-remote --exit-code "$up_remote" "$up_merge" 2>/dev/null \
        | awk 'NR==1 {print $1}' || true)"
      if [[ -z "$remote_commit" ]]; then remote_failed=1; fi
    else
      remote_failed=1
    fi

    if [[ $remote_failed -eq 0 ]]; then
      if git -C "$repo" cat-file -e "$remote_commit^{commit}" >/dev/null 2>&1; then
        lr_counts="$(git -C "$repo" rev-list --left-right --count "HEAD...$remote_commit" 2>/dev/null || echo "")"
        if [[ -n "$lr_counts" ]]; then
          ahead_n="${lr_counts%%$'\t'*}"
          behind_n_tmp="${lr_counts#*$'\t'}"
          if [[ -z "$ahead_n" ]]; then ahead_n=0; fi
          if [[ -z "$behind_n_tmp" || "$behind_n_tmp" == "$lr_counts" ]]; then behind_n_tmp=0; fi
          if [[ "$ahead_n" -gt 0 ]]; then
            ahead_state="$ahead_n"; has_remote_issue=1
          fi
          if [[ "$behind_n_tmp" -gt 0 ]]; then
            behind_state="$behind_n_tmp"; has_remote_issue=1
          fi
        fi
      else
        if git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
          ahead_n="$(git -C "$repo" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
          if [[ "${ahead_n:-0}" -gt 0 ]]; then
            ahead_state="$ahead_n"; has_remote_issue=1
          fi
        fi
        behind_state="unknown"; has_remote_issue=1
      fi
    else
      if git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
        ahead_n="$(git -C "$repo" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
        if [[ "${ahead_n:-0}" -gt 0 ]]; then
          ahead_state="$ahead_n"; has_remote_issue=1
        fi
      fi
      behind_state="stale"
    fi
  fi
fi

printf '%s\t%s\t%s\t%s\t%s\n' "$has_changes" "$has_remote_issue" "$ahead_state" "$behind_state" "$branch_disp"
EOS
chmod +x "$scan_script"
# Ensure cleanup and progress line finish
trap 'rm -f "$scan_script" 2>/dev/null || true; progress_finish || true' EXIT INT TERM

# Gum availability gate for per-repo spinner
use_gum=0
if [[ $is_tty -eq 1 ]] && command -v gum >/dev/null 2>&1; then
  use_gum=1
fi

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
  if [[ "$disp" == "." && "$base_abs" == "$cwd_abs" ]]; then
    disp="$root_disp"
  fi

  idx=$((idx+1))
  title="Scanning ${idx}/${total}: ${disp}"

  # Run the single-repo scan under gum spin when available
  res=""
  if [[ $use_gum -eq 1 ]]; then
    res=$(gum spin --spinner dot --title "$title" -- bash "$scan_script" "$repo" "${FORGIT_NO_NETWORK:-}")
  else
    progress_update "$title"
    res=$(bash "$scan_script" "$repo" "${FORGIT_NO_NETWORK:-}")
  fi

  # Parse results: has_changes, has_remote_issue, ahead_state, behind_state, branch_disp
  has_changes=0; has_remote_issue=0; ahead_state="0"; behind_state="0"; branch_disp=""
  IFS=$'\t' read -r has_changes has_remote_issue ahead_state behind_state branch_disp <<EOF
$res
EOF

  # Counters sourced directly from the scan helper results so we don't
  # re-run the expensive git checks.
  if [[ "$has_changes" == "1" ]]; then
    changes_count=$((changes_count+1))
  fi
  if [[ "$ahead_state" == "no-upstream" ]]; then
    ahead_no_upstream_count=$((ahead_no_upstream_count+1))
    ahead_count_total=$((ahead_count_total+1))
  elif [[ "$ahead_state" != "0" ]]; then
    ahead_count_total=$((ahead_count_total+1))
  fi
  if [[ "$behind_state" == "unknown" ]]; then
    behind_unknown_total=$((behind_unknown_total+1))
  elif [[ "$behind_state" == "stale" ]]; then
    behind_stale_total=$((behind_stale_total+1))
  elif [[ "$behind_state" != "0" ]]; then
    behind_count_total=$((behind_count_total+1))
  fi

  if [[ "$has_changes" == "1" || "$has_remote_issue" == "1" ]]; then
    out_repo+=("$disp")
    out_has_changes+=("$has_changes")
    out_ahead+=("$ahead_state")
    out_behind+=("$behind_state")
    out_branch+=("$branch_disp")
  fi
done

# Finish progress line before printing final results
progress_finish

if [[ ${#out_repo[@]} -eq 0 ]]; then
  # Explicitly state nothing needs attention (was easy to miss before)
  printf '%s\n' "${FG_GREEN}No repositories need attention.${RESET}"
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
  behind="${out_behind[$i]}"
  branch_disp="${out_branch[$i]}"

  parts=()
  if [[ "$chg" == "1" ]]; then
    parts+=("${FG_YELLOW}changes${RESET}")
  fi
  if [[ "$behind" == "unknown" ]]; then
    parts+=("${FG_RED}behind${RESET} ${DIM}(unknown)${RESET}")
  elif [[ "$behind" == "stale" ]]; then
    parts+=("${FG_RED}behind${RESET} ${DIM}(stale)${RESET}")
  elif [[ "$behind" != "0" ]]; then
    parts+=("${FG_RED}behind${RESET} ${DIM}(${behind})${RESET}")
  fi
  if [[ "$ahead" == "no-upstream" ]]; then
    parts+=("${FG_MAGENTA}ahead${RESET} ${DIM}(no remote)${RESET}")
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

summary_lines=(
  "changes: $changes_count"
  "ahead: $ahead_count_total (${ahead_no_upstream_count} no-remote)"
  "behind: $behind_count_total (${behind_unknown_total} unknown, ${behind_stale_total} stale)"
)

if [[ $is_tty -eq 1 ]] && command -v gum >/dev/null 2>&1; then
  gum_width=50
  for line in "${summary_lines[@]}"; do
    len=${#line}
    if [[ $len -gt $gum_width ]]; then
      gum_width=$len
    fi
  done
  gum style \
    --foreground 212 \
    --border-foreground 212 \
    --border double \
    --align center \
    --width "$gum_width" \
    --margin "1 2" \
    --padding "1 4" \
    "${summary_lines[@]}"
else
  for line in "${summary_lines[@]}"; do
    printf "${DIM}%s${RESET}\n" "$line"
  done
fi

exit 1
