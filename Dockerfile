FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive

# Base tooling + VS Code Remote SSH prerequisites.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      curl \
      nano \
      git \
      gzip \
      iproute2 \
      iptables \
      libstdc++6 \
      openssh-client \
      procps \
      tar \
      xz-utils && \
    rm -rf /var/lib/apt/lists/*

# Docker's official apt repository.
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc && \
    printf '%s\n' \
      'Types: deb' \
      'URIs: https://download.docker.com/linux/ubuntu' \
      "Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")" \
      'Components: stable' \
      "Architectures: $(dpkg --print-architecture)" \
      'Signed-By: /etc/apt/keyrings/docker.asc' \
      > /etc/apt/sources.list.d/docker.sources

# Docker Engine + Compose + Buildx.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      docker-ce \
      docker-ce-cli \
      containerd.io \
      docker-buildx-plugin \
      docker-compose-plugin && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

CMD ["dockerd"]
