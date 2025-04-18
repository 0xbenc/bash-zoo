#!/usr/bin/env bash
#
# share: secure wrapper around magic‑wormhole for files, dirs, text, or clipboard,
#        with AES‑256 symmetric encryption and PIN‑protected decrypt on receive.
#
set -euo pipefail

usage() {
  cat <<EOF
Usage: share [options] [path]
Options:
  -p PIN, --pin PIN         4‑digit PIN (will prompt if omitted)
  -t TEXT, --text TEXT      share the given TEXT
  -c, --clipboard           share clipboard contents
  -r CODE, --receive CODE   receive mode (grabs CODE from other side)
  -h, --help                show this message

Examples:
  share file.png
  share somedir/
  share -p 1234 -t "Hello World"
  share -c
  share -p 5678 -r 23-barn-animal
EOF
}

#–– Check dependencies ––
for cmd in wormhole gpg tar; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: '$cmd' not found. Please install it." >&2
    exit 1
  fi
done

#–– Arg parse ––
PIN=""
MODE="send"
RECV_CODE=""
TEXT=""
USE_CLIP=0
POSITIONAL=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--pin)     PIN="$2";           shift 2 ;;
    -t|--text)    TEXT="$2";          shift 2 ;;
    -c|--clipboard) USE_CLIP=1;       shift   ;;
    -r|--receive) RECV_CODE="$2"; MODE="receive"; shift 2 ;;
    -h|--help)    usage; exit 0      ;;
    --)           shift; break       ;;
    -*)
      echo "Unknown option: $1" >&2
      usage; exit 1 ;;
    *)
      POSITIONAL+=("$1"); shift ;;
  esac
done

#–– RECEIVE MODE ––
if [[ "$MODE" == "receive" ]]; then
  [[ -z "$RECV_CODE" ]] && read -rp "wormhole code: " RECV_CODE
  [[ -z "$PIN"      ]] && read -srp "4‑digit PIN: " PIN && echo

  # where to stash the incoming .gpg blob
  TMP_RECV="$(mktemp --suffix=.gpg)"
  echo "Receiving into $TMP_RECV …"
  wormhole receive \
    --accept-file \
    --output-file "$TMP_RECV" \
    "$RECV_CODE"

  echo "🔓 Decrypting…"
  # decrypt and honor the original filename embedded at encryption time
  gpg --batch --yes --quiet \
      --pinentry-mode loopback \
      --passphrase "$PIN" \
      --decrypt \
      --use-embedded-filename \
      "$TMP_RECV"

  rm -f "$TMP_RECV"

  # if it was a tar.gz, offer to extract
  for f in *; do
    if [[ -f "$f" && "$f" == *.tar.gz ]]; then
      read -rp "Extract \"$f\"? [Y/n] " ans
      if [[ -z "$ans" || "$ans" =~ ^[Yy] ]]; then
        tar xzf "$f"
        echo "Extracted to \"${f%.tar.gz}/\""
        read -rp "Remove archive \"$f\"? [y/N] " ans2
        [[ "$ans2" =~ ^[Yy] ]] && rm -f "$f"
      fi
    fi
  done

  exit 0
fi

#–– SEND MODE ––
[[ -z "$PIN" ]] && read -srp "4‑digit PIN: " PIN && echo

# prep temp and orig‑name
TMP_SRC=""; TMP_SRC_TEMP=0
ORIG_NAME=""; ENC_FILE=""

cleanup() {
  [[ $TMP_SRC_TEMP -eq 1 && -f "$TMP_SRC" ]] && rm -f "$TMP_SRC"
  [[ -n "$ENC_FILE" && -f "$ENC_FILE"    ]] && rm -f "$ENC_FILE"
}
trap cleanup EXIT

# 1) text
if [[ -n "$TEXT" ]]; then
  TMP_SRC="$(mktemp)"
  echo -n "$TEXT" >"$TMP_SRC"
  TMP_SRC_TEMP=1
  ORIG_NAME="message.txt"

# 2) clipboard
elif [[ $USE_CLIP -eq 1 ]]; then
  TMP_SRC="$(mktemp)"
  if command -v xclip &>/dev/null; then
    xclip -selection clipboard -o >"$TMP_SRC"
  elif command -v xsel &>/dev/null; then
    xsel --clipboard --output >"$TMP_SRC"
  else
    echo "Error: install xclip or xsel." >&2; exit 1
  fi
  TMP_SRC_TEMP=1
  ORIG_NAME="clipboard.txt"

# 3) path
elif [[ ${#POSITIONAL[@]} -eq 1 ]]; then
  src="${POSITIONAL[0]}"
  if [[ -d "$src" ]]; then
    ORIG_NAME="$(basename "$src").tar.gz"
    TMP_SRC="$(mktemp --suffix=.tar.gz)"
    tar czf "$TMP_SRC" -C "$(dirname "$src")" "$(basename "$src")"
    TMP_SRC_TEMP=1
  elif [[ -f "$src" ]]; then
    TMP_SRC="$src"
    ORIG_NAME="$(basename "$src")"
  else
    echo "Error: not found: $src" >&2; exit 1
  fi

else
  echo "Error: no input to send." >&2
  usage; exit 1
fi

# encrypt, embedding ORIG_NAME
ENC_FILE="$(mktemp --suffix=.gpg)"
gpg --batch --yes \
    --pinentry-mode loopback \
    --passphrase "$PIN" \
    --symmetric --cipher-algo AES256 \
    --set-filename "$ORIG_NAME" \
    -o "$ENC_FILE" "$TMP_SRC"

echo "🔐 Encrypted… launching magic‑wormhole:"
exec wormhole send "$ENC_FILE"
