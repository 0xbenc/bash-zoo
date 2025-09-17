#!/usr/bin/env bash

set -Eeuo pipefail

tmux_start() {
  log_warn "Tmux orchestrator is not yet implemented; using standalone mode"
  fzf_start "$@"
}
