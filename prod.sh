#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [ -f .env ]; then
  set -a
  . ./.env
  set +a
fi

IMAGE_REPO="${IMAGE_REPO:-ghcr.io/ryaneggz/msb-ubuntu-dind}"
IMAGE_VERSION="${IMAGE_VERSION:-latest}"
IMAGE="$IMAGE_REPO:$IMAGE_VERSION"

SANDBOX_NAME="${SANDBOX_NAME:-prod}"
CPUS="${CPUS:-4}"
MAX_CPUS="${MAX_CPUS:-8}"
MEMORY="${MEMORY:-8G}"
MAX_MEMORY="${MAX_MEMORY:-16G}"
ROOT_DISK="${ROOT_DISK:-12G}"
DOCKER_DATA_VOLUME="${DOCKER_DATA_VOLUME:-prod-docker-data}"
DOCKER_DATA_SIZE="${DOCKER_DATA_SIZE:-50G}"
WORKDIR="${WORKDIR:-/home/dev}"
MOUNT_DIRS="${MOUNT_DIRS:-/opt/infra-stack:/home/dev/infra-stack /opt/oh-deploy:/home/dev/oh-deploy /opt/langfuse:/home/dev/langfuse}"
PORTS="${PORTS:-3000:3000 3005:3005}"

if ! msb images | grep -q "$IMAGE_REPO.*$IMAGE_VERSION"; then
  if ! msb pull "$IMAGE"; then
    tar="$(mktemp -t msb-image-XXXXXX.tar)"
    trap 'rm -f "$tar"' EXIT
    docker pull "$IMAGE"
    docker save -o "$tar" "$IMAGE"
    msb load --input "$tar"
  fi
fi

args=(
  run -d
  --replace
  --pull never
  --name "$SANDBOX_NAME"
  --cpus "$CPUS"
  --max-cpus "$MAX_CPUS"
  --memory "$MEMORY"
  --max-memory "$MAX_MEMORY"
  --root-disk "$ROOT_DISK"
  --mount-named "$DOCKER_DATA_VOLUME:/var/lib/docker:kind=disk,size=$DOCKER_DATA_SIZE"
  --workdir "$WORKDIR"
)

for mount in $MOUNT_DIRS; do
  args+=(--mount-dir "$mount")
done

for port in $PORTS; do
  args+=(-p "$port")
done

msb "${args[@]}" "$IMAGE"

# -----------------------------------------------------------------------------
# Attach
# -----------------------------------------------------------------------------
# msb exec -t prod -- sh

# -----------------------------------------------------------------------------
# Resource changes
# -----------------------------------------------------------------------------

# Increase RAM live, up to the current 16G ceiling.
# msb modify prod --memory 12G
# msb modify prod --memory 16G

# Reduce RAM.
# msb modify prod --memory 8G

# Increase CPUs live, up to the current 8 CPU ceiling.
# msb modify prod --cpus 6
# msb modify prod --cpus 8

# Reduce CPUs.
# msb modify prod --cpus 4


# -----------------------------------------------------------------------------
# Increase resource ceilings
# Requires restart because max-memory/max-cpus are boot-time limits.
# -----------------------------------------------------------------------------

# Increase RAM ceiling and active RAM together.
# msb modify prod --max-memory 24G --memory 24G --restart

# Increase CPU ceiling and active CPUs together.
# msb modify prod --max-cpus 12 --cpus 12 --restart


# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------

# msb stop prod
# msb start prod
# msb restart prod


# -----------------------------------------------------------------------------
# Monitoring
# -----------------------------------------------------------------------------

# msb ls
# msb metrics prod
# msb metrics prod --watch

# msb volume ls
# msb volume inspect prod-docker-data
