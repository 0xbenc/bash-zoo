#!/bin/bash
# Script: share
# Description:
#   Share files, folders, or text using magic-wormhole.
#   Adds clipboard and folder zipping support.
# Dependencies:
#   magic-wormhole

set -e

print_usage() {
  echo "Usage:"
  echo "  share <file|folder>            Share a file or folder (zips folder)"
  echo "  share --text | -t              Share custom text (prompts for input)"
  echo "  share --clipboard | -c         Share current clipboard contents as text"
  echo "  share --receive | -r           Receive a wormhole transfer (will prompt for code)"
  echo "  share --receive <code>         Receive a wormhole using a specific code (e.g. '76-alkali-algol')"
  exit 1
}

extract_code() {
  grep -oE '[0-9a-z]+(-[0-9a-z]+){2}$'
}

send_file() {
  INPUT="$1"

  if [[ -d "$INPUT" ]]; then
    TMPZIP="/tmp/share-$(basename "$INPUT")-$(date +%s).zip"
    echo "[*] Zipping folder: $INPUT"
    zip -r -q "$TMPZIP" "$INPUT"
    echo "[*] Sending ZIP: $(basename "$TMPZIP")"
    CODE=$(wormhole send "$TMPZIP" 2>&1 | tee /dev/tty | extract_code)
    rm "$TMPZIP"
  elif [[ -f "$INPUT" ]]; then
    echo "[*] Sending file: $INPUT"
    CODE=$(wormhole send "$INPUT" 2>&1 | tee /dev/tty | extract_code)
  else
    echo "Invalid file or directory: $INPUT"
    exit 1
  fi
}

send_text() {
  echo "[*] Enter the text to send. Finish with Ctrl+D:"
  TEXT=$(</dev/stdin)
  echo "[*] Sending text..."
  CODE=$(echo "$TEXT" | wormhole send 2>&1 | tee /dev/tty | extract_code)
}

send_clipboard() {
  if ! command -v xclip &>/dev/null; then
    echo "xclip not found. Cannot read clipboard."
    exit 1
  fi

  TEXT=$(xclip -o -selection clipboard)
  if [[ -z "$TEXT" ]]; then
    echo "Clipboard is empty."
    exit 1
  fi

  echo "[*] Sending clipboard contents..."
  CODE=$(echo "$TEXT" | wormhole send 2>&1 | tee /dev/tty | extract_code)
}

receive_file() {
  if [[ -n "$1" ]]; then
    echo "[*] Receiving with code: $1"
    wormhole receive "$1"
  else
    echo "[*] Ready to receive file..."
    echo "You can also run: share --receive <code> to skip this step."
    wormhole receive
  fi
}

### ENTRYPOINT

if [[ $# -eq 0 ]]; then
  print_usage
fi

case "$1" in
  --text|-t)
    send_text
    ;;
  --clipboard|-c)
    send_clipboard
    ;;
  --receive|-r)
    if [[ -n "$2" ]]; then
      receive_file "$2"
    else
      receive_file
    fi
    ;;
  -*)
    print_usage
    ;;
  *)
    send_file "$1"
    ;;
esac
