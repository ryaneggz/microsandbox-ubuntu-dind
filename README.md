# msb-starter

Ubuntu 26.04 Microsandbox image with Docker-in-Docker, plus a `prod.sh` launcher.
Precursor to how openharness-cloud provisions an Ubuntu MSB VM with DinD.

## Build and load

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
