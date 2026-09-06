# microsandbox-ubuntu-dind

Ubuntu 26.04 Microsandbox image with Docker-in-Docker, plus a `prod.sh` launcher.
Ships an unprivileged `dev` user (uid 1000) in the `docker` group, so `docker`
needs no `sudo`.
Precursor to how openharness-cloud provisions an Ubuntu MSB VM with DinD.

## Run

`prod.sh` fetches the published image if the local Microsandbox store does not
have it, then starts the `prod` sandbox:

```sh
bash prod.sh
```

It prefers `msb pull`, and falls back to `docker pull` + `docker save` +
`msb load` on Microsandbox versions that cannot pull from a registry. Override
either half with environment variables:

```sh
# Pin a different released version.
IMAGE_VERSION=0.1.0 bash prod.sh

# Point at a locally built image instead (see "Build locally").
IMAGE_REPO=msb-ubuntu-dind IMAGE_VERSION=dev bash prod.sh
```

Images are published for `linux/amd64` and `linux/arm64` at
`ghcr.io/ryaneggz/microsandbox-ubuntu-dind`.

## Releasing

Releases are SemVer, cut by GitHub Actions from a tag:

```sh
git tag v0.1.0
git push origin v0.1.0
```

`.github/workflows/release.yml` builds both architectures, pushes
`0.1.0`, `0.1`, `0`, and `latest` to GHCR, and creates the GitHub Release.
A `-rc.1`-style prerelease tag skips `latest` and is marked as a prerelease.
`workflow_dispatch` accepts a version if you need to re-run one by hand.

## Build locally

Only needed when changing the image itself:

```sh
# Build the Ubuntu 26.04 DinD image.
docker build -t msb-ubuntu-dind:dev .

# Export the Docker image.
docker save -o msb-ubuntu-dind.tar msb-ubuntu-dind:dev

# Load it into Microsandbox's image store.
msb load --input msb-ubuntu-dind.tar

# Confirm the image exists.
msb images

# Remove the intermediate archive.
rm msb-ubuntu-dind.tar
```

Then run it:

```sh
IMAGE_REPO=msb-ubuntu-dind IMAGE_VERSION=dev bash prod.sh
```

## Verify

```sh
# Confirm Ubuntu 26.04.
msb exec prod -- cat /etc/os-release

# Confirm the unprivileged user can reach Docker without sudo.
msb exec prod -- su - dev -c 'docker info'
msb exec prod -- su - dev -c 'docker run --rm hello-world'

# Confirm Docker daemon is running.
msb exec prod -- docker info

# Confirm Compose.
msb exec prod -- docker compose version

# Important: validate actual nested container execution,
# not merely that the Docker daemon started.
msb exec prod -- docker run --rm hello-world
```

## SSH access

Microsandbox can serve SSH for a sandbox over stdio, so a workstation can reach
`prod` through the host that runs it. Add an entry like this to `~/.ssh/config`:

```sshconfig
Host prod-msb
    User dev
    IdentityFile ~/.ssh/<your-key>
    IdentitiesOnly yes
    ProxyCommand ssh <your-msb-host> /home/<user>/.local/bin/msb ssh serve prod --stdio
```

- `<your-msb-host>` is an existing `Host` entry for the machine running `msb`.
- `User dev` is the unprivileged account in the image. Use `root` only if
  `msb ssh serve` does not honour a non-root user on your Microsandbox version.
- Adjust the `msb` path if it is installed somewhere else on that machine.
- The same entry works as a VS Code Remote-SSH target.

Test the route from your workstation after the sandbox is running:

```sh
ssh prod-msb
```

## Files

## Users and privileges

The Docker daemon still runs as root — `dockerd` needs kernel privileges no
unprivileged user has — but nothing you do inside the sandbox has to:

- `dev` (uid/gid 1000) owns its home directory `/home/dev` and belongs to the `docker` group, so
  `docker`, `docker compose`, and `docker buildx` work without `sudo`.
- `dev` also has passwordless `sudo` for package installs and other admin work.
- Override the account at build time with
  `--build-arg USERNAME=... --build-arg USER_UID=... --build-arg USER_GID=...`.

Run a shell as that user:

```sh
msb exec prod -- su - dev
```

- `Dockerfile` — Ubuntu 26.04 base with Docker Engine, Compose, Buildx, telnet, and the `dev` user.
- `entrypoint.sh` — keeps `/home/dev` and its mount points owned by `dev`, then execs the command (`dockerd` by default).
- `prod.sh` — fetches the published image if needed, runs `msb run`, plus commented lifecycle, resize, and monitoring recipes.
- `.github/workflows/release.yml` — tag-driven SemVer build and publish to GHCR.
- `.github/workflows/ci.yml` — builds the image on every PR and push to `main`.
