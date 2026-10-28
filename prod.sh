#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

export IMAGE_REPO="${IMAGE_REPO:-ghcr.io/ryaneggz/msb-ubuntu-dind}"
export IMAGE_VERSION="${IMAGE_VERSION:-latest}"

export SANDBOX_NAME=prod
export CPUS=2
export MAX_CPUS=4
export MEMORY=2G
export MAX_MEMORY=4G
export ROOT_DISK=12G

export DOCKER_DATA_VOLUME=prod-docker-data
export DOCKER_DATA_SIZE=50G

export WORKDIR=/home/dev
export MOUNT_DIRS="/opt/infra-stack:/home/dev/infra-stack /opt/langfuse:/home/dev/langfuse /opt/oh-deploy:/home/dev/oh-deploy"
export PORTS="127.0.0.1:3000:3000 127.0.0.1:3005:3005"
export EXTRA_ARGS="--net-default-egress deny --net-rule allow:egress@host:udp:53,allow:egress@host:tcp:53,allow:egress@public,allow:egress@host:tcp:5432"

exec ./sandbox.sh
