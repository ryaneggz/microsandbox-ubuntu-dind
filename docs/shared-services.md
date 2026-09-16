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

## Worked example: `dev`, `prod`, and `infra`

Three sandboxes on one host. `infra` runs Postgres and Redis. `dev` and `prod`
each run an application that uses both, sharing one copy of each service
instead of running their own.

```
                     host 127.0.0.1
  dev sandbox   ─┐    :5432 ─┐
                 ├──────────  ├─► infra sandbox: postgres, redis
  prod sandbox  ─┘    :6379 ─┘
```

Only `infra` publishes ports. `dev` and `prod` publish nothing for this to
work; they are granted egress rules instead.

### Host port allocation

All sandboxes share one host port namespace, so decide it once.

| Host port | Service | Published by |
| --- | --- | --- |
| `5432` | Postgres | `infra` |
| `6379` | Redis | `infra` |

If `dev` and `prod` also publish their own application ports, those must not
collide with each other or with the table above.

### `infra` — the provider

```sh
SANDBOX_NAME=infra
CPUS=2
MAX_CPUS=4
MEMORY=2G
MAX_MEMORY=4G
DOCKER_DATA_VOLUME=infra-docker-data
DOCKER_DATA_SIZE=30G
MOUNT_DIRS="/opt/infra-services:/home/dev/infra-services"
PORTS="5432:5432 6379:6379"
```

No `EXTRA_ARGS`. A provider needs no rules: inbound policy on a published port
defaults to allow, and `infra` never initiates connections to the others.

`/opt/infra-services/compose.yml`:

```yaml
services:
  postgres:
    image: pgvector/pgvector:pg17-trixie
    container_name: infra-postgres
    restart: always
    environment:
      POSTGRES_USER: ${POSTGRES_USER:?}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?}
      POSTGRES_DB: ${POSTGRES_DB:-postgres}
    ports:
      - "0.0.0.0:5432:5432"
    volumes:
      - postgres-data:/var/lib/postgresql/data
    shm_size: 256mb
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:?}"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 30s

  redis:
    image: redis:8-trixie
    container_name: infra-redis
    restart: always
    command: ["redis-server", "--appendonly", "yes", "--requirepass", "${REDIS_PASSWORD:?}"]
    ports:
      - "0.0.0.0:6379:6379"
    volumes:
      - redis-data:/data
    healthcheck:
      test: ["CMD-SHELL", "redis-cli -a \"$$REDIS_PASSWORD\" ping | grep -q PONG"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 10s

volumes:
  postgres-data:
  redis-data:
```

Both services bind the guest's `0.0.0.0`, not the guest's loopback, or the
published-port listener has nothing to forward to. The host side of each
publish still binds `127.0.0.1` by default, which is what limits exposure.

Bring it up inside the sandbox:

```sh
msb exec infra -- bash -lc 'cd /home/dev/infra-services && docker compose up -d'
```

### `dev` and `prod` — the consumers

Identical except for name and what they connect to:

```sh
SANDBOX_NAME=dev
MOUNT_DIRS="/opt/dev-app:/home/dev/app"
EXTRA_ARGS="--net-rule allow@host:tcp:5432,allow@host:tcp:6379"
```

```sh
SANDBOX_NAME=prod
MOUNT_DIRS="/opt/prod-app:/home/dev/app"
EXTRA_ARGS="--net-rule allow@host:tcp:5432,allow@host:tcp:6379"
```

One `--net-rule` carries a comma-separated list, so two services need one flag.
Each entry grants exactly one host port; every other host port stays refused.

The application compose file in each environment points at
`host.microsandbox.internal`:

```yaml
services:
  app:
    image: your/app:latest
    restart: always
    environment:
      DATABASE_URL: postgres://${DB_USER}:${DB_PASSWORD}@host.microsandbox.internal:5432/${DB_NAME}
      REDIS_URL: redis://:${REDIS_PASSWORD}@host.microsandbox.internal:6379/${REDIS_DB}
```

No `extra_hosts` and no gateway address. The container resolves the name
through the guest resolver Docker copies into it.

### Keeping environments apart

One shared service does not mean one shared dataset. Separate them inside the
service, where the isolation is enforced rather than assumed:

