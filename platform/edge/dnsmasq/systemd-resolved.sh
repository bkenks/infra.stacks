#!/usr/bin/env bash
# Toggle systemd-resolved on a host — frees (or restores) port 53 for the dnsmasq stack.
# systemd-resolved binds 127.0.0.53:53, colliding with dnsmasq's published host :53,
# so it must be off before deploying dnsmasq to that host. 'disabled' also disables the
# unit so it stays off across reboots; 'enabled' undoes both.
#
# Usage: systemd-resolved.sh <enabled|disabled> [--host <ssh-host>]
#   enabled          start + enable  systemd-resolved (systemctl enable  --now)
#   disabled         stop  + disable systemd-resolved (systemctl disable --now); frees :53
#   --host HOST      run over ssh on HOST instead of locally
#   -h, --help       show this help
#
# Note: this only toggles the service; it does not rewrite /etc/resolv.conf. The host's
# own resolver is pointed at dnsmasq separately — see ./README.md.
set -euo pipefail

usage() { sed -n '2,14p' "$0"; exit "${1:-0}"; }

STATE="" HOST=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)    HOST="${2:?--host needs a value}"; shift 2 ;;
    -h|--help) usage 0 ;;
    -*)        echo "unknown flag: $1" >&2; usage 1 ;;
    *)         if [[ -z "$STATE" ]]; then STATE="$1"; else echo "too many args" >&2; usage 1; fi; shift ;;
  esac
done
case "$STATE" in
  enabled|disabled) ;;
  "") usage 1 ;;
  *)  echo "state must be 'enabled' or 'disabled', got: '$STATE'" >&2; usage 1 ;;
esac

# Run systemctl with root: over ssh (--host) or locally, prepending sudo unless already root.
sctl() {
  if [[ -n "$HOST" ]]; then
    ssh "$HOST" "sudo systemctl $*"
  elif [[ "$(id -u)" -eq 0 ]]; then
    systemctl "$@"
  else
    sudo systemctl "$@"
  fi
}

if [[ "$STATE" == "disabled" ]]; then
  echo "disabling systemd-resolved${HOST:+ on $HOST} (frees port 53)..."
  sctl disable --now systemd-resolved
else
  echo "enabling systemd-resolved${HOST:+ on $HOST}..."
  sctl enable --now systemd-resolved
fi

echo "done. status:"
sctl is-enabled systemd-resolved || true
sctl is-active  systemd-resolved || true
