#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 2 ]]; then
  exit 0
fi

root="$1"
path="$2"

if [[ -z "$path" ]]; then
  exit 0
fi

"$root/bin/astra" --preview-only "$path" || true

if [[ -d "$path" ]]; then
  "$root/lib/core/render_controls_panel.sh"
fi
