#!/usr/bin/env bash
# Install the host-side lifecycle for the `prod` msb sandbox.
#
# Idempotent. Installs the systemd *user* unit, enables lingering so it starts
# at boot without a login, and preflights the one prerequisite that silently
# breaks everything: the user manager's `kvm` group membership.
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
UNIT_SRC="$REPO/systemd/msb-prod.service"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
UNIT_DST="$UNIT_DIR/msb-prod.service"

log()  { printf '[install-host] %s\n' "$*"; }
fail() { printf '[install-host] ERROR: %s\n' "$*" >&2; exit 1; }

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
[ -f "$UNIT_SRC" ]   || fail "missing $UNIT_SRC"
[ -x "$REPO/ensure-prod.sh" ] || fail "missing or non-executable $REPO/ensure-prod.sh"
[ -f "$REPO/.env" ]  || log "WARNING: no .env; prod.sh will fall back to built-in defaults"

id -nG | tr ' ' '\n' | grep -qx kvm || log "WARNING: $USER is not in the kvm group (getent group kvm)"

preflight_kvm

log "installing unit -> $UNIT_DST"
mkdir -p "$UNIT_DIR"
install -m 0644 "$UNIT_SRC" "$UNIT_DST"

log "enabling linger for $USER (start at boot without login)"
loginctl enable-linger "$USER"

systemctl --user daemon-reload
systemctl --user enable msb-prod.service

log "installed and enabled. Start it with:"
log "  systemctl --user start msb-prod.service"
log "Verify:"
log "  systemctl --user status msb-prod.service"
log "  msb ls && msb exec prod -- docker ps"
