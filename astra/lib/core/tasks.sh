#!/usr/bin/env bash

set -Eeuo pipefail

tasks_init() {
  ASTRA_TASK_LOG="$ASTRA_STATE_DIR/tasks.log"
  : >"$ASTRA_TASK_LOG"
}

tasks_record() {
  local message="$*"
  local timestamp
  timestamp=$(date '+%H:%M:%S')
  printf '[%s] %s\n' "$timestamp" "$message" >>"$ASTRA_TASK_LOG"
}

tasks_shutdown() {
  :
}
