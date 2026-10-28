#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

export IMAGE_REPO="${IMAGE_REPO:-ghcr.io/ryaneggz/msb-ubuntu-dind}"
export IMAGE_VERSION="${IMAGE_VERSION:-latest}"

export SANDBOX_NAME=infra
export CPUS=2
export MAX_CPUS=4
export MEMORY=2G
export MAX_MEMORY=4G
export ROOT_DISK=12G

export DOCKER_DATA_VOLUME=infra-docker-data
export DOCKER_DATA_SIZE=30G

export WORKDIR=/home/dev
export MOUNT_DIRS="/opt/infra-services:/home/dev/infra-services"
export PORTS="5433:5432"
export EXTRA_ARGS="--net public,private --net-rule allow:ingress@private"

exec ./sandbox.sh
