#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" = "0" ] && [ -n "${DOCKER_USER:-}" ]; then
  home="$(getent passwd "$DOCKER_USER" | cut -d: -f6 || true)"
  if [ -n "$home" ]; then
    install -d -o "$DOCKER_USER" -g "$DOCKER_USER" "$home"
    find "$home" -maxdepth 1 -mindepth 1 \
      -exec chown "$DOCKER_USER:$DOCKER_USER" {} +
  fi
fi

exec "$@"
