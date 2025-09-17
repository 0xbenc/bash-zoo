#!/usr/bin/env bash

set -Eeuo pipefail

preview_show() {
  local path="$1"
  if [[ -z "$path" ]]; then
    echo "[astra] no selection"
    return 0
  fi
  if [[ ! -e "$path" ]]; then
    echo "[astra] path missing: $path"
    return 0
  fi

  local cache_file mime="" use_image_protocol=0 allow_cache=1
  cache_file=$(preview_cache_file "$path")
  if [[ ! -d "$path" ]]; then
    mime=$(preview_mime_type "$path")
  fi
  case "$ASTRA_TERM_IMG" in
    kitty|wezterm|iterm2)
      use_image_protocol=1
      ;;
  esac

  if (( use_image_protocol == 1 )) || [[ ${mime} == image/* ]]; then
    allow_cache=0
    rm -f "$cache_file"
  fi

  if [[ -f "$cache_file" ]]; then
    if [[ $use_image_protocol -eq 1 ]]; then
      preview_emit_image_clear
    fi
    cat "$cache_file"
    return 0
  fi

  local tmp
  tmp="$cache_file.tmp"
  if preview_render "$path" "$mime" >"$tmp" 2>/dev/null; then
    if [[ $use_image_protocol -eq 1 ]]; then
      preview_emit_image_clear
    fi
    cat "$tmp"
    if (( allow_cache == 1 )); then
      mv "$tmp" "$cache_file"
    else
      rm -f "$tmp"
    fi
  else
    rm -f "$tmp"
    echo "[astra] preview unavailable"
  fi
}

preview_mime_type() {
  local path="$1"
  file --mime-type -Lb -- "$path" 2>/dev/null || echo application/octet-stream
}

preview_cache_file() {
  local path="$1"
  local sig
  sig=$(preview_signature "$path")
  printf '%s/%s.txt' "$ASTRA_PREVIEW_CACHE" "$sig"
}

preview_emit_image_clear() {
  case "$ASTRA_TERM_IMG" in
    kitty|wezterm)
      printf $'\033_Ga=d\033\\'
      ;;
    iterm2)
      printf '\033]1337;File=;clear=1\a'
      ;;
  esac
}

preview_signature() {
  local path="$1" inode size mtime
  if is_macos; then
    inode=$(stat -f '%i' -- "$path")
    size=$(stat -f '%z' -- "$path")
    mtime=$(stat -f '%m' -- "$path")
  else
    inode=$(stat -c '%i' -- "$path")
    size=$(stat -c '%s' -- "$path")
    mtime=$(stat -c '%Y' -- "$path")
  fi
  local payload hash
  payload=$(printf '%s:%s:%s' "$inode" "$size" "$mtime")
  if command -v sha1sum >/dev/null 2>&1; then
    hash=$(printf '%s' "$payload" | sha1sum | awk '{print $1}')
  elif command -v shasum >/dev/null 2>&1; then
    hash=$(printf '%s' "$payload" | shasum -a 1 | awk '{print $1}')
  else
    hash=$(printf '%s' "$payload" | openssl sha1 | awk '{print $2}')
  fi
  printf '%s' "$hash"
}

preview_render() {
  local path="$1" mime="$2"
  if [[ -d "$path" ]]; then
    ls -a "$path"
    return 0
  fi

  if [[ -z "$mime" ]]; then
    mime=$(preview_mime_type "$path")
  fi
  case "$mime" in
    text/*|application/xml|application/x-sh)
      preview_render_text "$path"
      ;;
    application/json)
      preview_render_json "$path"
      ;;
    application/pdf)
      preview_render_pdf "$path"
      ;;
    image/*)
      preview_render_image "$path"
      ;;
    application/zip|application/x-tar|application/x-7z-compressed|application/x-xz)
      preview_render_archive "$path"
      ;;
    audio/*|video/*)
      preview_render_media "$path"
      ;;
    *)
      preview_render_binary "$path"
      ;;
  esac
}

preview_render_text() {
  local path="$1"
  if [[ -n "$ASTRA_BAT_CMD" ]]; then
    "$ASTRA_BAT_CMD" --style=numbers,changes --color=always --paging=never -- "$path"
  else
    sed -n '1,200p' "$path"
  fi
}

preview_render_json() {
  local path="$1"
  if [[ -n "$ASTRA_JQ_CMD" ]]; then
    "$ASTRA_JQ_CMD" -C . -- "$path" 2>/dev/null || preview_render_text "$path"
  else
    preview_render_text "$path"
  fi
}

preview_render_pdf() {
  local path="$1"
  if command -v pdftotext >/dev/null 2>&1; then
    pdftotext -layout -l 3 -- "$path" -
  else
    echo "[astra] install poppler-utils for PDF previews"
  fi
}

preview_render_archive() {
  local path="$1"
  if command -v atool >/dev/null 2>&1; then
    atool -l -- "$path"
  elif command -v bsdtar >/dev/null 2>&1; then
    bsdtar -tvf "$path"
  else
    echo "[astra] install atool or bsdtar for archive preview"
  fi
}

preview_render_media() {
  local path="$1"
  if command -v ffprobe >/dev/null 2>&1; then
    ffprobe -hide_banner -- "$path"
  elif command -v mediainfo >/dev/null 2>&1; then
    mediainfo "$path"
  else
    echo "[astra] install ffprobe or mediainfo for media metadata"
  fi
}

preview_render_binary() {
  local path="$1"
  xxd -g 1 -l 1024 -- "$path"
}

preview_guess_geometry() {
  local cols="${1:-0}" lines="${2:-0}" left="${3:-0}" top="${4:-0}"
  local stty_out term_lines term_cols
  local preview_ratio=60 border_padding=1 min_cols=20

  term_lines=${ASTRA_TTY_LINES:-0}
  term_cols=${ASTRA_TTY_COLS:-0}

  if (( term_lines <= 0 || term_cols <= 0 )); then
    if stty_out=$(stty size </dev/tty 2>/dev/null); then
      term_lines=${stty_out% *}
      term_cols=${stty_out#* }
    fi
  fi

  if (( term_lines <= 0 )); then
    term_lines=${LINES:-0}
  fi
  if (( term_cols <= 0 )); then
    term_cols=${COLUMNS:-0}
  fi

  if (( term_lines <= 0 )); then
    term_lines=24
  fi
  if (( term_cols <= 0 )); then
    term_cols=80
  fi

  if (( cols <= 0 )); then
    cols=$(( term_cols * preview_ratio / 100 ))
    if (( cols < min_cols )); then
      cols=$(( term_cols > min_cols ? min_cols : term_cols ))
    fi
    if (( cols >= term_cols )); then
      cols=$(( term_cols - 1 ))
    fi
  fi

  if (( lines <= 0 )); then
    lines=$term_lines
  fi

  if (( left <= 0 )); then
    left=$(( term_cols - cols ))
    (( left < 0 )) && left=0
    if (( border_padding > 0 && left + cols + border_padding <= term_cols )); then
      left=$(( left + border_padding ))
    fi
  fi

  if (( top < 0 )); then
    top=0
  fi

  printf '%s %s %s %s' "$cols" "$lines" "$left" "$top"
}

preview_render_image() {
  local path="$1"
  local preview_cols preview_lines preview_left preview_top have_geometry=0

  # FZF exposes preview geometry via env vars so we can clamp image output.
  preview_cols=${FZF_PREVIEW_COLUMNS:-0}
  preview_lines=${FZF_PREVIEW_LINES:-0}
  preview_left=${FZF_PREVIEW_LEFT:-0}
  preview_top=${FZF_PREVIEW_TOP:-0}

  if (( preview_cols <= 0 || preview_lines <= 0 || preview_left <= 0 || preview_top < 0 )); then
    read -r preview_cols preview_lines preview_left preview_top <<<"$(preview_guess_geometry "$preview_cols" "$preview_lines" "$preview_left" "$preview_top")"
  fi

  if (( preview_cols > 0 && preview_lines > 0 )); then
    have_geometry=1
  fi

  log_debug "preview geometry cols=$preview_cols lines=$preview_lines left=$preview_left top=$preview_top term_img=$ASTRA_TERM_IMG"

  case "$ASTRA_TERM_IMG" in
    kitty)
      if (( have_geometry == 1 )); then
        kitty +kitten icat --silent --transfer-mode file \
          --place "${preview_cols}x${preview_lines}@${preview_left}x${preview_top}" \
          "$path" || preview_render_image_fallback "$path" "$preview_cols" "$preview_lines"
      else
        kitty +kitten icat --silent --transfer-mode file "$path" \
          || preview_render_image_fallback "$path" "$preview_cols" "$preview_lines"
      fi
      ;;
    wezterm)
      if (( preview_cols > 0 )); then
        if (( preview_lines > 0 )); then
          wezterm imgcat --width "${preview_cols}" --height "${preview_lines}" "$path" \
            || preview_render_image_fallback "$path" "$preview_cols" "$preview_lines"
        else
          wezterm imgcat --width "${preview_cols}" "$path" \
            || preview_render_image_fallback "$path" "$preview_cols" "$preview_lines"
        fi
      else
        wezterm imgcat "$path" || preview_render_image_fallback "$path" "$preview_cols" "$preview_lines"
      fi
      ;;
    iterm2)
      local -a imgcat_opts=()
      if (( preview_cols > 0 )); then
        imgcat_opts+=(--width "${preview_cols}")
      fi
      if (( preview_lines > 0 )); then
        imgcat_opts+=(--height "${preview_lines}")
      fi
      imgcat "${imgcat_opts[@]}" "$path" || preview_render_image_fallback "$path" "$preview_cols" "$preview_lines"
      ;;
    chafa|viu)
      preview_render_image_fallback "$path" "$preview_cols" "$preview_lines"
      ;;
    *)
      preview_render_image_fallback "$path" "$preview_cols" "$preview_lines"
      ;;
  esac
}

preview_render_image_fallback() {
  local path="$1" cols="${2:-0}" lines="${3:-0}"
  if command -v chafa >/dev/null 2>&1; then
    local -a chafa_args=()
    if (( cols > 0 && lines > 0 )); then
      chafa_args+=(--size "${cols}x${lines}")
    fi
    chafa "${chafa_args[@]}" "$path"
  elif command -v viu >/dev/null 2>&1; then
    local -a viu_args=()
    if (( cols > 0 )); then
      viu_args+=(--width "${cols}")
    fi
    if (( lines > 0 )); then
      viu_args+=(--height "${lines}")
    fi
    viu "${viu_args[@]}" "$path"
  else
    echo "[astra] install chafa or viu for image previews"
  fi
}
