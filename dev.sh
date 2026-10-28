#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

export IMAGE_REPO="${IMAGE_REPO:-ghcr.io/ryaneggz/msb-ubuntu-dind}"
export IMAGE_VERSION="${IMAGE_VERSION:-latest}"

export SANDBOX_NAME=dev
export CPUS=2
export MAX_CPUS=4
export MEMORY=2G
export MAX_MEMORY=4G
export ROOT_DISK=12G

export DOCKER_DATA_VOLUME=dev-docker-data
export DOCKER_DATA_SIZE=50G

export WORKDIR=/home/dev
export MOUNT_DIRS="/opt/agro-console/dev:/home/dev:uid=1000,gid=1000"
export PORTS="127.0.0.1:4000:3000 127.0.0.1:4005:3005"
export EXTRA_ARGS="--net-default-egress deny --net-rule allow:egress@host:udp:53,allow:egress@host:tcp:53,allow:egress@public,allow:egress@host:tcp:5432"

mkdir -p /opt/agro-console/dev

exec ./sandbox.sh
