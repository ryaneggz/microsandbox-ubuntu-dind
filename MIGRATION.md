# Migration: pre-generic layout -> generic runtime

This branch is an **archive** of `main` before the generic-runtime refactor
(commit `91c8431`, released as `v0.5.0`). It is the layout that hard-codes a
sandbox named `prod`. Nothing new will land here.

Current `main` renames the scripts and makes the systemd unit a per-sandbox
template. See PR #2.

## What changed

| This branch | Current `main` |
|---|---|
| `prod.sh` | `sandbox.sh` |
| `ensure-prod.sh` | `ensure-sandbox.sh` |
| `RUNBOOK-prod.md` | `RUNBOOK.md` |
| `systemd/msb-prod.service` | `systemd/msb-sandbox@.service` (templated) |
| `SANDBOX_NAME` default `prod` | default `sandbox` |
| `MOUNT_DIRS` / `PORTS` hard-coded | empty, with commented examples |

The image itself is unchanged. Only scripts, the unit, and docs moved.

## Migrating an existing host

**Read this before checking out `main`.** If this repo directory is the one a
systemd unit points at, checking out `main` removes `ensure-prod.sh` while
`msb-prod.service` still references it. The unit keeps running (the old inode
is held) but any restart or reboot then fails.

Do it in this order:

```sh
# 1. Retire the old unit FIRST, while its ExecStart still exists.
systemctl --user disable --now msb-prod.service

# 2. Move to the new layout.
git checkout main && git pull --ff-only

# 3. Reinstall as a templated instance. Your .env keeps working:
#    SANDBOX_NAME=prod selects msb-sandbox@prod.service
./install-host.sh
systemctl --user start "msb-sandbox@$(awk -F= '/^SANDBOX_NAME=/{print $2}' .env | tr -d '"'"'"'"'"'"').service"

# 4. Remove the retired unit file.
rm -f ~/.config/systemd/user/msb-prod.service
systemctl --user daemon-reload
```

Verify:

```sh
systemctl --user status "msb-sandbox@<name>.service"
msb ls
msb exec <name> -- docker ps
```

Expect the unit active with `NRestarts=0`, the sandbox running, and your
containers back.

## Rolling back

This branch stays put, and `v0.5.0` tags the same commit:

```sh
git checkout archive/main-pre-generic     # or: git checkout v0.5.0
systemctl --user disable --now "msb-sandbox@<name>.service"
./install-host.sh
systemctl --user start msb-prod.service
```

## Sandbox state is not affected

Migration touches only host-side scripts and the unit. The sandbox, its root
disk, its named Docker volume and its containers are untouched. Do not
recreate the sandbox as part of this - `sandbox.sh` / `prod.sh` run
`msb run --replace`, which rebuilds the root disk.
