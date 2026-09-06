#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" = "0" ] && [ -n "${DOCKER_USER:-}" ] && id -u "$DOCKER_USER" >/dev/null 2>&1; then
  install -d -o "$DOCKER_USER" -g "$DOCKER_USER" /workspace
fi

exec "$@"
