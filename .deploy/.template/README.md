# Stack template

Standard reference for authoring a docker-compose stack in jsonnet. `compose.jsonnet`
here is a real, compiling stack (app + dedicated Postgres, with secrets) — copy it,
don't start from scratch. Its generated output lands at
`.deploy/.template/{compose.yaml,compose.stack.yaml}`, so you can see
input → output. It is rebuilt on every commit, which is also what stops this template
from silently rotting when a lib changes under it.

## Scaffold a new stack

1. Copy `compose.jsonnet` to `src/<area>/<stack>/compose.jsonnet` — `area` is `apps/<group>`,
   `platform/<group>`, or `tools/<group>`.
2. Rename the `stack` local. It is the compose project name and the prefix of every
   `n.container(role)` / `n.volume(role)`.
3. Delete services you don't need; uncomment the variations you do (redis block is inline;
   others below).
4. Register secrets (see [Secrets](#secrets)), then deploy via Komodo. Never `docker
   compose` a stack by hand.
5. Add a `[[stack]]` entry to `komodo/komodo-config-sync.toml` with
   `run_directory = "./.deploy/<area>/<stack>"` — note the `.deploy/` prefix and that
   there is no `src/` in it: `.deploy` mirrors the *contents* of `src/`.

Committing rebuilds `.deploy/` automatically (lefthook → `render.py`). Never edit anything
under `.deploy/` — the whole tree is wiped and rebuilt on the next commit.

## The two files, and the render contract

Every `compose.jsonnet` ends in `c.render(stack, manifest, envFiles)`, which emits:

| File | Role |
| --- | --- |
| `compose.yaml` | project name + `include:` of the manifest (+ `env_file:` for secrets). What Docker loads. |
| `compose.stack.yaml` | the `services` / `networks` / `volumes` manifest. |

Both land in the entrypoint's **mirrored** directory under `.deploy/`, next to copies of
that stack's hand-written assets. Relative paths are preserved exactly, so
`./files/entrypoint.sh` and `./templates` bind mounts work unchanged — write them in
jsonnet as if source and output shared a directory.

## Golden rule: reference by key, never by string

Anything that crosses stack boundaries lives in `registry.libsonnet`. Reference the
**entry**, not a string literal into it:

```jsonnet
reg.endpoints.postgres.host   // ✓ typo fails at compile time
'host.docker.internal'        // ✗ typo fails silently at runtime
```

Same for `reg.roles.{app,db,redis}`, `reg.domains.*`, `reg.endpoints.*`, `secrets.<x>.path`.

## Helper cheat-sheet (`.jsonnet/lib/compose.libsonnet`)

| Need | Use |
| --- | --- |
| Stack-scoped names | `local s = c.stack(name); local n = s.names` → `n.container(role)`, `n.volume(role)` |
| Private net for this stack | `s.network.default` |
| Attach a service to a net under an alias | `s.network.attach(netName, alias)` |
| Publish a host port (binds `127.0.0.1`) | `+ c.publish(hostPort, containerPort)` |
| Keep a container up through Komodo StopAll | `+ s.komodoSkip` (merge into `labels`) |
| Public HTTPS URL of a registry endpoint | `c.url(reg.endpoints.<x>).public` |
| Container URL of a registry endpoint | `c.url(reg.endpoints.<x>).container` |

## Networks

`s.network.default` is this stack's private bridge (its services reach each other by
container name). There are **no shared Docker networks** — services that need to talk
across stacks do it over published host ports, not a common network.

To reach another stack's service, publish it with `c.publish(hostPort, containerPort)`
and dial it from the consumer at `host.docker.internal:<hostPort>`, adding
`extra_hosts: ['host.docker.internal:host-gateway']` to the consuming service. The shared
Postgres cluster is single-sourced this way at `reg.endpoints.postgres.host`
(`host.docker.internal:6109`) — see `apps/business/n8n` for the pattern.

## Secrets

Producer/consumer must agree on the env-file path, so single-source it:

1. Add an entry to `infisical.catalogue` in `registry.libsonnet` (`dump` for a whole
   folder, `map` for renames, `raw` for a single value).
2. In the stack, `local secrets = reg.infisical.services;` and pass
   `secrets.<stack>.path` to `c.render`.
3. Reference each secret in `environment:` as `${VAR:?err}` — the `:?err` aborts the
   deploy if the value is missing. **Set the secret before the first `up`.**

A stack with **no** secrets omits the third `c.render` arg entirely.

Gotcha: some images don't interpolate env-file values into certain fields. When that
happens, put the literal `${VAR:?err}` directly in `environment:` (see
`apps/media/immich`).

## Variations (with real examples)

**Shared Postgres instead of a dedicated DB** — delete the `db` service; dial the shared
cluster over the host gateway, building the DSN from the registry endpoint:

```jsonnet
local pgHost = reg.endpoints.postgres.host.host;  // 'host.docker.internal'
local pgPort = reg.endpoints.postgres.host.port;  // 6109
// in environment:
DATABASE_URL: 'postgres://${POSTGRES_USER:?err}:${POSTGRES_PASS:?err}@'
              + pgHost + ':' + std.toString(pgPort) + '/' + dbName,
// on the consuming service, so it can resolve the docker host:
extra_hosts: ['host.docker.internal:host-gateway'],
// and pass the shared creds too:
c.render(stack, manifest, [secrets.<stack>.path, secrets.postgres.path])
```
Real: `apps/business/templates/twenty`, `apps/business/n8n`, `apps/business/docuseal`,
`apps/business/openproject`.

**A second published port** (e.g. SSH) — merge extra ports into the service with
`+ { ports+: c.publish(hostPort, containerPort).ports }`. Real:
`tools/devops/forgejo` (`compose.jsonnet:50`).

**Keep infra containers up when Komodo stops everything** — `+ s.komodoSkip` on the
service's `labels`. Real: `platform/container-manager/komodo`, `…/komodo-periphery`,
`tools/komodo-mcp`.

**Committed (non-secret) config via service-level `env_file`** — set `env_file:` on the
service, pointing at a file committed in the stack dir. Real:
`platform/container-manager/komodo-periphery` (`./periphery.env`).

**One stack, multiple parent/child pairs** (per-variant instances) — build the
`include:` list by hand instead of a single `c.render`. Real: `platform/edge/newt`.

**Device passthrough / NFS bind mounts** — `devices: ['/dev/dri:/dev/dri']`, literal host
paths for large media. Real: `apps/media/immich`.

## Notes on unused helpers

`c.toEnv(obj)` (renders an object to `KEY=value` lines) is defined in the lib but has no
current callers — kept for stacks that need to emit an env file from jsonnet.
