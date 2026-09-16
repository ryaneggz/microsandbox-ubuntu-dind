# Shared services across sandboxes

Optional. Skip this unless one sandbox needs to reach a service that lives in
another sandbox on the same host.

A sandbox that exists to host shared infrastructure — a database, a cache, a
message broker — is just an ordinary sandbox whose service is published to the
host. Consumers are ordinary sandboxes granted a narrow rule allowing that one
host port.

## The constraint that shapes everything

Sandboxes cannot address each other directly. Each one runs its own userspace
network stack inside its own host process, and the `/30` shown on `eth0` is two
addresses private to that process, not a subnet on a wire. A guest dialing
another guest's address causes the host to attempt a connection to an address no
host interface owns.

That attempt does not fail the way you expect, which matters when you go to
verify any of this:

> A TCP connect succeeding from inside a sandbox proves only that egress policy
> allowed the destination. It does not prove anything is listening.

The guest's stack completes the three-way handshake locally, from policy
evaluation alone, before the host-side connection is attempted. A bogus address
naming no sandbox behaves identically to a real, listening service. **Only a
protocol-level exchange is evidence** — a real client handshake, an
authentication failure, a version string. Never `/dev/tcp`, never a bare port
scan.

The supported path runs through the host. Each sandbox's gateway address
rewrites to the host's `127.0.0.1`, so a service published to host loopback by
one sandbox is reachable by another.

```
consumer app -> its own gateway:5433 -> host 127.0.0.1:5433 -> provider's
published port -> provider guest:5432
```

## Provider side

Publish the service to the host. Nothing else is required: inbound policy on a
published port defaults to allow.

```sh
SANDBOX_NAME=infra
PORTS="5433:5432"
```

Ports bind to `127.0.0.1` on the host by default, which is what you want. A
loopback bind is reachable through the gateway path and is not exposed on any
routable interface. Binding `0.0.0.0` would expose the service to anything that
can route to this host; prefer the default.

Inside the provider, the service must listen on the guest's `0.0.0.0`, not the
guest's loopback, or the published-port listener has nothing to forward to.

## Consumer side

Grant one rule for the one port:

```sh
EXTRA_ARGS="--net-rule allow@host:tcp:5433"
```

Then connect to `host.microsandbox.internal` on the published host port:

```sh
psql -h host.microsandbox.internal -p 5433 -U postgres -d postgres
```

`host.microsandbox.internal` resolves per-sandbox to that sandbox's own gateway.
Do not hardcode a gateway address; it differs per sandbox and changes when a
sandbox is recreated.

The broad `--net "public,host"` profile also works, but grants every host
loopback port. The narrow rule grants exactly one and leaves the rest refused,
while preserving normal outbound access.

Note that `private` does **not** imply `host`. The host gateway is its own
policy group, evaluated before the private-address check, and it is denied by
default. A sandbox with `--net "public,private"` gets `Connection refused`.

### Containers inside the consumer

Containers reach it too, with no `extra_hosts` entry and no change to the
compose network. Docker copies the guest's `resolv.conf` into each container, so
the gateway is already the container's nameserver and it answers for
`host.microsandbox.internal`. This holds on the default bridge and on a
user-defined compose network alike.

## Network rules are fixed at creation

A running sandbox cannot be granted a new rule. Adding one means recreating the
sandbox. A recreate preserves named volumes, so the Docker data disk and every
container in it survive, but the sandbox restarts.

Plan for a restart window on the consumer whenever its network policy changes.

## Cutover: moving a consumer onto the shared service

Run the shared service alongside the existing one first, on a different host
port, and switch over once the data is in place.

1. **Migrate the data.** With both running, dump from the old instance and
   restore into the shared one. Verify row counts and extensions before
   touching any application config.

2. **Recreate the consumer with the rule.** Add `EXTRA_ARGS` as above and
   re-run the launcher. Containers return on their restart policy, still
   pointing at the old database.

3. **Confirm reachability before repointing anything.** From inside the
   consumer, run a real query against the shared instance. A version string
   back is the only acceptable evidence.

4. **Repoint the application.** Change the host and port in the consumer's
   compose environment to `host.microsandbox.internal:5433`, then
   `docker compose up -d` to recreate the affected containers.

5. **Retire the old instance.** Remove its service from the consumer's compose
   file and `docker compose up -d --remove-orphans`. Keep its volume until the
   new instance has proven itself through a full backup cycle.

6. **Optional: take the standard port.** Once nothing uses the old instance,
   the provider can be recreated with `PORTS="5432:5432"` and consumers updated
   to the conventional port. Defer this until the migration has settled; it is
   cosmetic and costs another restart on both sides.

## Verifying

Run these from inside the consumer. The negative controls are not optional —
without them a result is not evidence.

```sh
# Positive: expect a version string.
psql -h host.microsandbox.internal -p 5433 -U postgres -d postgres \
  -tAc "select version(), inet_client_addr()"

# Control: a port with nothing behind it must fail.
psql -h host.microsandbox.internal -p 5999 -U postgres -d postgres -tAc "select 1"

# Control: a wrong password must fail at authentication, proving the
# connection reached a real server rather than a local phantom accept.
PGPASSWORD=wrong psql -h host.microsandbox.internal -p 5433 -U postgres \
  -d postgres -tAc "select 1"
```

`inet_client_addr()` returns the provider's gateway address, confirming the
connection arrived through the published-port listener rather than some other
route.

## Trade-offs

Traffic crosses the host loopback, adding a proxy hop in each direction. For a
database on the same machine this is unlikely to matter, but it is not free, and
it is not the same as two processes on one bridge.

Sharing a service is a deliberate hole in sandbox isolation. The consumer can
reach that host port and nothing else, which is a much smaller grant than a
shared network — but the provider is now a shared failure domain. Size it and
supervise it accordingly.
