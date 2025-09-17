#!/usr/bin/env bash

set -Eeuo pipefail

search_list_directory() {
  local dir="$1"
  local include_hidden="$2"

  if [[ ! -d "$dir" ]]; then
    return 1
  fi

  local entries=()
  if [[ -n "$ASTRA_FD_CMD" ]]; then
    if [[ "$include_hidden" == true ]]; then
      while IFS= read -r rel; do
        rel=${rel%/}
        entries+=("$rel")
      done < <(cd "$dir" && "$ASTRA_FD_CMD" --max-depth 1 --min-depth 1 --hidden --strip-cwd-prefix --color never)
    else
      while IFS= read -r rel; do
        rel=${rel%/}
        entries+=("$rel")
      done < <(cd "$dir" && "$ASTRA_FD_CMD" --max-depth 1 --min-depth 1 --strip-cwd-prefix --color never)
    fi
  else
    if [[ "$include_hidden" == true ]]; then
      while IFS= read -r entry; do
        entries+=("$(basename "$entry")")
      done < <(find "$dir" -mindepth 1 -maxdepth 1 -print)
    else
      while IFS= read -r entry; do
        local base
        base=$(basename "$entry")
        [[ "$base" == .* ]] && continue
        base=${base%/}
        entries+=("$base")
      done < <(find "$dir" -mindepth 1 -maxdepth 1 -print)
    fi
  fi

  local dirs=() links=() files=() others=()
  local rel abs
  for rel in "${entries[@]}"; do
    [[ -z "$rel" ]] && continue
    abs="$dir/$rel"
    if [[ -d "$abs" ]]; then
      dirs+=("$rel")
    elif [[ -L "$abs" ]]; then
      links+=("$rel")
    elif [[ -f "$abs" ]]; then
      files+=("$rel")
    else
      others+=("$rel")
    fi
  done

  local parent
  if [[ "$dir" != "/" ]]; then
    parent=$(cd "$dir/.." && pwd)
    printf '%s\t%s\n' "$(search_format_display up "..")" "$parent"
  fi

  search_emit_sorted "$dir" dir   "${dirs[@]}"
  search_emit_sorted "$dir" link  "${links[@]}"
  search_emit_sorted "$dir" file  "${files[@]}"
  search_emit_sorted "$dir" other "${others[@]}"
}

search_emit_sorted() {
  local base_dir="$1" type="$2"
  shift 2
  if [[ $# -eq 0 ]]; then
    return
  fi
  local sorted rel resolved display
  sorted=$(printf '%s\n' "$@" | LC_ALL=C sort)
  while IFS= read -r rel; do
    [[ -z "$rel" ]] && continue
    if [[ "$type" == up ]]; then
      resolved="$base_dir"
    else
      resolved=$(cd "$base_dir" && cd "$rel" 2>/dev/null && pwd || printf '%s/%s' "$base_dir" "$rel")
    fi
    display=$(search_format_display "$type" "$rel")
    printf '%s\t%s\n' "$display" "$resolved"
  done <<<"$sorted"
}

search_format_display() {
  local type="$1"
  local name="$2"
  case "$type" in
    dir)
      printf '[D] %s/' "$name"
      ;;
    link)
      printf '[L] %s@' "$name"
      ;;
    up)
      printf '[↑] %s' "$name"
      ;;
    *)
      printf '[F] %s' "$name"
      ;;
  esac
}

search_name() {
  local dir="$1"
  local query="$2"
  local include_hidden="$3"
  if [[ -z "$query" ]]; then
    query='.'
  fi
  if [[ -n "$ASTRA_FD_CMD" ]]; then
    local cmd=("$ASTRA_FD_CMD" --color never --absolute-path)
    if [[ "$include_hidden" == true ]]; then
      cmd+=(--hidden)
    fi
    cmd+=("$query" "$dir")
    "${cmd[@]}"
  else
    if [[ "$include_hidden" == true ]]; then
      find "$dir" -iname "*${query}*" -print
    else
      find "$dir" -iname "*${query}*" ! -path '*/.*' -print
    fi
  fi
}

search_content() {
  local dir="$1"
  local pattern="$2"
  if command -v rg >/dev/null 2>&1; then
    rg --line-number --no-heading --color never "$pattern" "$dir"
  else
    grep -Rin "$pattern" "$dir"
  fi
}

search_extract_path() {
  local line="$1"
  local display path
  IFS=$'\t' read -r display path <<<"$line"
  if [[ -n "$path" ]]; then
    printf '%s' "$path"
  else
    printf '%s' "$display"
  fi
}
