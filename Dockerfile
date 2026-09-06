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
      sudo \
      tar \
      inetutils-telnet \
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

# Unprivileged default user with direct access to the Docker socket.
ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=1000
RUN if existing="$(getent passwd "$USER_UID" | cut -d: -f1)" && [ -n "$existing" ]; then \
      userdel --remove "$existing"; \
    fi && \
    groupadd --gid "$USER_GID" "$USERNAME" && \
    useradd --uid "$USER_UID" --gid "$USER_GID" --create-home --shell /bin/bash "$USERNAME" && \
    usermod --append --groups docker "$USERNAME" && \
    printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$USERNAME" > /etc/sudoers.d/"$USERNAME" && \
    chmod 0440 /etc/sudoers.d/"$USERNAME"

COPY --chmod=0755 entrypoint.sh /usr/local/bin/entrypoint.sh

ENV DOCKER_USER=dev
WORKDIR /home/dev

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["dockerd"]
