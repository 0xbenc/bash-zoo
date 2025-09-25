#!/bin/bash
set -euo pipefail

# Installer for airplane (Debian-like Linux)
# - Creates group 'airplane' and adds current user to it
# - Installs iptables/ip6tables rules to block WAN egress for group 'airplane'
#   while allowing LAN and loopback

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing dependency: $1" >&2
    exit 1
  }
}

sudo_prep() {
  if command -v sudo >/dev/null 2>&1; then
    sudo -v || true
  fi
}

ensure_firewall_tooling() {
  local needs_install=0
  if ! command -v iptables >/dev/null 2>&1; then
    needs_install=1
  fi
  if ! command -v ip6tables >/dev/null 2>&1; then
    needs_install=1
  fi

  if [[ $needs_install -eq 1 ]]; then
    if ! command -v apt >/dev/null 2>&1; then
      echo "Error: iptables tooling missing and 'apt' is unavailable. Install iptables manually." >&2
      exit 1
    fi
    echo "Installing iptables tooling (Debian/Ubuntu)..."
    sudo apt update -y
    sudo apt install -y iptables iptables-persistent
  fi

  if ! command -v iptables >/dev/null 2>&1; then
    echo "Error: iptables not found after installation attempt." >&2
    exit 1
  fi

  if ! command -v ip6tables >/dev/null 2>&1; then
    echo "Warning: ip6tables not found; IPv6 egress will not be filtered." >&2
  fi
}

ensure_group() {
  if getent group airplane >/dev/null 2>&1; then
    :
  else
    echo "Creating group 'airplane'..."
    sudo groupadd airplane
  fi

  # Add current user if not already a member
  if id -nG "$USER" | tr ' ' '\n' | grep -qx airplane; then
    :
  else
    echo "Adding user '$USER' to group 'airplane'..."
    sudo usermod -aG airplane "$USER"
    echo "User '$USER' added to 'airplane'. You may need to re-login for membership to apply."
  fi
}

iptables_rule() {
  # Helper to run iptables with sudo; tolerate missing -w flag
  local tool="$1"; shift
  if "$tool" -w -S >/dev/null 2>&1; then
    sudo "$tool" -w "$@"
  else
    sudo "$tool" "$@"
  fi
}

setup_iptables_v4() {
  if ! command -v iptables >/dev/null 2>&1; then
    echo "iptables not found; skipping IPv4 rules." >&2
    return 0
  fi

  echo "Configuring IPv4 egress rules for group 'airplane'..."
  # Create chain if missing; then flush and repopulate
  if ! iptables_rule iptables -L AIRPLANE_OUTPUT >/dev/null 2>&1; then
    iptables_rule iptables -N AIRPLANE_OUTPUT
  fi
  iptables_rule iptables -F AIRPLANE_OUTPUT

  # Allow loopback and LAN ranges
  iptables_rule iptables -A AIRPLANE_OUTPUT -o lo -j ACCEPT
  iptables_rule iptables -A AIRPLANE_OUTPUT -d 127.0.0.0/8   -j ACCEPT
  iptables_rule iptables -A AIRPLANE_OUTPUT -d 10.0.0.0/8    -j ACCEPT
  iptables_rule iptables -A AIRPLANE_OUTPUT -d 172.16.0.0/12 -j ACCEPT
  iptables_rule iptables -A AIRPLANE_OUTPUT -d 192.168.0.0/16 -j ACCEPT
  iptables_rule iptables -A AIRPLANE_OUTPUT -d 169.254.0.0/16 -j ACCEPT
  # Multicast/mDNS
  iptables_rule iptables -A AIRPLANE_OUTPUT -d 224.0.0.0/4 -j ACCEPT

  # Reject everything else (fail fast)
  iptables_rule iptables -A AIRPLANE_OUTPUT -j REJECT

  # Ensure OUTPUT jumps into our chain for group 'airplane'
  if iptables_rule iptables -C OUTPUT -m owner --gid-owner airplane -j AIRPLANE_OUTPUT >/dev/null 2>&1; then
    :
  else
    # Insert at the top to ensure evaluation before broad ACCEPT rules
    iptables_rule iptables -I OUTPUT 1 -m owner --gid-owner airplane -j AIRPLANE_OUTPUT
  fi
}

setup_iptables_v6() {
  if ! command -v ip6tables >/dev/null 2>&1; then
    echo "ip6tables not found; skipping IPv6 rules." >&2
    return 0
  fi

  echo "Configuring IPv6 egress rules for group 'airplane'..."
  if ! iptables_rule ip6tables -L AIRPLANE6_OUTPUT >/dev/null 2>&1; then
    iptables_rule ip6tables -N AIRPLANE6_OUTPUT
  fi
  iptables_rule ip6tables -F AIRPLANE6_OUTPUT

  # Allow loopback and local/link scopes
  iptables_rule ip6tables -A AIRPLANE6_OUTPUT -o lo -j ACCEPT
  iptables_rule ip6tables -A AIRPLANE6_OUTPUT -d ::1/128  -j ACCEPT
  iptables_rule ip6tables -A AIRPLANE6_OUTPUT -d fe80::/10 -j ACCEPT
  iptables_rule ip6tables -A AIRPLANE6_OUTPUT -d fc00::/7 -j ACCEPT
  # Multicast
  iptables_rule ip6tables -A AIRPLANE6_OUTPUT -d ff00::/8 -j ACCEPT

  iptables_rule ip6tables -A AIRPLANE6_OUTPUT -j REJECT

  if iptables_rule ip6tables -C OUTPUT -m owner --gid-owner airplane -j AIRPLANE6_OUTPUT >/dev/null 2>&1; then
    :
  else
    iptables_rule ip6tables -I OUTPUT 1 -m owner --gid-owner airplane -j AIRPLANE6_OUTPUT
  fi
}

main() {
  sudo_prep || true
  ensure_firewall_tooling
  require_cmd id
  ensure_group
  setup_iptables_v4
  setup_iptables_v6
  echo "airplane (debian): install complete. Open a new shell or use 'airplane' to start an airplane subshell."
}

main "$@"
