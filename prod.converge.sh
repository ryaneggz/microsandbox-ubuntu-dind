#!/usr/bin/env bash
# Restore the management Ed25519 key onto the sandbox ROOT DISK before dockerd.
#
# The key cannot be bound straight from /home/dev/oh-deploy: virtiofs presents
# mounted files as root:root, and the provisioner runs as uid 1000, so the
# in-container read fails. /etc/oh is root-disk state, so a RECREATED sandbox
# loses it -- and Docker then auto-creates the missing bind source as a
# DIRECTORY, which fails the mount ("not a directory") and leaves the container
# dead at exit 127 with no restart, because a create-time failure is not a
# restart event. Idempotent: 387 bytes, cheap to reinstall every converge.
set -euo pipefail

MSB="${MSB:-$HOME/.microsandbox/bin/msb}"
SANDBOX="${SANDBOX_NAME:-prod}"
KEY_SRC="${KEY_SRC:-/home/dev/oh-deploy/oh-ed25519}"
KEY_DST="${KEY_DST:-/etc/oh/oh-ed25519}"

"$MSB" exec "$SANDBOX" -- sh -c '
  src="$1"; dst="$2"
  [ -f "$src" ] || { echo "key source missing: $src" >&2; exit 1; }
  [ -d "$dst" ] && rm -rf "$dst"
  mkdir -p "$(dirname "$dst")"
  install -m 0400 -o 1000 -g 1000 "$src" "$dst"
' sh "$KEY_SRC" "$KEY_DST"
