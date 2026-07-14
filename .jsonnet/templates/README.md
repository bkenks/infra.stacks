# Stack template

Standard reference for authoring a docker-compose stack in jsonnet. `compose.jsonnet`
here is a real, compiling stack (app + dedicated Postgres, behind Traefik, with
secrets) — copy it, don't start from scratch. `compose.yaml` / `compose.stack.yaml`
next to it are its generated output, kept so you can see input → output.

## Scaffold a new stack

1. Copy `compose.jsonnet` to `<area>/<stack>/compose.jsonnet` — `area` is `apps/<group>`,
   `platform/<group>`, or `tools/<group>`.
2. Rename the `stack` local. It is the compose project name and the prefix of every
   `n.container(role)` / `n.volume(role)`.
3. Delete services you don't need; uncomment the variations you do (redis block is inline;
   others below).
4. Register secrets (see [Secrets](#secrets)), then deploy via Komodo. Never `docker
   compose` a stack by hand.

Committing re-renders the YAML automatically (lefthook → `render.py`). Never edit the
generated YAML — it carries a `# GENERATED …` header and is overwritten.

## The two files, and the render contract

Every `compose.jsonnet` ends in `c.render(stack, manifest, envFiles)`, which emits:

| File | Role |
| --- | --- |
| `compose.yaml` | project name + `include:` of the manifest (+ `env_file:` for secrets). What Docker loads. |
| `compose.stack.yaml` | the `services` / `networks` / `volumes` manifest. |

`render.py` writes only into the entrypoint's own directory and sweeps stale YAML it
previously owned, so one `compose.jsonnet` stands next to exactly its own output.

## Golden rule: reference by key, never by string

Anything that crosses stack boundaries lives in `registry.libsonnet`. Reference the
**entry**, not a string literal into it:

```jsonnet
reg.sharedNetworks.proxy      // ✓ typo fails at compile time
'shared-proxy'                // ✗ typo fails silently at runtime
```

Same for `reg.roles.{app,db,redis}`, `reg.domains.*`, `reg.endpoints.*`, `secrets.<x>.path`.

## Helper cheat-sheet (`.jsonnet/lib/compose.libsonnet`)

| Need | Use |
| --- | --- |
| Stack-scoped names | `local s = c.stack(name); local n = s.names` → `n.container(role)`, `n.volume(role)` |
| Traefik HTTP router | `s.proxy.add(router, sub, port, zone=ktbinternal)` |
| Private net for this stack | `s.network.default` |
| Join a shared net (someone else owns) | `s.network.join(reg.sharedNetworks.<x>)` |
| Own a shared net (this stack is the owner) | `s.network.own(reg.sharedNetworks.<x>)` |
| Attach a service to a net under an alias | `s.network.attach(netName, alias)` |
| Publish a host port (binds `127.0.0.1`) | `+ c.publish(hostPort, containerPort)` |
| Keep a container up through Komodo StopAll | `+ s.komodoSkip` (merge into `labels`) |
| Public HTTPS URL of a registry endpoint | `c.url(reg.endpoints.<x>).public` |
| Container URL of a registry endpoint | `c.url(reg.endpoints.<x>).container` |

## Networks

`s.network.default` is this stack's private bridge (its services reach each other by
container name). Beyond that, join the shared nets you depend on:

| Shared net | Owner | Join when |
| --- | --- | --- |
| `reg.sharedNetworks.proxy` | traefik | the stack is reached through Traefik (almost always) |
| `reg.sharedNetworks.postgres` | postgres | using the shared Postgres cluster |
| `reg.sharedNetworks.dbBackups` | databasus | backups reach this stack's DB |
| `reg.sharedNetworks.infisical` | infisical | talking to Infisical service-to-service |
| `reg.sharedNetworks.edge` | authentik | on the authentik outpost edge |

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

**Shared Postgres instead of a dedicated DB** — delete the `db` service; join the
shared net; build the DSN from the registry endpoint:

```jsonnet
local pgHost = reg.endpoints.postgres.container.host;  // 'postgres_db'
local pgPort = reg.endpoints.postgres.container.port;  // 5432
// in environment:
DATABASE_URL: 'postgres://${POSTGRES_USER:?err}:${POSTGRES_PASS:?err}@'
              + pgHost + ':' + std.toString(pgPort) + '/' + dbName,
// on the service + top-level networks:
[reg.sharedNetworks.postgres.name]: { aliases: [n.container(app)] },
// and pass the shared creds too:
c.render(stack, manifest, [secrets.<stack>.path, secrets.postgres.path])
```
Real: `apps/business/templates/twenty`, `apps/business/n8n`, `apps/business/docuseal`,
`apps/business/openproject`.

**A second published port / raw-TCP Traefik router** (e.g. SSH) — merge extra ports and
hand-write the `traefik.tcp.*` labels (`s.proxy.add` only builds HTTP routers). Real:
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
current callers — kept for stacks that need to emit an env file from jsonnet. Auth is
hand-written per stack today: existing stacks (komodo, komodo-mcp) write basicauth labels
directly on top of `s.proxy.add(...)`; there's no forward-auth helper.
