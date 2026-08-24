# Stack template

Standard reference for authoring a docker-compose stack in jsonnet. The two files here
are a real, compiling stack (app + dedicated Postgres, with secrets) — copy the directory,
don't start from scratch. Its output lands beside it as `compose.yaml` and `services.yaml`,
so you can see input → output. It is rebuilt on every commit, which is what stops this
template from silently rotting when `devlib/` changes under it.

## Scaffold a new stack

1. Copy this directory to `src/<area>/<stack>/` — `area` is `apps/<group>`,
   `platform/<group>`, or `tools/<group>`.
2. Rename `name::` in `refs.libsonnet`. It is the compose project name and the prefix of
   every derived container (`<name>_<role>`) and volume (`<name>_<key>`).
3. Delete the services and volumes you don't need, in `refs.libsonnet` and
   `stack.jsonnet` both.
4. Register secrets (see [Secrets](#secrets)), then deploy via Komodo. Never `docker
   compose` a stack by hand.
5. Add a `[[stack]]` entry to `files/komodo_config/sync.toml` with
   `run_directory = "./src/<area>/<stack>"` and `file_paths = ["compose.yaml"]`.

Committing re-renders everything automatically (lefthook → `devlib/render.py`). Never edit a
file whose first line is the `# GENERATED from …` header.

## The two files

| File | Role |
| --- | --- |
| `refs.libsonnet` | Every name this stack owns. Imported by the entrypoint. |
| `stack.jsonnet` | `{ compose: refs.compose, services: <plain Compose> }`. Renders `compose.yaml` and `services.yaml`. |

**An entrypoint names the files it writes.** It evaluates to an object whose top-level
fields are filenames without the extension, and each value is the document to put there —
so `{ compose: {...}, services: {...} }` renders both YAML files beside it. The entrypoint's
own filename decides nothing; what ties output back to source is the `# GENERATED from …`
header.

That is why the manifest is wrapped in a `services:` field rather than being the document
itself. A field holding anything but an object is a hard error, which catches the mistake
this shape invites — returning a bare Compose document, whose `name:`/`networks:`/`volumes:`
fields would otherwise be read as filenames.

A stack can name more than two (see `platform/edge/pangolin/files/configs.jsonnet`, which
applies one shared `config.libsonnet` and renders the four YAML files its keys name).

`compose` stays a **separate document** from `services` because `env_file` has to attach at
the `include`, not at the service: `${VAR:?err}` inside `services.yaml` is interpolated from
the include's env file, whereas a service-level `env_file:` only reaches the container's
environment and would leave every `${...}` in the manifest unresolved.

## The one import

```jsonnet
local lib = import 'lib.libsonnet';
```

`render.py` passes `-J devlib`, so that path is the same from any depth under `src/`.
`refs.libsonnet` sits next to the entrypoint, so `import 'refs.libsonnet'` just works.

## refs.libsonnet

```jsonnet
local lib = import 'lib.libsonnet';

lib.Project {
  name:: 'example',
  envFiles:: [lib.Secret('example')],

  app:: self.Service { role:: lib.role.APP },
  db:: self.Service { role:: lib.role.DB },

  appData:: self.Volume { key:: 'app' },
}
```

| You write | You get |
| --- | --- |
| `name:: 'example'` | `refs.name` — the compose project name, and what the private bridge is called |
| `self.Service { role:: lib.role.APP }` | `.key` (`app` — the compose key, and what other services in the project dial) and `.ext` (`example_app` — what it is called on the host) |
| `self.Volume { key:: 'app' }` | `.key` (`app`), `.name` (`example_app`), `.declare` (the top-level `volumes:` entry) and `.mount('/data')` |
| `envFiles:: [...]` | `refs.compose`, the whole `compose.yaml` document |

**Services are keyed by role**, taken from `lib.role` rather than typed as bare strings, so
`db` is never also `database` in some other stack. A service whose name is genuinely
app-specific (`gerbil`, `machine-learning`, `sonarr`) passes that string as the role.

**Override a derived name by writing it again.** `ext:: self.role` gives a service its
bare name, for the handful other systems already dial — see `platform/edge/pangolin`
(`gerbil`, `traefik`), `databases/postgres` (`postgres-db`).

## stack.jsonnet

Two fields, two files. `compose` is `refs.compose` and nothing else; under `services` it is
plain Compose, everything literal except the names that come out of `refs`:

```jsonnet
local lib = import 'lib.libsonnet';
local refs = import 'refs.libsonnet';

{
  compose: refs.compose,

  services: {
    name: refs.name,
    networks: { default: { name: refs.name } },
    volumes: refs.appData.declare,

    services: {
      [refs.app.key]: {
        container_name: refs.app.ext,
        image: 'ghcr.io/example/example:1.2.3',
        restart: lib.restart.unlessStopped,
        volumes: [refs.appData.mount('/data')],
        depends_on: { [refs.db.key]: { condition: lib.condition.healthy } },
        environment: { DB_HOST: refs.db.key },
      },
    },
  },
}
```

The outer `services:` names the file; the inner one is Compose's own key.

A volume mounted by several services is declared once in `refs.libsonnet`, `.declare`d once
at the top level, and `.mount(...)`ed in each service — so the name is written in exactly one
place. Bind mounts have no name to derive and go in `volumes:` verbatim.

## Golden rule: reference by key, never by string

Anything that crosses stack boundaries lives in `devlib/registry.libsonnet`. Reference the
**entry**, not a string literal into it:

```jsonnet
lib.registry.endpoint.serviceGroup.postgres.host.addr   // ✓ typo fails at compile time
'littlebuddy.internal:6109'                             // ✗ typo fails silently at runtime
```

`collections` holds the constants that depend on nothing — spellings and defaults.
`registry` is the global version of a `refs.libsonnet`: a value goes there the moment a
*second* stack needs it. Same rule for `lib.role.*`, `lib.domain.*`, `lib.dirs.*`,
`lib.ip.loopback`, `lib.mounts.*`, `lib.registry.endpoint.hostGroup.*` and
`lib.Secret('<key>')`.

## Cheat-sheet

| Need | Use |
| --- | --- |
| Publish a host port | `ports: ['%s:18000:8080' % lib.ip.loopback]` |
| Reach a service on another host | `lib.registry.endpoint.serviceGroup.<x>.host.addr` |
| Wait on a healthcheck | `depends_on: { [refs.db.key]: { condition: lib.condition.healthy } }` |
| Mount the docker socket | `lib.mounts.dockerSock` (`…RW` when it must write) |
| Keep a container up through Komodo StopAll | `labels: lib.labels.komodoSkip` |
| Env-file path for a secret bundle | `lib.Secret('<key>')` |
| …same, overridable during bootstrap | `lib.SecretOrBootstrap('<key>')` |
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

Producer and consumer must agree on the env-file path, so single-source it:

1. Add the bundle to the right Infisical project's `secretsMap` in
   `devlib/registry.libsonnet`. `service` is the folder in Infisical and the default
   filename; override `projectPath`, `outFile`, `type` or `key` only where they differ.
   Every project's map is flattened into `infisical.catalog`, which is what `lib.Secret`
   looks in — so a key can only be spelled one way across the repo.
2. Write the agent fragment at
   `src/platform/secrets-manager/infisical/templates/services.<key>.yaml` — these are
   hand-written; see `templates.md` beside them for the Go-template forms.
3. Put `lib.Secret('<key>')` in the stack's `envFiles::`. A typo'd key fails at compile time.
4. Reference each secret in `environment:` as `${VAR:?err}` — the `:?err` aborts the deploy
   if the value is missing. **Set the secret before the first `up`.**

`lib.SecretOrBootstrap('<key>')` is the same path wrapped in `${ANSIBLE_SECRETS_FILE:-…}`,
for stacks the control plane brings up before the agent exists. Real: `komodo`, `infisical`,
`cloudflared`, `zerobyte`.

A stack with **no** secrets omits `envFiles::` entirely.

Gotcha: some images don't interpolate env-file values into certain fields. When that
happens the literal `${VAR:?err}` goes directly in `environment:` — see `apps/media/immich`.

## Variations (with real examples)

**Shared Postgres instead of a dedicated DB** — drop the `db` service and reach the shared
cluster at the level it is on. On `littlebuddy`, that is the shared network:

```jsonnet
local pg = lib.registry.endpoint.serviceGroup.postgres;
local sharedDB = lib.registry.network.shared.postgresDB;
// in environment:
DATABASE_URL: 'postgresql://${POSTGRES_USER:?err}:${POSTGRES_PASS:?err}@%s/mydb' % pg.container.addr,
// on the consuming service:
networks: ['default', sharedDB.name],
// and pass the shared creds too, in refs.libsonnet:
envFiles:: [lib.Secret('<stack>'), lib.Secret('postgres')],
```

From any other host, swap `pg.container.addr` for `pg.host.addr` and drop the shared
network — `littlebuddy.internal:6109` resolves through CoreDNS.

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
