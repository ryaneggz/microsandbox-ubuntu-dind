# microsandbox-ubuntu-dind

Ubuntu 26.04 Microsandbox image with Docker-in-Docker, plus a `prod.sh` launcher.
Ships an unprivileged `dev` user (uid 1000) in the `docker` group, so `docker`
needs no `sudo`.
Precursor to how openharness-cloud provisions an Ubuntu MSB VM with DinD.

## Pull from GHCR (no build)

Released images are published to `ghcr.io/ryaneggz/microsandbox-ubuntu-dind`.

```sh
# Pull a released version (or :latest, :0, :0.1).
docker pull ghcr.io/ryaneggz/microsandbox-ubuntu-dind:0.1.0
docker tag ghcr.io/ryaneggz/microsandbox-ubuntu-dind:0.1.0 prod-msb-ubuntu:26.04

# Hand it to Microsandbox's image store.
docker save -o prod-msb-ubuntu-26.04.tar prod-msb-ubuntu:26.04
msb load --input prod-msb-ubuntu-26.04.tar
rm prod-msb-ubuntu-26.04.tar
```

No authentication is needed once the package is public. Images are published for
`linux/amd64` and `linux/arm64`.

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

```sh
# Build the Ubuntu 26.04 DinD image.
docker build -t prod-msb-ubuntu:26.04 .

# Export the Docker image.
docker save \
  -o prod-msb-ubuntu-26.04.tar \
  prod-msb-ubuntu:26.04

# Load it into Microsandbox's image store.
msb load --input prod-msb-ubuntu-26.04.tar

# Confirm the image exists.
msb images

# Remove the intermediate archive.
rm prod-msb-ubuntu-26.04.tar
```

## Run

```sh
# Recreate prod.
bash prod.sh
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

- `dev` (uid/gid 1000) owns `/workspace` and belongs to the `docker` group, so
  `docker`, `docker compose`, and `docker buildx` work without `sudo`.
- `dev` also has passwordless `sudo` for package installs and other admin work.
- Override the account at build time with
  `--build-arg USERNAME=... --build-arg USER_UID=... --build-arg USER_GID=...`.

Run a shell as that user:

```sh
msb exec prod -- su - dev
```

- `Dockerfile` — Ubuntu 26.04 base with Docker Engine, Compose, Buildx, telnet, and the `dev` user.
- `entrypoint.sh` — keeps `/workspace` owned by `dev`, then execs the command (`dockerd` by default).
- `prod.sh` — `msb run` invocation plus commented lifecycle, resize, and monitoring recipes.
- `.github/workflows/release.yml` — tag-driven SemVer build and publish to GHCR.
- `.github/workflows/ci.yml` — builds the image on every PR and push to `main`.
