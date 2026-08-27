# Stack template

Standard reference for authoring a docker-compose stack in jsonnet. The `stack.jsonnet`
here is a real, compiling stack (app + dedicated Postgres, with secrets) — copy the directory,
don't start from scratch. Its output lands beside it as `compose.yaml`, so you can see
input → output. It is rebuilt on every commit, which is what stops this
template from silently rotting when the library changes under it.

## Scaffold a new stack

1. Copy this directory to `src/<area>/<stack>/` — `area` is `apps/<group>`,
   `platform/<group>`, or `tools/<group>`.
2. Rename `name::` in the `refs` table at the top of `stack.jsonnet`. It is the compose
   project name and the prefix of every derived container (`<name>_<role>`) and volume
   (`<name>_<key>`).
3. Delete the services and volumes you don't need, from both the `refs` table and the
   manifest under it.
4. Register the secret bundle (see [Secrets](#secrets)), then deploy via Komodo. Never
   `docker compose` a stack by hand.
5. Add a `[[stack]]` entry to `files/komodo_config/sync.toml` with
   `run_directory = "./src/<area>/<stack>"` and `file_paths = ["compose.yaml"]`.

Committing re-renders everything automatically (lefthook → `.vendir/libsonnet/render.py`). Never edit a
file whose first line is the `# GENERATED from …` header.

## The one file

`stack.jsonnet` is the whole stack: a `local refs` table of every name it owns, then
`{ compose: <plain Compose> }`, which renders `compose.yaml` beside it.

**An entrypoint names the files it writes.** It evaluates to an object whose top-level
fields are filenames without the extension, and each value is the document to put there —
so `{ compose: {...} }` renders `compose.yaml`. The entrypoint's own filename decides
nothing; what ties output back to source is the `# GENERATED from …` header.

That is why the manifest is wrapped in a `compose:` field rather than being the document
itself. A field holding anything but an object is a hard error, which catches the mistake
this shape invites — returning a bare Compose document, whose `name:`/`networks:`/`volumes:`
fields would otherwise be read as filenames.

A stack can name more than one (see `platform/edge/pangolin/files/configs.jsonnet`, which
applies one shared `config.libsonnet` and renders the four YAML files its keys name).

**The exception is `platform/secrets-manager/infisical`**, which still renders two documents.
Its secrets cannot come from the provider — that would mean asking the Infisical server for
them before it is up — so they arrive in an env file attached at an `include`, which is the
one place `${VAR}` inside a manifest is interpolated from. Every other stack has no
`${...}` left to resolve and needs only the one document.

## The one import

```jsonnet
local lib = import 'lib.libsonnet';
```

`render.py` passes `-J .vendir/libsonnet -J src`, so that path is the same from any depth
under `src/`.

## The refs table

```jsonnet
local lib = import 'lib.libsonnet';

local refs = lib.Project {
  name:: 'example',

  app:: self.Service { role:: lib.role.APP },
  db:: self.Service { role:: lib.role.DB },

  appData:: self.Volume { key:: 'app' },
};
```

| You write | You get |
| --- | --- |
| `name:: 'example'` | `refs.name` — the compose project name, and what the private bridge is called |
| `self.Service { role:: lib.role.APP }` | `.key` (`app` — the compose key, and what other services in the project dial) and `.ext` (`example_app` — what it is called on the host) |
| `self.Volume { key:: 'app' }` | `.key` (`app`), `.name` (`example_app`), `.declare` (the top-level `volumes:` entry) and `.mount('/data')` |

**Services are keyed by role**, taken from `lib.role` rather than typed as bare strings, so
`db` is never also `database` in some other stack. A service whose name is genuinely
app-specific (`gerbil`, `machine-learning`, `sonarr`) passes that string as the role.

**Override a derived name by writing it again.** `ext:: self.role` gives a service its
bare name, for the handful other systems already dial — see `platform/edge/pangolin`
(`gerbil`, `traefik`), `databases/postgres` (`postgres-db`).

## The manifest

One field, one file. Under `compose` it is plain Compose, everything literal except the
names that come out of `refs` and the secrets the provider injects:

```jsonnet
{
  compose: {
    name: refs.name,
    networks: { default: { name: refs.name } },
    volumes: refs.appData.declare,

    services: {
      [lib.role.SECRETS]: lib.SecretsProvider('apps', '/example'),

      [refs.app.key]: {
        container_name: refs.app.ext,
        image: 'ghcr.io/example/example:1.2.3',
        restart: lib.restart.unlessStopped,
        volumes: [refs.appData.mount('/data')],
        depends_on: lib.secretsReady + {
          [refs.db.key]: { condition: lib.condition.healthy },
        },
        environment: { DB_HOST: refs.db.key },
      },
    },
  },
}
```

The outer `compose:` names the file; the inner `services:` is Compose's own key.

A volume mounted by several services is declared once in `refs`, `.declare`d once
at the top level, and `.mount(...)`ed in each service — so the name is written in exactly one
place. Bind mounts have no name to derive and go in `volumes:` verbatim.

## Golden rule: reference by key, never by string

Anything that crosses stack boundaries lives in `src/registry.libsonnet`. Reference the
**entry**, not a string literal into it:

```jsonnet
lib.registry.endpoint.serviceGroup.postgres.host.addr   // ✓ typo fails at compile time
'littlebuddy.internal:6109'                             // ✗ typo fails silently at runtime
```

`collections` holds the constants that depend on nothing — spellings and defaults.
`registry` is the global version of a stack's `refs` table: a value goes there the moment a
*second* stack needs it. Same rule for `lib.role.*`, `lib.domain.*`, `lib.dirs.*`,
`lib.ip.loopback`, `lib.mounts.*`, `lib.registry.endpoint.hostGroup.*` and
`lib.registry.infisical.project.*`.

## Cheat-sheet

| Need | Use |
| --- | --- |
| Publish a host port | `ports: ['%s:18000:8080' % lib.ip.loopback]` |
| Reach a service on another host | `lib.registry.endpoint.serviceGroup.<x>.host.addr` |
| Wait on a healthcheck | `depends_on: { [refs.db.key]: { condition: lib.condition.healthy } }` |
| Mount the docker socket | `lib.mounts.dockerSock` (`…RW` when it must write) |
| Keep a container up through Komodo StopAll | `labels: lib.labels.komodoSkip` |
| Pull in a secret bundle | `[lib.role.SECRETS]: lib.SecretsProvider('apps', '/<folder>')` |
| Depend on that bundle | `depends_on: lib.secretsReady` |
| Public HTTPS URL of an endpoint | `lib.registry.endpoint.serviceGroup.<x>.proxy.url` |
| A restart policy | `lib.restart.unlessStopped` / `.always` / `.onFailure(5)` |

## Networks

This is a multi-node fleet, so the two directions are genuinely different mechanisms.

**Container to container, on one host** — a shared docker network. It is one entry in
`lib.registry.network.shared`, and every participating stack writes it into its top-level
`networks:` alongside the private bridge:

```jsonnet
local sharedDB = lib.registry.network.shared.postgresDB;

networks: {
  default: { name: refs.name },
  [sharedDB.name]: { name: sharedDB.name, external: true },
},
// and on each participating service:
networks: ['default', sharedDB.name],
```

`external: true` for every stack that joins one it does not own; the owning stack drops
`external` so it is the one that creates it. Compose creates an `external` network for
nobody, so attaching before the owner exists fails the deploy rather than silently building
a second empty network of the same name. Real: `platform/edge/tailscale` (owns
`shared__ts-gateway`), `apps/business/docuseal` (joins `shared__postgres_db`).

**Host to host** — the `.internal` zone, which every host's CoreDNS resolves. Publish the
port and dial `lib.registry.endpoint.serviceGroup.<x>.host.addr`, which is that service's
host `ref` and port together (`littlebuddy.internal:6109`). Which host runs a service is a
fact about that stack, so it lives on its registry entry and no consumer retypes it. Real:
`platform/backup-manager/databasus` on `rick` reaching Postgres on `littlebuddy`.

Every stack also gets one private bridge, named after the project, keyed as Compose's
reserved `default`. Write it literally: `networks: { default: { name: refs.name } }` — and
add fields to it the same way when a stack needs more, e.g. `{ default: { name: refs.name,
driver: 'bridge', enable_ipv6: true } }`. Real: `platform/edge/pangolin`.

A service using `network_mode` (host, or `service:<other>`) must declare no `networks` at
all — Compose rejects the whole project if both are present. Real: `apps/media/stream`
(plex), `platform/edge/pangolin` (traefik).

## Secrets

Secrets come from the **infisical-secrets** Compose provider. Compose runs it as a
subprocess at `up`, and every secret in the bundle is injected as a plain environment
variable — under its own Infisical name — into each service that declares `depends_on` on
the provider service.

1. Make sure the Infisical project holding the bundle is in `infisical.project` in
   `src/registry.libsonnet` — that map is just project name to id, and all five are
   already there. The bundle's *folder* does not go in the registry: exactly one stack reads
   it, so it is written in that stack.
2. Add the provider service, keyed by `lib.role.SECRETS`. The first argument is the project
   KEY (a typo fails at compile time), the second the folder inside it:

   ```jsonnet
   [lib.role.SECRETS]: lib.SecretsProvider('apps', '/<folder>'),
   ```

3. Add `lib.secretsReady` to the `depends_on` of every service that reads one. Without it
   nothing is injected. A provider has no health of its own, so `service_started` is the
   only condition it can satisfy — which is what `lib.secretsReady` is.
4. Write nothing in `environment:` for those values, and leave a comment naming them so the
   next reader knows where they come from. **Store the secret before the first `up`.**

**Store each secret under exactly the name the container reads.** There is no compose-level
interpolation left, so the provider cannot rename a value or build one out of parts:

- One password read by two services under two names (`POSTGRES_PASSWORD` on the database,
  `PAPERLESS_DBPASS` on the app) is stored **twice**, once under each name.
- A connection string is stored **whole** as `DATABASE_URL`, not assembled from a user and a
  password. Real: `apps/business/docuseal`, `tools/komodo-mcp`.

A value written literally in `environment:` that the bundle also carries is **overwritten by
the bundle's**, with a Compose warning. That is how a literal default stays overridable per
host — see `platform/dashboard/homarr`.

The bundle's name space is flat across every provider service a container depends on, so
keep keys distinct when a stack pulls from two paths. Real: `platform/edge/pangolin`, which
has a second provider service for the shared `/traefik` DNS-01 token.

A secret that has to arrive as a **file** needs a `pre_start` hook: the provider only ever
injects environment variables. Real: `platform/backup-manager/databasus`.

A stack with **no** secrets declares no provider service at all.

One stack the provider cannot serve — `platform/secrets-manager/infisical`, which would be
asking itself for its own secrets — still takes an env file at its `include`, via
`refs.envFiles`. Nothing else should.

## Variations (with real examples)

**Shared Postgres instead of a dedicated DB** — drop the `db` service and reach the shared
cluster at the level it is on. On `littlebuddy`, that is the shared network:

```jsonnet
local sharedDB = lib.registry.network.shared.postgresDB;
// on the consuming service:
networks: ['default', sharedDB.name],
depends_on: lib.secretsReady,
```

`DATABASE_URL` is not written here at all: it is stored whole in this stack's own bundle and
injected, so the shared cluster's credentials are never a second bundle this stack has to
pull. Address the cluster at `lib.registry.endpoint.serviceGroup.postgres.container.addr`
from the same host, or `.host.addr` from any other (drop the shared network then —
`littlebuddy.internal:6109` resolves through CoreDNS).

Real: `apps/business/docuseal`, `apps/business/openproject` (same host);
`platform/backup-manager/databasus` (another host).

**One image run several ways** — bind the shared body to a `local` and add to it per
service. Real: `apps/business/openproject` (web/worker/cron/seeder).

**Compose profiles** — one file, two deployment shapes. Real:
`platform/secrets-manager/infisical` (`server` and `agent`).

**Committed (non-secret) config via service-level `env_file`** — point it at a file
committed in the stack dir. Real: `platform/container-manager/komodo` (`./core.env`).

**Device passthrough / NFS bind mounts** — `devices: ['/dev/dri:/dev/dri']`, literal host
paths for large media. Real: `apps/media/immich`.

**An entrypoint that isn't a stack** — any `.jsonnet` under `src/` renders to the `.yaml`
beside it. Real: `platform/edge/pangolin/files/` (four config files from one shared
`config.libsonnet`).