```sh
# In infra's postgres, once.
createdb -U postgres appdb_dev  && createuser -U postgres app_dev
createdb -U postgres appdb_prod && createuser -U postgres app_prod
psql -U postgres -c "grant all on database appdb_dev  to app_dev"
psql -U postgres -c "grant all on database appdb_prod to app_prod"
```

| Environment | `DB_NAME` | `DB_USER` | `REDIS_DB` |
| --- | --- | --- | --- |
| `dev` | `appdb_dev` | `app_dev` | `0` |
| `prod` | `appdb_prod` | `app_prod` | `1` |

Distinct Postgres roles mean a mistake in `dev` cannot reach `prod` data.
Redis numbered databases are a weaker boundary — they share one instance,
one password, and `FLUSHALL` crosses them — so use separate Redis ACL users,
or a second Redis on another port, if that matters.

### What each sandbox can reach

| | Postgres `5432` | Redis `6379` | Other host ports | The other sandboxes |
| --- | --- | --- | --- | --- |
| `infra` | serves it | serves it | denied | no |
| `dev` | allowed | allowed | denied | no |
| `prod` | allowed | allowed | denied | no |

No sandbox can reach another directly. `dev` cannot reach `prod`, and neither
can reach anything on the host beyond those two ports.

### Verifying the example

From inside `dev`, with negative controls:

```sh
# Postgres: expect a version string.
psql -h host.microsandbox.internal -p 5432 -U app_dev -d appdb_dev \
  -tAc "select version(), inet_client_addr()"

# Redis: expect PONG.
redis-cli -h host.microsandbox.internal -p 6379 -a "$REDIS_PASSWORD" ping

# Control: a host port that was not granted must be refused.
curl -s -m 5 http://host.microsandbox.internal:5433/ ; echo "exit=$?"

# Control: a wrong password must fail at authentication, proving the
# connection reached a real server rather than a local phantom accept.
PGPASSWORD=wrong psql -h host.microsandbox.internal -p 5432 -U app_dev \
  -d appdb_dev -tAc "select 1"
```

`inet_client_addr()` returns `infra`'s gateway address, confirming the
connection arrived through its published-port listener rather than some other
route. A denied port exits `7` (connection refused), while a granted port
reaching a non-HTTP service exits `28` (timeout) — different observable
outcomes. Confirm both; a positive result alone does not distinguish a working
rule from a permissive one.

## Reference

### Provider

Publish the service to the host with `PORTS="<HOST_PORT>:<GUEST_PORT>"`. Nothing
else is required: inbound policy on a published port defaults to allow, and a
provider needs no `EXTRA_ARGS`.

Ports bind to `127.0.0.1` on the host by default, which is what you want. A
loopback bind is reachable through the gateway path and is not exposed on any
routable interface. Binding `0.0.0.0` would expose the service to anything that
can route to this host; prefer the default.

Inside the provider, the service must listen on the guest's `0.0.0.0`, not the
guest's loopback, or the published-port listener has nothing to forward to.

### Consumer

Grant one rule per host port, comma-separated in a single flag:

```sh
EXTRA_ARGS="--net-rule allow@host:tcp:<HOST_PORT>"
```

Connect to `host.microsandbox.internal` on that host port. The name resolves
per-sandbox to that sandbox's own gateway. Do not hardcode a gateway address; it
differs per sandbox and changes when a sandbox is recreated.

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

### Network rules are fixed at creation

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
   compose environment to `host.microsandbox.internal:<HOST_PORT>`, then
   `docker compose up -d` to recreate the affected containers.

5. **Retire the old instance.** Remove its service from the consumer's compose
   file and `docker compose up -d --remove-orphans`. Keep its volume until the
   new instance has proven itself through a full backup cycle.

6. **Optional: take the standard port.** Once nothing uses the old instance,
   the provider can be recreated with `PORTS="5432:5432"` and consumers updated
   to the conventional port. Defer this until the migration has settled; it is
   cosmetic and costs another restart on both sides.

## Trade-offs

Traffic crosses the host loopback, adding a proxy hop in each direction. For a
database on the same machine this is unlikely to matter, but it is not free, and
it is not the same as two processes on one bridge.

Sharing a service is a deliberate hole in sandbox isolation. The consumer can
reach that host port and nothing else, which is a much smaller grant than a
shared network — but the provider is now a shared failure domain. Size it and
supervise it accordingly.
