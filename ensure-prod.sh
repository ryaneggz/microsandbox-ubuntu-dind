#!/usr/bin/env bash
# Converge the `prod` msb sandbox to running-with-dockerd, then supervise dockerd.
#
# msb start is boot-only by design: it resumes the VM but never re-runs the image
# ENTRYPOINT/CMD, so dockerd (the image CMD) does not come back on its own.
# See docs.microsandbox.dev/sandboxes/commands.
#
# Guard policy, deliberately conservative:
#   running  -> leave alone
#   stopped  -> msb start        (NON-destructive; preserves the root disk)
#   missing  -> prod.sh          (recreate; ONLY when there is nothing to lose)
# A stopped sandbox is never recreated: that would discard /home/dev state
# (.oh sandbox definitions, .copilot auth) which lives on the root disk.
#
# `msb start` aborts with SIGABRT if it races a VM teardown still in flight, so
# retries are handled HERE with backoff, under a lock. Never let systemd drive
# the retry loop: rapid restarts race each other and the sandbox never comes up.
set -uo pipefail

MSB="${MSB:-$HOME/.microsandbox/bin/msb}"
SANDBOX="${SANDBOX_NAME:-prod}"
REPO="$(cd "$(dirname "$0")" && pwd)"
LOCK="${TMPDIR:-/tmp}/ensure-${SANDBOX}.lock"
START_TRIES="${START_TRIES:-6}"
START_BACKOFF="${START_BACKOFF:-10}"

log() { printf '[ensure-prod] %s\n' "$*"; }

sandbox_status() {
  "$MSB" ls 2>/dev/null | awk -v n="$SANDBOX" '$1 == n { print $3 }'
}

dockerd_running() {
  "$MSB" exec "$SANDBOX" -- sh -c 'pgrep -x dockerd >/dev/null' >/dev/null 2>&1
}

# msb reports transient lifecycle states (draining/starting/stopping) while a VM
# tears down. Acting on them races msb's lifecycle lock and aborts with SIGABRT.
wait_for_settled() {
  local i st
  for (( i = 1; i <= 36; i++ )); do
    st="$(sandbox_status)"
    case "$st" in
      draining|starting|stopping) sleep 5 ;;
      *) return 0 ;;
    esac
  done
  log "sandbox stuck in transient state '$st'"
  return 1
}

# Poll rather than trusting a single post-start read: status lags the command.
wait_for_running() {
  local i
  for (( i = 1; i <= 12; i++ )); do
    [ "$(sandbox_status)" = "running" ] && return 0
    sleep 5
  done
  return 1
}

start_with_retry() {
  local i out delay=$START_BACKOFF
  for (( i = 1; i <= START_TRIES; i++ )); do
    wait_for_settled || { sleep "$delay"; continue; }
    [ "$(sandbox_status)" = "running" ] && { log "sandbox already running"; return 0; }

    out="$("$MSB" start "$SANDBOX" 2>&1)"
    printf '%s\n' "$out" | tail -2

    # "already running" is success, not failure.
    case "$out" in *"already running"*) log "sandbox already running"; return 0 ;; esac

    wait_for_running && { log "sandbox running (attempt $i)"; return 0; }

    log "start attempt $i/$START_TRIES failed; retrying in ${delay}s"
    sleep "$delay"
    [ "$delay" -lt 60 ] && delay=$(( delay * 2 ))
  done
  log "sandbox failed to start after $START_TRIES attempts"
  return 1
}

converge_sandbox() {
  local st
  st="$(sandbox_status)"
  case "$st" in
    running) log "sandbox running" ;;
    stopped) log "sandbox stopped; starting (non-destructive)"; start_with_retry || return 1 ;;
    "")      log "sandbox MISSING; recreating via prod.sh"
             ( cd "$REPO" && ./prod.sh ) || { log "prod.sh failed"; return 1; } ;;
    draining|starting|stopping)
             log "sandbox in transient state '$st'; waiting to settle"
             wait_for_settled || return 1
             converge_sandbox; return $? ;;
    *)       log "unexpected status '$st'; refusing to act"; return 1 ;;
  esac
  return 0
}

# Serialize: never let two converge runs race msb's lifecycle lock.
exec 9>"$LOCK"
flock 9 || { log "could not acquire lock"; exit 1; }

converge_sandbox || exit 1

if dockerd_running; then
  log "dockerd already running; monitoring"
  while dockerd_running; do sleep 15; done
  log "dockerd exited; letting systemd restart us"
  exit 1
fi

log "starting dockerd in guest (foreground, supervised by systemd)"
exec "$MSB" exec "$SANDBOX" -- dockerd
