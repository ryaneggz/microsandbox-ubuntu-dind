# microsandbox-ubuntu-dind

Ubuntu 26.04 Microsandbox image with Docker-in-Docker, plus a `prod.sh` launcher.
Precursor to how openharness-cloud provisions an Ubuntu MSB VM with DinD.

## Pull from GHCR (no build)

Released images are published to `ghcr.io/ryaneggz/microsandbox-ubuntu-dind`.

```sh
# The repository is private, so authenticate first.
echo "$GITHUB_TOKEN" | docker login ghcr.io -u ryaneggz --password-stdin

# Pull a released version (or :latest, :0, :0.1).
docker pull ghcr.io/ryaneggz/microsandbox-ubuntu-dind:0.1.0
docker tag ghcr.io/ryaneggz/microsandbox-ubuntu-dind:0.1.0 prod-msb-ubuntu:26.04

# Hand it to Microsandbox's image store.
docker save -o prod-msb-ubuntu-26.04.tar prod-msb-ubuntu:26.04
msb load --input prod-msb-ubuntu-26.04.tar
rm prod-msb-ubuntu-26.04.tar
```

The token needs the `read:packages` scope. Images are published for
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

# Confirm Docker daemon is running.
msb exec prod -- docker info

# Confirm Compose.
msb exec prod -- docker compose version

# Important: validate actual nested container execution,
# not merely that the Docker daemon started.
msb exec prod -- docker run --rm hello-world
```

Test the SSH route from localhost afterward:

```sh
ssh prod-msb
```

## Files

- `Dockerfile` — Ubuntu 26.04 base with Docker Engine, Compose, Buildx.
- `prod.sh` — `msb run` invocation plus commented lifecycle, resize, and monitoring recipes.
- `.github/workflows/release.yml` — tag-driven SemVer build and publish to GHCR.
- `.github/workflows/ci.yml` — builds the image on every PR and push to `main`.
