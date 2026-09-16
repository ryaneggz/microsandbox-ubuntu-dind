# Sandbox runbook

Operating a sandbox created by `sandbox.sh`. Substitute your own
`SANDBOX_NAME` for `<name>` throughout; it is whatever `.env` sets.

## Bring a sandbox up by hand

Only needed when the systemd unit is not running (it is the normal path - see
"The systemd unit"). Stop the unit first if it is active, or it will race you.

```sh
msb start <name>
tmux new-session -d -s msb-<name>-dockerd "$HOME/.microsandbox/bin/msb exec <name> -- dockerd"
```

Containers with a `restart: always` policy start themselves once dockerd is up.
Verify:

```sh
msb exec <name> -- docker ps --format '{{.Names}} | {{.Status}}'
```

## Why dockerd needs starting at all

`msb start` is boot-only **by design**: it resumes the VM but never re-runs the
image ENTRYPOINT/CMD. See https://docs.microsandbox.dev/sandboxes/commands
Since the image sets `CMD ["dockerd"]`, dockerd is the workload and does not
return on its own. Only `msb run` (create) executes it.

Do NOT "fix" this by recreating the sandbox on every boot: `sandbox.sh` runs
`msb run --replace`, which rebuilds the root disk and discards anything written
there that is not on a `MOUNT_DIRS` mount or a named volume.

## The KVM group trap

`msb start` from a systemd **user** service fails:

```
panicked at msb_krun_vmm/src/linux/vstate.rs:453
Error creating the Kvm object: Error(13)      # EACCES on /dev/kvm
```

`/dev/kvm` is `root:kvm 0660`. Supplementary groups are snapshotted when a
process starts. A `systemd --user` manager started before the account was added
to `kvm` has no `kvm` group, and neither does any service it spawns. Manual
starts work because the login shell does have the group.

`systemctl --user daemon-reexec` does NOT refresh credentials.

Check whether the manager can reach KVM:

```sh
grep ^Groups: /proc/$(pgrep -u "$USER" -f 'systemd --user' | head -1)/status
getent group kvm        # note the gid
```

gid present -> user services can start the VM. Absent -> they cannot.
`install-host.sh` runs this check and refuses to install until it passes.

Fixes, best first:

1. Reboot the host. logind recreates the lingering manager with current
   groups. No permission changes. Preferred.
2. `loginctl terminate-user "$USER"` - restarts the manager without a reboot,
   but kills every process you own, including tmux and any agent session.
3. udev rule `KERNEL=="kvm", GROUP="kvm", MODE="0666"` in
   /etc/udev/rules.d/99-kvm.rules (+ `sudo chmod 0666 /dev/kvm` to apply now).
   Works regardless of groups, but lets any local user create VMs.

## Setting up a host from scratch

```sh
git clone <this repo> ~/microsandbox-ubuntu-dind
cd ~/microsandbox-ubuntu-dind
cp .example.env .env          # set SANDBOX_NAME, sizing, mounts, ports
./sandbox.sh                  # create the sandbox
./install-host.sh             # install + enable the systemd user unit
systemctl --user start msb-sandbox@<name>.service
```

`install-host.sh` is idempotent and gated on the KVM preflight above.

## The systemd unit

Source of truth: `systemd/msb-sandbox@.service` in this repo, installed to
`~/.config/systemd/user/` by `install-host.sh`. It is a **templated** unit -
one instance per sandbox, named by `%i`:

```sh
systemctl --user enable --now msb-sandbox@<name>.service
systemctl --user status msb-sandbox@<name>.service
```

It runs `ensure-sandbox.sh <name>`, which converges the sandbox and then
supervises dockerd in the foreground.

Verified: after a host reboot the unit brought sandbox and dockerd up
unattended on the first attempt (`NRestarts=0`).

If the KVM preflight fails, the unit will loop and stop after
`StartLimitBurst=5`. Fix the group problem rather than working around it by
recreating the sandbox.

Unit settings that matter: `RestartSec=30` and `StartLimitBurst=5` so a broken
sandbox fails loudly instead of hammering `msb start`; `KillMode=process` so
systemd does not kill the VM along with the script.

`ensure-sandbox.sh` guard policy:

| sandbox state | action                                  |
|---------------|-----------------------------------------|
| running       | leave alone                             |
| stopped       | `msb start` (non-destructive)           |
| draining etc. | wait for the transient state to settle  |
| missing       | `sandbox.sh` recreate (nothing to lose) |

It retries `msb start` internally with backoff under a `flock`, because msb
aborts with SIGABRT if it races a teardown still in flight. Do not move the
retry loop into systemd: rapid restarts race each other.

## Resource sizing

`.env` drives `sandbox.sh`. If these drift from the running sandbox, the next
`sandbox.sh` run silently resizes it.

Raise memory live up to the `MAX_MEMORY` ceiling:

```sh
msb modify <name> --memory 4G
```

Going above the ceiling needs `--max-memory ... --restart`, because
`max-memory` and `max-cpus` are boot-time limits.

## Container restart policy

Use `restart: always` for services that must survive a daemon restart.
`unless-stopped` does NOT restart containers that the daemon itself stopped
during shutdown, so a stack can stay down after a dockerd bounce.

Do not use `always` for a container that exits immediately on failure - it
will crash-loop on every boot.

The image ships `/etc/docker/daemon.json` with `live-restore: true`, so
containers survive a dockerd restart. Apply daemon config changes with
`kill -HUP $(pgrep -x dockerd)` rather than restarting the daemon.

## Disk note

The Docker data volume is a non-sparse raw image with no TRIM passthrough, so
space freed inside the guest is not returned to the host. Reclaim it offline:

1. Zero-fill free space in the guest:
   `dd if=/dev/zero of=/var/lib/docker/ZEROFILL bs=1M; sync; rm -f /var/lib/docker/ZEROFILL`
2. `msb stop <name>`
3. On the host: `fallocate -d ~/.microsandbox/volumes/<volume>/disk.raw`
4. `msb start <name>`

Stop the containers first so nothing is writing during the zero-fill.
