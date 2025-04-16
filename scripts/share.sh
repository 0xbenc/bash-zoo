#!/bin/bash
# Script: share
# Description:
#   Share files, folders, or text using magic-wormhole.
#   Adds clipboard, ASCII formatting, optional QR, and folder zipping support.
# Dependencies:
#   magic-wormhole, xclip (optional), figlet (optional), qrencode (optional)

set -e

print_usage() {
  echo "Usage:"
  echo "  share <file|folder>       Share a file or folder (zips folder)"
  echo "  share --text              Share custom text (prompts for input)"
  echo "  share --clipboard         Share current clipboard contents as text"
  echo "  share --receive           Receive a wormhole transfer"
  exit 1
}

show_code() {
  CODE="$1"

  if command -v figlet &>/dev/null; then
    figlet "$CODE"
  else
    echo "Wormhole Code: $CODE"
  fi

  if command -v xclip &>/dev/null; then
    echo -n "$CODE" | xclip -selection clipboard
    echo "[✓] Code copied to clipboard"
  fi

  if command -v qrencode &>/dev/null; then
    echo "[QR]"
    echo "$CODE" | qrencode -t ansiutf8
  fi
}

send_file() {
  INPUT="$1"

  if [[ -d "$INPUT" ]]; then
    TMPZIP="/tmp/share-$(basename "$INPUT")-$(date +%s).zip"
    echo "[*] Zipping folder: $INPUT"
    zip -r -q "$TMPZIP" "$INPUT"
    echo "[*] Sending ZIP: $(basename "$TMPZIP")"
    CODE=$(wormhole send "$TMPZIP" 2>&1 | tee /dev/tty | grep -oE '[0-9a-z]+(-[0-9a-z]+){2}$')
    rm "$TMPZIP"
  elif [[ -f "$INPUT" ]]; then
    echo "[*] Sending file: $INPUT"
    CODE=$(wormhole send "$INPUT" 2>&1 | tee /dev/tty | grep -oE '[0-9a-z]+(-[0-9a-z]+){2}$')
  else
    echo "Invalid file or directory: $INPUT"
    exit 1
  fi

  echo
  show_code "$CODE"
}

send_text() {
  echo "[*] Enter the text to send. Finish with Ctrl+D:"
  TEXT=$(</dev/stdin)
  echo "[*] Sending text..."
  CODE=$(echo "$TEXT" | wormhole send 2>&1 | tee /dev/tty | grep -oE '[0-9a-z]+(-[0-9a-z]+){2}$')
  echo
  show_code "$CODE"
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
  CODE=$(echo "$TEXT" | wormhole send 2>&1 | tee /dev/tty | grep -oE '[0-9a-z]+(-[0-9a-z]+){2}$')
  echo
  show_code "$CODE"
}

receive_file() {
  echo "[*] Ready to receive file..."
  wormhole receive
}

### ENTRYPOINT

if [[ $# -eq 0 ]]; then
  print_usage
fi

case "$1" in
  --text)
    send_text
    ;;
  --clipboard)
    send_clipboard
    ;;
  --receive)
    receive_file
    ;;
  -*)
    print_usage
    ;;
  *)
    send_file "$1"
    ;;
esac
