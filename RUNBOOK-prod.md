# prod sandbox runbook

Operational notes for the `prod` msb sandbox (`ghcr.io/ryaneggz/msb-ubuntu-dind`)
running the `oh-deploy` stack: gateway, web, cloudflared, postgres.

## Bring prod up by hand

Only needed when the systemd unit is not running (it is the normal path - see
"The systemd unit" below). Stop the unit first if it is active, or it will
race you.

```sh
msb start prod
tmux new-session -d -s msb-prod-dockerd "$HOME/.microsandbox/bin/msb exec prod -- dockerd"
```

Containers self-start from there (`restart: always`). Verify:

```sh
msb exec prod -- docker ps --format '{{.Names}} | {{.Status}}'
```

Expect 4 containers; gateway, web and postgres report `(healthy)` within ~45s.

## Why dockerd needs starting at all

`msb start` is boot-only **by design**: it resumes the VM but never re-runs the
image ENTRYPOINT/CMD. See https://docs.microsandbox.dev/sandboxes/commands
Since the image sets `CMD ["dockerd"]`, dockerd is the workload and does not
return on its own. Only `msb run` (create) executes it.

Do NOT "fix" this by recreating the sandbox on every boot: `prod.sh` runs
`msb run --replace`, which rebuilds the root disk and discards `/home/dev`
state that is not on a mount (`.oh` sandbox definitions, `.copilot` auth).

## The KVM group trap  (root cause of the failed automation, 2026-09-16)

`msb start` from a systemd **user** service fails:

```
panicked at msb_krun_vmm/src/linux/vstate.rs:453
Error creating the Kvm object: Error(13)      # EACCES on /dev/kvm
```

`/dev/kvm` is `root:kvm 0660`. Supplementary groups are snapshotted when a
process starts. The `systemd --user` manager started 2026-07-10; the account
was added to `kvm` on 2026-08-12. The manager therefore has no `kvm` group and
neither does any service it spawns. Manual starts work because the login shell
does have the group.

`systemctl --user daemon-reexec` does NOT refresh credentials (verified).

Check whether the manager can reach KVM:

```sh
grep ^Groups: /proc/$(pgrep -u "$USER" -f 'systemd --user' | head -1)/status
getent group kvm        # note the gid, e.g. 992
```

gid present -> user services can start the VM. Absent -> they cannot.

Fixes, best first:

1. Reboot the host. logind recreates the lingering manager with current
   groups. No permission changes. Preferred.
2. `loginctl terminate-user "$USER"` - restarts the manager without a reboot,
   but kills every process you own, including tmux and any agent session.
3. udev rule `KERNEL=="kvm", GROUP="kvm", MODE="0666"` in
   /etc/udev/rules.d/99-kvm.rules (+ `sudo chmod 0666 /dev/kvm` to apply now).
   Works regardless of groups, but lets any local user create VMs.

## Setting this host up from scratch

```sh
git clone <this repo> ~/microsandbox-ubuntu-dind
cd ~/microsandbox-ubuntu-dind
cp .example.env .env          # then edit secrets/sizing
./prod.sh                     # create the sandbox
./install-host.sh             # install + enable the systemd user unit
systemctl --user start msb-prod.service
```

`install-host.sh` is idempotent and refuses to install until a systemd user
service can open /dev/kvm - see "The KVM group trap" below.

## The systemd unit

Source of truth: `systemd/msb-prod.service` in this repo, installed to
`~/.config/systemd/user/` by `install-host.sh`. It runs `ensure-prod.sh`, which
converges the sandbox and then supervises dockerd in the foreground.

Verified working: after a host reboot on 2026-09-16 the unit brought the
sandbox and dockerd up unattended on the first attempt (`NRestarts=0`), and
all four containers self-started via `restart: always`.

Enable and start it (install-host.sh already does this):

```sh
systemctl --user enable --now msb-prod.service
systemctl --user status msb-prod.service
```

If the KVM preflight fails, the unit will loop and stop after
`StartLimitBurst=5`. Fix the group problem first - do not work around it by
recreating the sandbox.

Unit settings that matter: `RestartSec=30` and `StartLimitBurst=5` so a broken
sandbox fails loudly instead of hammering `msb start`; `KillMode=process` so
systemd does not kill the VM along with the script.

`ensure-prod.sh` guard policy:

| sandbox state | action                                  |
|---------------|-----------------------------------------|
| running       | leave alone                             |
| stopped       | `msb start` (non-destructive)           |
| draining etc. | wait for the transient state to settle  |
| missing       | `prod.sh` recreate (nothing to lose)    |

It retries `msb start` internally with backoff under a `flock`, because msb
aborts with SIGABRT if it races a teardown still in flight.

## Resource sizing

`.env` drives `prod.sh`. Kept in sync with the running sandbox on 2026-09-16:
`CPUS=2 MAX_CPUS=4 MEMORY=2G MAX_MEMORY=4G`. If these drift, the next
`prod.sh` run silently resizes the sandbox.

Raise memory live up to the 4G ceiling: `msb modify prod --memory 4G`.
Above the ceiling needs `--max-memory ... --restart` (boot-time limit).

## Docker settings applied 2026-09-16

- `restart: always` on gateway, web, cloudflared, postgres (compose sources in
  /opt/oh-deploy). `unless-stopped` does NOT restart containers that the daemon
  itself stopped during shutdown - that is why the stack stayed down after a
  dockerd bounce.
- `oh-cloud-provisioner` deliberately left `unless-stopped`: it exits 127, and
  `always` would crash-loop it on every boot.
- `/etc/docker/daemon.json` in the guest sets `live-restore: true`, so
  containers survive a dockerd restart. Apply changes with `kill -HUP $(pgrep -x dockerd)`.

## Disk note

`prod-docker-data/disk.raw` is a 50 GiB non-sparse image with no TRIM
passthrough, so space freed inside the guest is not returned to the host.
Reclaim it offline: zero-fill free space in the guest, `msb stop prod`, then
`fallocate -d .../prod-docker-data/disk.raw` on the host. Recovered 44.7 GiB
on 2026-09-16.
