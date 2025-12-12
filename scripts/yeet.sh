#!/bin/bash
set -euo pipefail

# yeet: Flash drive ejector for macOS + Linux.
# Scans for removable drives and lets you select one or more to eject via gum.

print_usage() {
  cat <<'EOF'
Usage:
  yeet

Interactive flow to safely eject one or more removable flash drives.
EOF
}

echo_err() { printf '%s\n' "$*" >&2; }

ensure_gum() {
  if command -v gum >/dev/null 2>&1; then return 0; fi
  echo_err "gum is required. Install it first:"
  echo_err "  brew install gum"
  echo_err "  # or see https://github.com/charmbracelet/gum"
  return 1
}

trim() {
  printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

os_name() {
  local u; u=$(uname -s)
  if [[ "$u" == "Darwin" ]]; then
    printf '%s\n' macos
  elif [[ "$u" == "Linux" ]]; then
    printf '%s\n' linux
  else
    printf '%s\n' other
  fi
}

join_array() {
  local sep="$1"; shift
  local out="" item
  for item in "$@"; do
    if [[ -z "$out" ]]; then
      out="$item"
    else
      out="$out$sep$item"
    fi
  done
  printf '%s' "$out"
}

# Globals for discovery (parallel arrays)
DRIVE_LABELS=()
DRIVE_PATHS=()

mac_mountpoints_for_disk() {
  local disk="$1"
  local mps=() mp
  while IFS= read -r mp; do
    [[ -n "${mp:-}" ]] && mps+=("$mp")
  done < <(mount | awk -v d="$disk" '$1 ~ ("^" d "s") {print $3}')
  printf '%s\n' "${mps[@]:-}"
}

mac_media_name() {
  local disk="$1"
  local media
  media=$(diskutil info "$disk" 2>/dev/null | awk -F: '
    /Device \\/ Media Name/ || /^ *Media Name/ {
      gsub(/^[[:space:]]+/, "", $2); print $2; exit
    }' || true)
  media=$(trim "${media:-}")
  [[ -n "$media" ]] && printf '%s' "$media"
}

mac_pretty_name() {
  local disk="$1"
  local mps=() names=() mp name
  while IFS= read -r mp; do
    [[ -n "${mp:-}" ]] && mps+=("$mp")
  done < <(mac_mountpoints_for_disk "$disk" || true)
  for mp in "${mps[@]:-}"; do
    name=$(basename "$mp")
    [[ -n "${name:-}" ]] && names+=("$name")
  done
  if [[ ${#names[@]} -gt 0 ]]; then
    join_array ", " "${names[@]}"
    return 0
  fi
  local media
  media=$(mac_media_name "$disk" || true)
  if [[ -n "${media:-}" ]]; then
    printf '%s' "$media"
    return 0
  fi
  printf '%s' "external drive"
}

list_macos_drives() {
  DRIVE_LABELS=(); DRIVE_PATHS=()
  local disks=() d
  while IFS= read -r d; do
    [[ -n "${d:-}" ]] && disks+=("$d")
  done < <(diskutil list external physical 2>/dev/null | awk '/^\/dev\/disk[0-9]+/ {print $1}')

  if [[ ${#disks[@]} -eq 0 ]]; then
    while IFS= read -r d; do
      [[ -n "${d:-}" ]] && disks+=("$d")
    done < <(diskutil list 2>/dev/null | awk '/^\/dev\/disk[0-9]+/ && $0 ~ /external/ {print $1}')
  fi

  local disk pretty mps=() mp_hint label
  for disk in "${disks[@]:-}"; do
    pretty=$(mac_pretty_name "$disk")
    mps=()
    while IFS= read -r mp_hint; do
      [[ -n "${mp_hint:-}" ]] && mps+=("$mp_hint")
    done < <(mac_mountpoints_for_disk "$disk" || true)
    label="$disk — $pretty"
    if [[ ${#mps[@]} -gt 0 ]]; then
      label="$label ($(join_array ", " "${mps[@]}"))"
    fi
    DRIVE_LABELS+=("$label")
    DRIVE_PATHS+=("$disk")
  done
}

linux_pretty_name() {
  local disk="$1" model="$2" size="$3"
  local names=() line NAME TYPE LABEL MOUNTPOINT
  while IFS= read -r line; do
    unset NAME TYPE LABEL MOUNTPOINT
    eval "$line"
    if [[ "${TYPE:-}" == "part" ]]; then
      if [[ -n "${LABEL:-}" ]]; then
        names+=("$LABEL")
      elif [[ -n "${MOUNTPOINT:-}" ]]; then
        names+=("$(basename "$MOUNTPOINT")")
      fi
    fi
  done < <(lsblk -P -o NAME,TYPE,LABEL,MOUNTPOINT "$disk" 2>/dev/null || true)

  local pretty=""
  if [[ ${#names[@]} -gt 0 ]]; then
    pretty=$(join_array ", " "${names[@]}")
  elif [[ -n "${model:-}" ]]; then
    pretty="$model"
  else
    pretty="removable disk"
  fi
  if [[ -n "${size:-}" ]]; then
    pretty="$pretty, $size"
  fi
  printf '%s' "$pretty"
}

linux_mount_hint() {
  local disk="$1"
  local mps=() line NAME TYPE MOUNTPOINT
  while IFS= read -r line; do
    unset NAME TYPE MOUNTPOINT
    eval "$line"
    if [[ "${TYPE:-}" == "part" && -n "${MOUNTPOINT:-}" ]]; then
      mps+=("$MOUNTPOINT")
    fi
  done < <(lsblk -P -o NAME,TYPE,MOUNTPOINT "$disk" 2>/dev/null || true)
  if [[ ${#mps[@]} -gt 0 ]]; then
    join_array ", " "${mps[@]}"
  fi
}

linux_canon_device() {
  local dev="$1"
  if [[ "$dev" != /dev/* ]]; then
    dev="/dev/$dev"
  fi
  printf '%s' "$dev"
}

list_linux_drives() {
  DRIVE_LABELS=(); DRIVE_PATHS=()
  if ! command -v lsblk >/dev/null 2>&1; then
    echo_err "lsblk is required on Linux (util-linux)."
    return 1
  fi

  local line NAME RM TYPE TRAN SIZE LABEL MODEL MOUNTPOINT
  while IFS= read -r line; do
    unset NAME RM TYPE TRAN SIZE LABEL MODEL MOUNTPOINT
    eval "$line"
    [[ "${RM:-0}" == "1" && "${TYPE:-}" == "disk" ]] || continue
    local dev pretty hint label_str
    dev=$(linux_canon_device "$NAME")
    pretty=$(linux_pretty_name "$dev" "${MODEL:-}" "${SIZE:-}")
    hint=$(linux_mount_hint "$dev" || true)
    label_str="$dev — $pretty"
    [[ -n "${hint:-}" ]] && label_str="$label_str ($hint)"
    DRIVE_LABELS+=("$label_str")
    DRIVE_PATHS+=("$dev")
  done < <(lsblk -P -o NAME,RM,TYPE,TRAN,SIZE,LABEL,MODEL,MOUNTPOINT 2>/dev/null | sed '/^$/d')
}

discover_drives() {
  local os; os=$(os_name)
  case "$os" in
    macos) list_macos_drives ;;
    linux) list_linux_drives ;;
    *)
      echo_err "Unsupported OS."
      return 1
      ;;
  esac
}

eject_macos_drive() {
  local disk="$1"
  if diskutil eject "$disk" >/dev/null 2>&1; then
    printf 'ejected %s\n' "$disk"
    return 0
  fi
  echo_err "failed to eject $disk"
  return 1
}

linux_unmount_partitions() {
  local disk="$1"
  local line NAME TYPE MOUNTPOINT
  while IFS= read -r line; do
    unset NAME TYPE MOUNTPOINT
    eval "$line"
    if [[ "${TYPE:-}" == "part" && -n "${MOUNTPOINT:-}" ]]; then
      local part_dev
      part_dev=$(linux_canon_device "$NAME")
      if command -v udisksctl >/dev/null 2>&1; then
        udisksctl unmount -b "$part_dev" >/dev/null 2>&1 || true
      else
        umount "$part_dev" >/dev/null 2>&1 || umount "$MOUNTPOINT" >/dev/null 2>&1 || true
      fi
    fi
  done < <(lsblk -P -o NAME,TYPE,MOUNTPOINT "$disk" 2>/dev/null || true)
}

eject_linux_drive() {
  local disk="$1"
  linux_unmount_partitions "$disk"
  if command -v udisksctl >/dev/null 2>&1; then
    if udisksctl power-off -b "$disk" >/dev/null 2>&1; then
      printf 'powered off %s\n' "$disk"
      return 0
    fi
  fi
  if command -v eject >/dev/null 2>&1; then
    if eject "$disk" >/dev/null 2>&1; then
      printf 'ejected %s\n' "$disk"
      return 0
    fi
  fi
  echo_err "failed to eject $disk (need udisksctl or eject)"
  return 1
}

eject_drive() {
  local disk="$1"
  local os; os=$(os_name)
  case "$os" in
    macos) eject_macos_drive "$disk" ;;
    linux) eject_linux_drive "$disk" ;;
    *) echo_err "Unsupported OS."; return 1 ;;
  esac
}

main() {
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    print_usage
    exit 0
  fi

  ensure_gum || exit 1
  discover_drives || exit 1

  if [[ ${#DRIVE_LABELS[@]} -eq 0 ]]; then
    echo "No removable drives found."
    exit 0
  fi

  local selected
  selected=$(printf '%s\n' "${DRIVE_LABELS[@]}" | gum choose --no-limit --header "Select drives to yeet (eject)") || exit 0

  local ok=0 fail=0 line disk
  while IFS= read -r line; do
    [[ -z "${line:-}" ]] && continue
    disk=${line%%[[:space:]]*}
    if eject_drive "$disk"; then
      ok=$((ok+1))
    else
      fail=$((fail+1))
    fi
  done <<<"$selected"

  printf '\nSummary: %s ejected, %s failed.\n' "$ok" "$fail"
}

main "$@"
