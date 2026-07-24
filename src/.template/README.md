# Stack template

Standard reference for authoring a docker-compose stack in jsonnet. `compose.jsonnet`
here is a real, compiling stack (app + dedicated Postgres, with secrets) — copy it,
don't start from scratch. Its generated output lands at
`.deploy/.template/{compose.yaml,compose.stack.yaml}`, so you can see
input → output. It is rebuilt on every commit, which is also what stops this template
from silently rotting when the library changes under it.

## Scaffold a new stack

1. Copy `compose.jsonnet` to `src/<area>/<stack>/compose.jsonnet` — `area` is `apps/<group>`,
   `platform/<group>`, or `tools/<group>`.
2. Rename the `name` local. It is the compose project name and the prefix of every derived
   container (`<name>_<role>`) and volume (`<name>_<key>`).
3. Delete services you don't need; uncomment the variations you do.
4. Register secrets (see [Secrets](#secrets)), then deploy via Komodo. Never `docker
   compose` a stack by hand.
5. Add a `[[stack]]` entry to `komodo-config-sync.toml` with
   `run_directory = "./.deploy/<area>/<stack>"` — note the `.deploy/` prefix and that
   there is no `src/` in it: `.deploy` mirrors the *contents* of `src/`.

Committing rebuilds `.deploy/` automatically (lefthook → `render.py`). Never edit anything
under `.deploy/` — the whole tree is wiped and rebuilt on the next commit.

## The one import

```jsonnet
local lib = import 'lib/lib.libsonnet';
local reg = lib.registry;
local role = reg.role;
```

`render.py` passes the repo root as the jsonnet jpath, so that path is the same from any
depth under `src/`. `lib/lib.libsonnet` is the only entrypoint — `compose.libsonnet` and
`registry.libsonnet` are reached through it.

## The two files, and the render contract

Every `compose.jsonnet` ends in `lib.render(projectName, stack, envFiles)`, which emits:

| File | Role |
| --- | --- |
| `compose.yaml` | project name + `include:` of the manifest (+ `env_file:` for secrets). What Docker loads. |
| `compose.stack.yaml` | the `services` / `networks` / `volumes` manifest. |

Both land in the entrypoint's **mirrored** directory under `.deploy/`, next to copies of
that stack's hand-written assets. Relative paths are preserved exactly, so
`./files/entrypoint.sh` and `./templates` bind mounts work unchanged — write them in
jsonnet as if source and output shared a directory.

## Service and Stack

```jsonnet
lib.render(
  name,
  lib.Stack(name, function(ref) {
    [role.APP]: lib.Service {
      image: 'ghcr.io/example/example:1.2.3',
      volumes_:: { app: '/data' },
      depends_on: { [role.DB]: { condition: 'service_healthy' } },
      environment: { DB_HOST: ref[role.DB] },
    },
  }),
  [lib.Secret('example')],
)
```

`lib.Service` derives the things a stack should never hand-write:

| Field | Derived as | Override by |
| --- | --- | --- |
| `container_name` | `<name>_<role>` | writing the field again |
| `restart` | `unless-stopped` | writing the field again |
| `networks` | `{default: {aliases: [container_name]}}`, plus anything in `networks_` | writing the field again |

Those are plain fields, so an override is just re-declaring one. That is the escape hatch
for names other systems already dial — `postgres-db`, `komodo_core`, pangolin's unprefixed
`gerbil`/`traefik`.

**Services are keyed by role**, taken from `reg.role` rather than typed as bare strings,
so `db` is never also `database` in some other stack. A service whose name is genuinely
app-specific (`guacd`, `gerbil`, `machine-learning`) uses a plain `local` string instead.

**`ref` is the stack's own service table.** `ref[role.DB]` is the name the db service will
actually carry — both its compose key's container and its DNS name on the stack network.
Asking for a role the stack does not declare fails at evaluation, at the point of the
mistake, rather than in a container that never starts.

## Volumes

| Input | Renders |
| --- | --- |
| `volumes_:: { app: '/data' }` | mount `app:/data`, plus top-level `app: {name: <stack>_app}` |
| `mounts_:: ['/srv/x:/y', './files/z:/w:ro']` | those strings, verbatim |

The key is the compose-local handle; `<stack>_<key>` is the real volume on the host. A
volume mounted by several services is declared in each service's `volumes_` and deduped
into one top-level entry — declared where it is used, never restated. Bind mounts have no
name to derive, so they go in `mounts_` untouched. Named volumes render before bind mounts.

## Golden rule: reference by key, never by string

Anything that crosses stack boundaries lives in `registry.libsonnet`. Reference the
**entry**, not a string literal into it:

```jsonnet
reg.endpoint.postgres.host.host   // ✓ typo fails at compile time
'host.docker.internal'            // ✗ typo fails silently at runtime
```

Same for `reg.role.*`, `reg.domains.*`, `reg.endpoint.*`, `reg.dirs.docker.*`,
`reg.ips.loopback`, `reg.hosts`, and `lib.Secret('<catalogue-key>')`.

## Helper cheat-sheet (`lib/lib.libsonnet`)

| Need | Use |
| --- | --- |
| A service | `lib.Service { … }` |
| The manifest | `lib.Stack(name, function(ref) { … })` |
| Put a service on another network | `networks_:: lib.network.attach(reg.networks.shared.<x>)` |
| Own that shared network from one stack | `networks_:: lib.network.create(reg.networks.shared.<x>)` |
| A different private bridge | `lib.Stack(name, fn, networks)` — third arg replaces `default` |
| Publish a host port | `ports: ['%s:18000:8080' % reg.ips.loopback]` |
| Keep a container up through Komodo StopAll | `labels: lib.komodoSkip` |
| Env-file path for a catalogue entry | `lib.Secret('<key>')` |
| …same, overridable during bootstrap | `lib.SecretOrBootstrap('<key>')` |
| Public HTTPS URL of an endpoint | `reg.endpoint.<x>.public.url` |
| Render an object to `KEY=value` lines | `lib.toEnv(obj)` — see `platform/edge/newt/envs/env.jsonnet` |

## Networks

Every stack gets one private bridge, named after the stack, keyed as Compose's reserved
`default`. **Cross-stack traffic goes over published host ports by default** — publish it,
then dial it from the consumer at `host.docker.internal:<hostPort>` with
`extra_hosts: ['host.docker.internal:host-gateway']` on the consuming service. The shared
Postgres cluster is single-sourced this way at `reg.endpoint.postgres.host`
(`host.docker.internal:6109`) — see `apps/business/n8n`.

A service that must be on another network as well declares it in `networks_`, keyed by the
network's real name and valued as its top-level definition. `lib.Stack` hoists those
definitions, exactly as it does `volumes_`:

| Input | Renders |
| --- | --- |
| `networks_:: lib.network.create(reg.networks.shared.postgresDB)` | membership, plus top-level `{name: shared__postgres_db}` |
| `networks_:: lib.network.attach(reg.networks.shared.postgresDB)` | membership, plus top-level `{name: …, external: true}` |

The split is ownership: exactly one stack `create`s a shared network and every other
`attach`es to it. Compose creates an `external` network for nobody, so attaching before the
owner exists fails the deploy rather than silently building a second empty network of the
same name. Two services joining the same network collapse to one top-level entry, and both
get `container_name` as an alias on every network they join. `networks_` is incompatible
with `network_mode` (no netns of its own) and says so at render time.

Changing the private bridge itself is the third argument to `lib.Stack` — it is merged last
over the top-level block, so naming `default` redefines it and hoisted networks are left
alone. `default` is always emitted; the argument can only change it, never remove it. Real:
`platform/edge/pangolin` (ipv6 on the default); `reg.networks.hostGateway.create(name)`
builds a fixed-IPAM block for it.

## Secrets

Producer and consumer must agree on the env-file path, so single-source it:

1. Add an entry to `infisical.catalog` in `registry.libsonnet` (`dump` for a whole
   folder, `map` for renames, `raw` for a single value).
2. In the stack, pass `lib.Secret('<key>')` to `lib.render`. That looks the entry's `dest`
   up in the catalogue, so the agent fragment and this stack derive the same path and a
   typo'd key fails at compile time. `dest` is not always `<key>.env` (komodo renders
   `komodo_core.env`) and not always an env file (databasus renders a raw key file), which
   is why it is looked up rather than spelled out.
3. Reference each secret in `environment:` as `${VAR:?err}` — the `:?err` aborts the
   deploy if the value is missing. **Set the secret before the first `up`.**

`lib.SecretOrBootstrap('<key>')` is the same path wrapped in
`${ANSIBLE_SECRETS_FILE:-…}`, for stacks the control plane brings up before the agent
exists to render anything. Real: `komodo`, `infisical`, `cloudflared`, `zerobyte`.

A stack with **no** secrets omits the third `lib.render` arg entirely.

Gotcha: some images don't interpolate env-file values into certain fields. When that
happens, put the literal `${VAR:?err}` directly in `environment:` (see
`apps/media/immich`).

## Variations (with real examples)

**Shared Postgres instead of a dedicated DB** — delete the `db` service; dial the shared
cluster over the host gateway, building the DSN from the registry endpoint:

```jsonnet
local pg = reg.endpoint.postgres.host;   // .host = 'host.docker.internal', .port = '6109'
// in environment:
DATABASE_URL: 'postgres://${POSTGRES_USER:?err}:${POSTGRES_PASS:?err}@%s:%s/%s'
              % [pg.host, pg.port, dbName],
// on the consuming service, so it can resolve the docker host:
extra_hosts: ['host.docker.internal:host-gateway'],
// and pass the shared creds too:
lib.render(name, stack, [lib.Secret('<stack>'), lib.Secret('postgres')])
```
Real: `apps/business/n8n`, `apps/business/docuseal`, `apps/business/openproject`.

**A second published port** (e.g. SSH) — just add another entry to `ports`. Real:
`tools/devops/forgejo`.

**Overriding a derived name** — write the field again, with a comment saying who dials it.
Real: `databases/postgres` (`container_name: 'postgres-db'`),
`platform/container-manager/komodo` (alias `komodo_core`).

**Project name ≠ stack name** — `lib.Stack` names the resources, `lib.render` names the
compose project; pass different strings when a stack's resources belong beside another's.
Real: `platform/container-manager/komodo-periphery` and
`platform/secrets-manager/infisical-agent` (both render under their own directory while
naming resources `komodo_*` / `infisical_*`).

**Keep infra containers up when Komodo stops everything** — `labels: lib.komodoSkip`. Real:
`platform/container-manager/komodo`, `…/komodo-periphery`, `tools/komodo-mcp`.

**Committed (non-secret) config via service-level `env_file`** — set `env_file:` on the
service, pointing at a file committed in the stack dir. Real:
`platform/container-manager/komodo-periphery` (`./periphery.env`), `platform/edge/newt`.

**Device passthrough / NFS bind mounts** — `devices: ['/dev/dri:/dev/dri']`, literal host
paths for large media. Real: `apps/media/immich`.

**An entrypoint that isn't a compose stack** — any `.jsonnet` under `src/` renders into its
own mirrored directory. Real: `platform/edge/dnsmasq/files/hosts.jsonnet` (a hosts file
from `reg.hosts`), `platform/secrets-manager/infisical-agent/templates/services.jsonnet`
(one agent fragment per catalogue entry).
