#!/bin/sh
set -eu

REPO_URL="${BASH_ZOO_REPO_URL:-https://github.com/0xbenc/bash-zoo.git}"
BRANCH="${BASH_ZOO_BRANCH:-}"
KEEP_DIR="${BASH_ZOO_KEEP_DIR:-0}"

say() {
  printf '%s\n' "$*" >&2
}

die() {
  say "error: $*"
  exit 1
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    die "missing required command: $1"
  fi
}

need_cmd git
need_cmd mktemp

if command -v bash >/dev/null 2>&1; then
  BASH="bash"
elif [ -x "/bin/bash" ]; then
  BASH="/bin/bash"
else
  die "bash is required to run install.sh"
fi

tmp_dir="$(mktemp -d 2>/dev/null || mktemp -d -t bash-zoo)"
repo_dir="$tmp_dir/bash-zoo"

cleanup() {
  if [ "${KEEP_DIR}" = "1" ]; then
    say "kept clone at: ${repo_dir}"
    return 0
  fi
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT INT TERM HUP

say "cloning: ${REPO_URL}"
if [ -n "${BRANCH}" ]; then
  git clone --depth 1 --branch "${BRANCH}" "${REPO_URL}" "${repo_dir}" >/dev/null
else
  git clone --depth 1 "${REPO_URL}" "${repo_dir}" >/dev/null
fi

say "running: ./install.sh $*"
if [ -t 0 ]; then
  (cd "${repo_dir}" && exec "${BASH}" ./install.sh "$@")
elif [ -r /dev/tty ]; then
  (cd "${repo_dir}" && exec "${BASH}" ./install.sh "$@" </dev/tty)
else
  (cd "${repo_dir}" && exec "${BASH}" ./install.sh "$@")
fi

