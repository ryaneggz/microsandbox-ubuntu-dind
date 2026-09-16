#!/usr/bin/env bash
# Install the host-side lifecycle for an msb sandbox.
#
# Usage: ./install-host.sh [SANDBOX_NAME]
# Name resolution: $1, then $SANDBOX_NAME, then SANDBOX_NAME in .env, then "sandbox".
#
# Idempotent. Installs the templated systemd *user* unit, enables lingering so
# it starts at boot without a login, and preflights the one prerequisite that
# silently breaks everything: the user manager's `kvm` group membership.
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
UNIT_SRC="$REPO/systemd/msb-sandbox@.service"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
UNIT_DST="$UNIT_DIR/msb-sandbox@.service"

log()  { printf '[install-host] %s\n' "$*"; }
fail() { printf '[install-host] ERROR: %s\n' "$*" >&2; exit 1; }

resolve_name() {
  local n="${1:-${SANDBOX_NAME:-}}"
  if [ -z "$n" ] && [ -f "$REPO/.env" ]; then
    n="$(awk -F= '/^SANDBOX_NAME=/{gsub(/["'"'"']/,"",$2); print $2}' "$REPO/.env" | tail -1)"
  fi
  printf '%s' "${n:-sandbox}"
}

SANDBOX="$(resolve_name "${1:-}")"
UNIT="msb-sandbox@${SANDBOX}.service"

# --- preflight: /dev/kvm reachable from a systemd user service ---------------
# Supplementary groups are snapshotted when a process starts. If the user was
# added to `kvm` after the systemd --user manager started, every user service
# it spawns gets EACCES on /dev/kvm and `msb start` aborts with SIGABRT:
#   panicked at msb_krun_vmm/src/linux/vstate.rs: Error creating the Kvm object: Error(13)
preflight_kvm() {
  [ -e /dev/kvm ] || fail "/dev/kvm does not exist; is virtualization enabled?"

  if systemd-run --user --wait --pipe --quiet /bin/sh -c ': < /dev/kvm' 2>/dev/null; then
    log "preflight OK: systemd user services can open /dev/kvm"
    return 0
  fi

  cat >&2 <<'MSG'
[install-host] ERROR: systemd user services cannot open /dev/kvm (EACCES).

The systemd --user manager does not carry the `kvm` group, so `msb start`
will abort with SIGABRT before the agent relay comes up.

  Check:  grep ^Groups: /proc/$(pgrep -u "$USER" -f 'systemd --user' | head -1)/status
          getent group kvm

Fixes, best first:
  1. Reboot. logind recreates the lingering manager with current groups.
  2. loginctl terminate-user "$USER"   (restarts the manager; kills your
     session and any tmux)
  3. udev rule KERNEL=="kvm", GROUP="kvm", MODE="0666" in
     /etc/udev/rules.d/99-kvm.rules, plus `sudo chmod 0666 /dev/kvm` to apply
     now. Works regardless of groups, but lets any local user create VMs.

Re-run this script once the check passes.
MSG
  exit 1
}

command -v systemctl >/dev/null || fail "systemctl not found"
[ -f "$UNIT_SRC" ] || fail "missing $UNIT_SRC"
[ -x "$REPO/ensure-sandbox.sh" ] || fail "missing or non-executable $REPO/ensure-sandbox.sh"
[ -f "$REPO/.env" ] || log "WARNING: no .env; sandbox.sh will use built-in defaults"

id -nG | tr ' ' '\n' | grep -qx kvm || log "WARNING: $USER is not in the kvm group (getent group kvm)"

log "sandbox: $SANDBOX"
preflight_kvm

log "installing unit template -> $UNIT_DST"
mkdir -p "$UNIT_DIR"
install -m 0644 "$UNIT_SRC" "$UNIT_DST"

log "enabling linger for $USER (start at boot without login)"
loginctl enable-linger "$USER"

systemctl --user daemon-reload
systemctl --user enable "$UNIT"

log "installed and enabled $UNIT. Start it with:"
log "  systemctl --user start $UNIT"
log "Verify:"
log "  systemctl --user status $UNIT"
log "  msb ls && msb exec $SANDBOX -- docker ps"
