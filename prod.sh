#!/usr/bin/env bash
set -euo pipefail

msb run -d \
  --replace \
  --pull never \
  --name prod \
  --cpus 4 \
  --max-cpus 8 \
  --memory 8G \
  --max-memory 16G \
  --root-disk 12G \
  --mount-dir /opt/infra-stack:/workspace/infra-stack \
  --mount-dir /opt/oh-deploy:/workspace/oh-deploy \
  --mount-dir /opt/langfuse:/workspace/langfuse \
  --mount-named prod-docker-data:/var/lib/docker:kind=disk,size=50G \
  --workdir /workspace \
  -p 3000:3000 \
  -p 3005:3005 \
  prod-msb-ubuntu:26.04

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
