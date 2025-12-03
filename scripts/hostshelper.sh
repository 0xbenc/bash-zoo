#!/bin/bash
set -euo pipefail

# hostshelper: gum-only TUI for managing host entries and presets, and writing them to /etc/hosts.
# Config: ~/.bash-zoo/hosthelper.toml with [hosts] and [presets] tables.
# Managed block in /etc/hosts is wrapped with start/end markers to avoid duplicates.

CONFIG_PATH="$HOME/.bash-zoo/hosthelper.toml"
CONFIG_DIR="$(dirname "$CONFIG_PATH")"
HOSTS_FILE="/etc/hosts"
BLOCK_START="# hostshelper start (managed by bash-zoo)"
BLOCK_END="# hostshelper end"

HOST_NAMES=()
HOST_IPS=()
PRESET_NAMES=()
PRESET_MEMBERS=() # comma-separated hostnames per preset

BLOCK_HOSTS=()
BLOCK_IPS=()
BLOCK_FOUND=0

echo_err() { printf '%s\n' "$*" >&2; }

trim() {
  printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

ensure_gum() {
  if command -v gum >/dev/null 2>&1; then
    return 0
  fi
  echo_err "gum is required. Install it with Homebrew:"
  echo_err "  brew install gum"
  exit 1
}

ensure_config_dir() { mkdir -p "$CONFIG_DIR"; }

find_host_index() {
  local name="$1" i
  for i in "${!HOST_NAMES[@]}"; do
    if [[ "${HOST_NAMES[$i]}" == "$name" ]]; then
      printf '%s' "$i"
      return 0
    fi
  done
  printf '%s' "-1"
  return 1
}

find_preset_index() {
  local name="$1" i
  for i in "${!PRESET_NAMES[@]}"; do
    if [[ "${PRESET_NAMES[$i]}" == "$name" ]]; then
      printf '%s' "$i"
      return 0
    fi
  done
  printf '%s' "-1"
  return 1
}

load_config() {
  HOST_NAMES=()
  HOST_IPS=()
  PRESET_NAMES=()
  PRESET_MEMBERS=()
  [[ -f "$CONFIG_PATH" ]] || return 0
  local section="" line key val inner
  while IFS= read -r line || [[ -n "$line" ]]; do
    line=$(printf '%s' "$line" | sed -e 's/[[:space:]]*#.*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [[ -z "$line" ]] && continue
    case "$line" in
      "[hosts]")
        section="hosts"
        continue
        ;;
      "[presets]")
        section="presets"
        continue
        ;;
      \[*\])
        section=""
        continue
        ;;
    esac
    case "$section" in
      hosts)
        key=$(trim "${line%%=*}")
        val=$(trim "${line#*=}")
        if [[ -z "$key" || -z "$val" ]]; then
          continue
        fi
        if [[ "${val:0:1}" == '"' && "${val: -1}" == '"' && ${#val} -ge 2 ]]; then
          val="${val:1:${#val}-2}"
        fi
        # Upsert host entry
        local idx
        idx=$(find_host_index "$key") || true
        if [[ "$idx" -ge 0 ]]; then
          HOST_IPS[$idx]="$val"
        else
          HOST_NAMES+=("$key")
          HOST_IPS+=("$val")
        fi
        ;;
      presets)
        key=$(trim "${line%%=*}")
        val=$(trim "${line#*=}")
        [[ -z "$key" ]] && continue
        if [[ "$val" =~ ^\[(.*)\]$ ]]; then
          inner="${BASH_REMATCH[1]}"
        else
          inner="$val"
        fi
        local members=() part parts=()
        IFS=',' read -r -a parts <<<"$inner"
        for part in "${parts[@]}"; do
          part=$(trim "$part")
          if [[ "${part:0:1}" == '"' && "${part: -1}" == '"' && ${#part} -ge 2 ]]; then
            part="${part:1:${#part}-2}"
          fi
          [[ -z "$part" ]] && continue
          members+=("$part")
        done
        local joined=""
        if [[ ${#members[@]} -gt 0 ]]; then
          joined="${members[0]}"
          local mi
          for mi in "${!members[@]}"; do
            if [[ "$mi" -eq 0 ]]; then
              continue
            fi
            joined+=","${members[$mi]}
          done
        fi
        local pidx
        pidx=$(find_preset_index "$key") || true
        if [[ "$pidx" -ge 0 ]]; then
          PRESET_MEMBERS[$pidx]="$joined"
        else
          PRESET_NAMES+=("$key")
          PRESET_MEMBERS+=("$joined")
        fi
        ;;
    esac
  done < "$CONFIG_PATH"
}

save_config() {
  ensure_config_dir
  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/hostshelper_cfg.XXXXXX")
  {
    echo "# hostshelper config"
    echo "[hosts]"
    local i
    for i in "${!HOST_NAMES[@]}"; do
      printf '%s = "%s"\n' "${HOST_NAMES[$i]}" "${HOST_IPS[$i]}"
    done
    echo ""
    echo "[presets]"
    for i in "${!PRESET_NAMES[@]}"; do
      local raw members=() part
      raw="${PRESET_MEMBERS[$i]}"
      [[ -n "$raw" ]] && IFS=',' read -r -a members <<<"$raw"
      printf '%s = [' "${PRESET_NAMES[$i]}"
      if [[ ${#members[@]} -gt 0 ]]; then
        local line_parts=()
        for part in "${members[@]}"; do
          line_parts+=("\"$part\"")
        done
        local lp
        for lp in "${!line_parts[@]}"; do
          if [[ "$lp" -gt 0 ]]; then
            printf ', '
          fi
          printf '%s' "${line_parts[$lp]}"
        done
      fi
      printf ']\n'
    done
  } > "$tmp"
  mv "$tmp" "$CONFIG_PATH"
}

upsert_block_entry() {
  local host="$1" ip="$2" i
  for i in "${!BLOCK_HOSTS[@]}"; do
    if [[ "${BLOCK_HOSTS[$i]}" == "$host" ]]; then
      BLOCK_IPS[$i]="$ip"
      return
    fi
  done
  BLOCK_HOSTS+=("$host")
  BLOCK_IPS+=("$ip")
}

load_block_entries() {
  BLOCK_HOSTS=()
  BLOCK_IPS=()
  BLOCK_FOUND=0
  [[ -f "$HOSTS_FILE" ]] || return 0
  local in_block=0 line trimmed ip rest name
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "$BLOCK_START" ]]; then
      BLOCK_FOUND=1
      in_block=1
      continue
    fi
    if [[ "$line" == "$BLOCK_END" ]]; then
      in_block=0
      continue
    fi
    [[ $in_block -eq 0 ]] && continue
    trimmed=$(trim "$line")
    [[ -z "$trimmed" || "${trimmed:0:1}" == "#" ]] && continue
    ip="${trimmed%%[[:space:]]*}"
    rest=$(trim "${trimmed#*$ip}")
    [[ -z "$rest" ]] && continue
    IFS=' ' read -r -a names <<<"$rest"
    for name in "${names[@]}"; do
      [[ -z "$name" ]] && continue
      upsert_block_entry "$name" "$ip"
    done
  done < "$HOSTS_FILE"
}

write_hosts_file() {
  local include_block="${1:-1}"
  local keep_lines=() in_block=0 line
  if [[ -f "$HOSTS_FILE" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" == "$BLOCK_START" ]]; then
        in_block=1
        continue
      fi
      if [[ "$line" == "$BLOCK_END" ]]; then
        in_block=0
        continue
      fi
      [[ $in_block -eq 1 ]] && continue
      local clean skip_line=0 host
      clean=$(trim "${line%%#*}")
      if [[ -n "$clean" ]]; then
        for host in "${BLOCK_HOSTS[@]}"; do
          case " $clean " in
            *" $host "*) skip_line=1; break ;;
          esac
        done
      fi
      [[ $skip_line -eq 1 ]] && continue
      keep_lines+=("$line")
    done < "$HOSTS_FILE"
  fi

  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/hostshelper_hosts.XXXXXX")
  for line in "${keep_lines[@]}"; do
    printf '%s\n' "$line" >> "$tmp"
  done
  if [[ ${#keep_lines[@]} -gt 0 ]]; then
    local last_line
    last_line=$(tail -n 1 "$tmp" 2>/dev/null || printf '')
    [[ -n "$last_line" ]] && printf '\n' >> "$tmp"
  fi
  if [[ $include_block -eq 1 && ${#BLOCK_HOSTS[@]} -gt 0 ]]; then
    printf '%s\n' "$BLOCK_START" >> "$tmp"
    local i
    for i in "${!BLOCK_HOSTS[@]}"; do
      printf '%s\t%s\n' "${BLOCK_IPS[$i]}" "${BLOCK_HOSTS[$i]}" >> "$tmp"
    done
    printf '%s\n' "$BLOCK_END" >> "$tmp"
  fi

  local backup=""
  if [[ -f "$HOSTS_FILE" ]]; then
    backup="$HOSTS_FILE.hostshelper.bak.$(date +%Y%m%d%H%M%S)"
    if ! sudo cp "$HOSTS_FILE" "$backup"; then
      echo_err "Failed to create backup at $backup"
      return 1
    fi
  fi
  if ! sudo tee "$HOSTS_FILE" >/dev/null < "$tmp"; then
    echo_err "Failed to update $HOSTS_FILE. Check sudo permissions."
    return 1
  fi
  if [[ -n "$backup" ]]; then
    echo "Updated $HOSTS_FILE (backup: $backup)"
  else
    echo "Updated $HOSTS_FILE"
  fi
}

apply_entries() {
  local mode="$1"
  shift
  local pairs=("$@")
  if [[ $((${#pairs[@]} % 2)) -ne 0 ]]; then
    echo_err "apply_entries expects host/ip pairs."
    return 1
  fi
  if [[ ${#pairs[@]} -eq 0 ]]; then
    echo_err "No host entries provided."
    return 1
  fi
  if [[ "$mode" == "replace" ]]; then
    BLOCK_HOSTS=()
    BLOCK_IPS=()
  else
    load_block_entries
  fi
  local i host ip
  for ((i=0; i<${#pairs[@]}; i+=2)); do
    host="${pairs[$i]}"
    ip="${pairs[$((i+1))]}"
    upsert_block_entry "$host" "$ip"
  done
  write_hosts_file 1
}

remove_hosts_from_block() {
  local to_remove=("$@")
  load_block_entries
  if [[ $BLOCK_FOUND -eq 0 ]]; then
    echo_err "No hostshelper block found in $HOSTS_FILE."
    return 1
  fi
  if [[ ${#BLOCK_HOSTS[@]} -eq 0 ]]; then
    echo_err "No hostshelper entries present in $HOSTS_FILE."
    return 1
  fi
  local new_hosts=() new_ips=() host ip i drop rm
  for i in "${!BLOCK_HOSTS[@]}"; do
    host="${BLOCK_HOSTS[$i]}"
    ip="${BLOCK_IPS[$i]}"
    drop=0
    for rm in "${to_remove[@]}"; do
      if [[ "$host" == "$rm" ]]; then
        drop=1
        break
      fi
    done
    if [[ $drop -eq 0 ]]; then
      new_hosts+=("$host")
      new_ips+=("$ip")
    fi
  done
  if [[ ${#new_hosts[@]} -eq ${#BLOCK_HOSTS[@]} ]]; then
    echo_err "No matching hosts to remove."
    return 1
  fi
  BLOCK_HOSTS=("${new_hosts[@]}")
  BLOCK_IPS=("${new_ips[@]}")
  if [[ ${#BLOCK_HOSTS[@]} -eq 0 ]]; then
    write_hosts_file 0
    echo "Removed hostshelper block from $HOSTS_FILE."
  else
    write_hosts_file 1
  fi
}

collect_entries_from_preset() {
  local preset="$1"
  local idx
  idx=$(find_preset_index "$preset") || true
  if [[ "$idx" -lt 0 ]]; then
    echo_err "Preset '$preset' not found."
    return 1
  fi
  local members_raw="${PRESET_MEMBERS[$idx]}"
  [[ -z "$members_raw" ]] && { echo_err "Preset '$preset' has no hosts."; return 1; }
  local preset_hosts=()
  IFS=',' read -r -a preset_hosts <<<"$members_raw"
  local entries=() missing=()
  local host ip hidx
  for host in "${preset_hosts[@]}"; do
    hidx=$(find_host_index "$host") || true
    if [[ "$hidx" -lt 0 ]]; then
      missing+=("$host")
      continue
    fi
    ip="${HOST_IPS[$hidx]}"
    entries+=("$host" "$ip")
  done
  if [[ ${#entries[@]} -eq 0 ]]; then
    echo_err "No valid hosts found for preset '$preset'. Missing: ${missing[*]}"
    return 1
  fi
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo_err "Skipping missing hosts in preset '$preset': ${missing[*]}"
  fi
  apply_entries "replace" "${entries[@]}" || return
}

apply_single_host_flow() {
  if [[ ${#HOST_NAMES[@]} -eq 0 ]]; then
    echo_err "No hosts defined. Add a host first."
    return
  fi
  local labels=() i
  for i in "${!HOST_NAMES[@]}"; do
    labels+=("${HOST_NAMES[$i]} (${HOST_IPS[$i]})")
  done
  local choice
  choice=$(printf '%s\n' "${labels[@]}" | gum choose --header "Select host to write to /etc/hosts") || return
  local sel_idx=-1
  for i in "${!labels[@]}"; do
    if [[ "${labels[$i]}" == "$choice" ]]; then
      sel_idx=$i
      break
    fi
  done
  [[ $sel_idx -lt 0 ]] && { echo_err "Selection failed."; return; }
  local host ip
  host="${HOST_NAMES[$sel_idx]}"
  ip="${HOST_IPS[$sel_idx]}"
  echo "Writing $host -> $ip (merge with existing hostshelper entries)..."
  apply_entries "merge" "$host" "$ip" || return
}

create_or_update_host() {
  local ip host existing_idx
  ip=$(gum input --prompt "IP address> " --placeholder "e.g. 192.168.0.67") || return
  ip=$(trim "$ip")
  [[ -z "$ip" ]] && { echo_err "IP is required."; return; }
  host=$(gum input --prompt "Hostname> " --placeholder "e.g. pnwgit.occ.farm") || return
  host=$(trim "$host")
  [[ -z "$host" ]] && { echo_err "Hostname is required."; return; }
  case "$host" in *[[:space:]]*) echo_err "Hostname cannot contain spaces."; return ;; esac
  existing_idx=$(find_host_index "$host") || true
  if [[ "$existing_idx" -ge 0 ]]; then
    if ! gum confirm "Update $host from ${HOST_IPS[$existing_idx]} to $ip?"; then
      echo "No changes saved."
      return
    fi
    HOST_IPS[$existing_idx]="$ip"
  else
    HOST_NAMES+=("$host")
    HOST_IPS+=("$ip")
  fi
  save_config
  echo "Saved $host -> $ip to $CONFIG_PATH"
}

select_preset_name() {
  local labels=() i
  for i in "${!PRESET_NAMES[@]}"; do
    labels+=("${PRESET_NAMES[$i]}")
  done
  printf '%s\n' "${labels[@]}"
}

apply_preset_flow() {
  if [[ ${#PRESET_NAMES[@]} -eq 0 ]]; then
    echo_err "No presets defined. Create one first."
    return
  fi
  local choice
  choice=$(select_preset_name | gum choose --header "Select preset to load into /etc/hosts") || return
  if ! gum confirm "Replace hostshelper block with preset '$choice'?"; then
    echo "Cancelled."
    return
  fi
  collect_entries_from_preset "$choice" || return
}

remove_all_hosts_flow() {
  load_block_entries
  if [[ $BLOCK_FOUND -eq 0 || ${#BLOCK_HOSTS[@]} -eq 0 ]]; then
    echo_err "No hostshelper entries in $HOSTS_FILE to remove."
    return
  fi
  if ! gum confirm "Remove all hostshelper entries from $HOSTS_FILE?"; then
    echo "Cancelled."
    return
  fi
  BLOCK_HOSTS=()
  BLOCK_IPS=()
  write_hosts_file 0
  echo "Removed all hostshelper entries from $HOSTS_FILE."
}

remove_single_host_flow() {
  load_block_entries
  if [[ $BLOCK_FOUND -eq 0 || ${#BLOCK_HOSTS[@]} -eq 0 ]]; then
    echo_err "No hostshelper entries in $HOSTS_FILE to remove."
    return
  fi
  local labels=() i
  for i in "${!BLOCK_HOSTS[@]}"; do
    labels+=("${BLOCK_HOSTS[$i]} (${BLOCK_IPS[$i]})")
  done
  local choice
  choice=$(printf '%s\n' "${labels[@]}" | gum choose --header "Select host to remove from /etc/hosts") || return
  local sel=-1
  for i in "${!labels[@]}"; do
    if [[ "${labels[$i]}" == "$choice" ]]; then
      sel=$i
      break
    fi
  done
  [[ $sel -lt 0 ]] && { echo_err "Selection failed."; return; }
  local host="${BLOCK_HOSTS[$sel]}"
  if ! gum confirm "Remove $host from $HOSTS_FILE?"; then
    echo "Cancelled."
    return
  fi
  remove_hosts_from_block "$host"
}

remove_preset_from_hosts_flow() {
  if [[ ${#PRESET_NAMES[@]} -eq 0 ]]; then
    echo_err "No presets defined."
    return
  fi
  load_block_entries
  if [[ $BLOCK_FOUND -eq 0 || ${#BLOCK_HOSTS[@]} -eq 0 ]]; then
    echo_err "No hostshelper entries in $HOSTS_FILE to remove."
    return
  fi
  local choice
  choice=$(select_preset_name | gum choose --header "Select preset to remove from /etc/hosts") || return
  local idx
  idx=$(find_preset_index "$choice") || true
  if [[ "$idx" -lt 0 ]]; then
    echo_err "Preset '$choice' not found."
    return
  fi
  local members=()
  if [[ -n "${PRESET_MEMBERS[$idx]}" ]]; then
    IFS=',' read -r -a members <<<"${PRESET_MEMBERS[$idx]}"
  fi
  if [[ ${#members[@]} -eq 0 ]]; then
    echo_err "Preset '$choice' has no hosts."
    return
  fi
  if ! gum confirm "Remove ${#members[@]} host(s) from $HOSTS_FILE for preset '$choice'?"; then
    echo "Cancelled."
    return
  fi
  remove_hosts_from_block "${members[@]}"
}

toggle_preset_cli() {
  local preset="$1"
  load_config
  local idx
  idx=$(find_preset_index "$preset") || true
  if [[ "$idx" -lt 0 ]]; then
    echo_err "Preset '$preset' not found."
    exit 1
  fi
  local members_raw="${PRESET_MEMBERS[$idx]}"
  [[ -z "$members_raw" ]] && { echo_err "Preset '$preset' has no hosts."; exit 1; }
  local preset_hosts=()
  IFS=',' read -r -a preset_hosts <<<"$members_raw"
  local entries=() host ip hidx missing=()
  for host in "${preset_hosts[@]}"; do
    hidx=$(find_host_index "$host") || true
    if [[ "$hidx" -lt 0 ]]; then
      missing+=("$host")
      continue
    fi
    ip="${HOST_IPS[$hidx]}"
    entries+=("$host" "$ip")
  done
  if [[ ${#entries[@]} -eq 0 ]]; then
    echo_err "No valid hosts resolved for preset '$preset'. Missing: ${missing[*]}"
    exit 1
  fi
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo_err "Skipping missing hosts in preset '$preset': ${missing[*]}"
  fi
  load_block_entries
  local present=0 h
  for ((i=0; i<${#entries[@]}; i+=2)); do
    h="${entries[$i]}"
    for existing in "${BLOCK_HOSTS[@]}"; do
      if [[ "$existing" == "$h" ]]; then
        present=1
        break
      fi
    done
    [[ $present -eq 1 ]] && break
  done
  if [[ $present -eq 1 ]]; then
    remove_hosts_from_block "${preset_hosts[@]}" || exit 1
    echo "Removed preset '$preset' from $HOSTS_FILE."
  else
    apply_entries "merge" "${entries[@]}" || exit 1
    echo "Applied preset '$preset' to $HOSTS_FILE."
  fi
}

edit_preset() {
  local preset="$1" idx hosts_raw=() members=()
  idx=$(find_preset_index "$preset") || true
  [[ "$idx" -lt 0 ]] && { echo_err "Preset '$preset' not found."; return; }
  if [[ -n "${PRESET_MEMBERS[$idx]}" ]]; then
    IFS=',' read -r -a hosts_raw <<<"${PRESET_MEMBERS[$idx]}"
  fi
  echo "Current hosts in '$preset': ${PRESET_MEMBERS[$idx]:-(none)}"
  local choices=() i
  for i in "${!HOST_NAMES[@]}"; do
    choices+=("${HOST_NAMES[$i]} (${HOST_IPS[$i]})")
  done
  local selected
  selected=$(printf '%s\n' "${choices[@]}" | gum choose --no-limit --header "Select hosts for '$preset'") || return
  members=()
  local line host
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    host="${line%% (*}"
    members+=("$host")
  done <<<"$selected"
  if [[ ${#members[@]} -eq 0 ]]; then
    echo_err "Preset must contain at least one host."
    return
  fi
  local joined="${members[0]}"
  for i in "${!members[@]}"; do
    if [[ "$i" -eq 0 ]]; then
      continue
    fi
    joined+=","${members[$i]}
  done
  PRESET_MEMBERS[$idx]="$joined"
  save_config
  echo "Updated preset '$preset'."
}

create_preset() {
  if [[ ${#HOST_NAMES[@]} -eq 0 ]]; then
    echo_err "Add hosts before creating presets."
    return
  fi
  local name
  name=$(gum input --prompt "Preset name> " --placeholder "e.g. at-home") || return
  name=$(trim "$name")
  [[ -z "$name" ]] && { echo_err "Preset name is required."; return; }
  local exists_idx
  exists_idx=$(find_preset_index "$name") || true
  if [[ "$exists_idx" -ge 0 ]]; then
    if ! gum confirm "Preset '$name' exists. Overwrite?"; then
      echo "Cancelled."
      return
    fi
  fi
  local choices=() i
  for i in "${!HOST_NAMES[@]}"; do
    choices+=("${HOST_NAMES[$i]} (${HOST_IPS[$i]})")
  done
  local selected
  selected=$(printf '%s\n' "${choices[@]}" | gum choose --no-limit --header "Select hosts for '$name'") || return
  local members=() line host joined
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    host="${line%% (*}"
    members+=("$host")
  done <<<"$selected"
  if [[ ${#members[@]} -eq 0 ]]; then
    echo_err "Preset must contain at least one host."
    return
  fi
  joined="${members[0]}"
  for i in "${!members[@]}"; do
    if [[ "$i" -eq 0 ]]; then
      continue
    fi
    joined+=","${members[$i]}
  done
  if [[ "$exists_idx" -ge 0 ]]; then
    PRESET_MEMBERS[$exists_idx]="$joined"
  else
    PRESET_NAMES+=("$name")
    PRESET_MEMBERS+=("$joined")
  fi
  save_config
  echo "Saved preset '$name'."
}

delete_preset() {
  if [[ ${#PRESET_NAMES[@]} -eq 0 ]]; then
    echo_err "No presets to delete."
    return
  fi
  local choice
  choice=$(select_preset_name | gum choose --header "Select preset to delete") || return
  if ! gum confirm "Delete preset '$choice'?"; then
    echo "Cancelled."
    return
  fi
  local idx new_names=() new_members=() i
  idx=$(find_preset_index "$choice") || true
  for i in "${!PRESET_NAMES[@]}"; do
    if [[ "$i" -eq "$idx" ]]; then
      continue
    fi
    new_names+=("${PRESET_NAMES[$i]}")
    new_members+=("${PRESET_MEMBERS[$i]}")
  done
  PRESET_NAMES=("${new_names[@]}")
  PRESET_MEMBERS=("${new_members[@]}")
  save_config
  echo "Deleted preset '$choice'."
}

manage_presets_menu() {
  while true; do
    local options=(
      "Create preset"
      "Edit preset"
      "Delete preset"
      "Back"
    )
    local action
    action=$(printf '%s\n' "${options[@]}" | gum choose --header "Preset management") || return
    case "$action" in
      "Create preset") create_preset ;;
      "Edit preset")
        if [[ ${#PRESET_NAMES[@]} -eq 0 ]]; then
          echo_err "No presets to edit."
        else
          local choice
          choice=$(select_preset_name | gum choose --header "Select preset to edit") || continue
          edit_preset "$choice"
        fi
        ;;
      "Delete preset") delete_preset ;;
      "Back") break ;;
    esac
  done
}

main_menu() {
  while true; do
    load_config
    local options=(
      "Apply preset to /etc/hosts"
      "Apply single host to /etc/hosts"
      "Remove preset from /etc/hosts"
      "Remove single host from /etc/hosts"
      "Remove all hostshelper hosts"
      "Add or update host"
      "Manage presets"
      "Quit"
    )
    local choice
    choice=$(printf '%s\n' "${options[@]}" | gum choose --header "hostshelper") || exit 0
    case "$choice" in
      "Apply preset to /etc/hosts") apply_preset_flow ;;
      "Apply single host to /etc/hosts") apply_single_host_flow ;;
      "Remove preset from /etc/hosts") remove_preset_from_hosts_flow ;;
      "Remove single host from /etc/hosts") remove_single_host_flow ;;
      "Remove all hostshelper hosts") remove_all_hosts_flow ;;
      "Add or update host") create_or_update_host ;;
      "Manage presets") manage_presets_menu ;;
      "Quit") exit 0 ;;
    esac
  done
}

ensure_gum
if [[ $# -gt 0 ]]; then
  if [[ $# -gt 1 ]]; then
    echo_err "Usage: hostshelper [preset-name]"
    exit 1
  fi
  toggle_preset_cli "$1"
  exit 0
fi
main_menu
