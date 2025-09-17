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

  local cache_file mime="" use_image_protocol=0
  cache_file=$(preview_cache_file "$path")
  if [[ ! -d "$path" ]]; then
    mime=$(preview_mime_type "$path")
  fi
  case "$ASTRA_TERM_IMG" in
    kitty|wezterm|iterm2)
      use_image_protocol=1
      ;;
  esac
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
    mv "$tmp" "$cache_file"
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

preview_render_image() {
  local path="$1"
  case "$ASTRA_TERM_IMG" in
    kitty)
      kitty +kitten icat --silent --transfer-mode file "$path" || preview_render_image_fallback "$path"
      ;;
    wezterm)
      wezterm imgcat "$path" || preview_render_image_fallback "$path"
      ;;
    iterm2)
      imgcat "$path" || preview_render_image_fallback "$path"
      ;;
    chafa)
      chafa "$path"
      ;;
    viu)
      viu "$path"
      ;;
    *)
      preview_render_image_fallback "$path"
      ;;
  esac
}

preview_render_image_fallback() {
  local path="$1"
  if command -v chafa >/dev/null 2>&1; then
    chafa "$path"
  elif command -v viu >/dev/null 2>&1; then
    viu "$path"
  else
    echo "[astra] install chafa or viu for image previews"
  fi
}
