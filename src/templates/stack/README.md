# Stack template

Standard reference for authoring a docker-compose stack in Pkl. The `stack.pkl` here is a
real, rendering stack (app + dedicated Postgres, with secrets): copy the directory, don't
start from scratch. Its output lands beside it as `compose.yaml`, so you can see input and
output side by side. It is rebuilt on every commit, which is what stops this template from
silently rotting when the library changes under it.

## Scaffold a new stack

1. Copy this directory to `src/<area>/<stack>/`; `area` is `apps/<group>`,
   `platform/<group>`, or `tools/<group>`.
2. Set `name`. It is the compose project name and the prefix of every derived container
   (`<name>-<role>`) and volume (`<name>-<role>_<purpose>`).
3. Delete the services and fields you don't need.
4. Register the secret bundle (see [Secrets](#secrets)), then deploy via Komodo. Never
   `docker compose` a stack by hand.
5. Add the stack to Komodo with `run_directory = "./src/<area>/<stack>"`; it deploys the
   `compose.yaml` there.

Committing re-renders everything automatically (lefthook runs `mise run render`). Never
edit a file whose first line is the `# GENERATED from …` header.

## The one file

`stack.pkl` is the whole stack. It amends `@infra/Stack.pkl`, sets `name`, fills
`services` by role, and declares `networks`. Everything else is derived or rendered.

```pkl
amends "@infra/Stack.pkl"

import "@infra/registry.pkl"
import "@infra/collections.pkl" as col
import "@infra/secrets.pkl"

name = "example"

services {
  ["secrets"] = secrets.provider("apps", "/example")

  ["app"] {
    image = "ghcr.io/example/example:1.2.3"
    restart = "unless-stopped"
    data { ["data"] { target = "/data" } }
    depends_on {
      ...secrets.ready
      ["db"] { condition = "service_healthy" }
    }
    environment { ["DB_HOST"] = "db" }
  }
}

networks {
  ["default"] { name = module.name }
}
```

`@compose` is the pkl-compose library (vendored under `.vendir/pkl-compose`); `@infra` is
`src/lib`, this repo's own package. Both resolve from any depth under `src/` because the
root `PklProject` declares them; `mise run render` always evaluates from the repo root.

## Names

| You write | You get |
| --- | --- |
| `name = "example"` | compose `name`, and what the private bridge is called |
| `["app"] { … }` | `container_name: example-app`, `hostname: app`; other services dial `app` |
| `data { ["data"] { target = "/data" } }` | a mount from `app_data`, and a top-level volume `app_data` named `example-app_data` |
| `networks { ["backend"] {} }` | a network named `example_backend` |

**Services are keyed by role** (`Types.Role` in pkl-compose: `app`, `db`, `cache`,
`worker`, `tv`, `media`, …), so `db` is never also `database` in some other stack. A key
outside the enumeration fails eval; add the role upstream and release pkl-compose rather
than reaching for a product name. Two services of one role take a qualifier:
`secrets-traefik` (see `platform/edge/pangolin`).

**Override a derived name by writing it again.** `container_name = "postgres-db"` keeps
a name other systems already dial (`databases/postgres`, `platform/edge/pangolin`).

A volume mounted by several services is declared once under `data` on the service that
owns it and mounted by the others as `new { type = "volume"; source = "<role>_<purpose>";
target = … }`. Bind mounts are `col.bind(host, container)` / `col.bindReadOnly(…)`.

## Golden rule: reference by key, never by string

Anything that crosses stack boundaries lives in `src/lib/registry.pkl`. Reference the
entry, not a string literal into it:

```pkl
registry.endpoint.serviceGroup.postgres.host.addr   // typo fails at eval
"littlebuddy.internal:6109"                         // typo fails silently at `up`
```

`collections.pkl` holds the constants that depend on nothing: spellings and defaults.
`registry.pkl` is the global version of a stack's own names: a value goes there the moment
a *second* stack needs it.

## Cheat-sheet

| Need | Use |
| --- | --- |
| Publish a host port | `ports { new { target = 8080; published = 18000; host_ip = col.ip.loopback } }` |
| Reach a service on another host | `registry.endpoint.serviceGroup.<x>.host.addr` |
| Wait on a healthcheck | `depends_on { ["db"] { condition = "service_healthy" } }` |
| Mount the docker socket | `col.mounts.dockerSock` (`…RW` when it must write) |
| Keep a container up through Komodo StopAll | `labels = col.labels.komodoSkip` |
| Pull in a secret bundle | `["secrets"] = secrets.provider("apps", "/<folder>")` |
| Depend on that bundle | `depends_on = secrets.ready` (or spread `...secrets.ready`) |
| Public HTTPS URL of an endpoint | `registry.endpoint.serviceGroup.<x>.proxy.url` |
| Durations and sizes | `interval = 30.s`, `memory = 512.mib` |
| A one-off hook | `pre_start { new { image = "alpine:3.20"; command { … } } }` |

## Networks

**Container to container, on one host**: a shared docker network. It is one entry in
`registry.network.shared`, and every participating stack writes it into its top-level
`networks` alongside the private bridge:

```pkl
local sharedDB = registry.network.shared.db_001

networks {
  ["default"] { name = module.name }
  [sharedDB.name] { name = sharedDB.name; `external` = true }
}
// and on each participating service:
networks { "default"; sharedDB.name }
```

Compose creates an `external` network for nobody, so attaching before it exists fails the
deploy rather than silently building a second empty network of the same name.

**Host to host**: the `.internal` zone, which every host's CoreDNS resolves. Publish the
port and dial `registry.endpoint.serviceGroup.<x>.host.addr`.

A service using `network_mode` (host, or `service:<other>`) must declare no `networks` at
all. Real: `apps/media/stream` (media), `platform/edge/pangolin` (proxy).

## Secrets

Secrets come from the **infisical-secrets** Compose provider. Compose runs it at `up`, and
every secret in the bundle is injected as a plain environment variable, under its own
Infisical name, into each service that declares `depends_on` on the provider service.

1. The Infisical project holding the bundle must be a key of `registry.infisical.project`.
   The bundle's *folder* does not go in the registry: exactly one stack reads it.
2. Assign the provider service with `=`, never the amends form (the amends form goes
   through the role default and picks up a `container_name`):

   ```pkl
   ["secrets"] = secrets.provider("apps", "/<folder>")
   ```

3. Add `secrets.ready` to the `depends_on` of every service that reads one. A provider has
   no health of its own, so `service_started` is the only condition it can satisfy.
4. Write nothing in `environment` for those values; leave a comment naming them.

**Store each secret under exactly the name the container reads.** There is no compose-level
interpolation left, so the provider cannot rename a value or build one out of parts.

A secret that has to arrive as a **file** needs a `pre_start` hook. Real:
`platform/backup-manager/databasus`.

The restore tier (`databasus`, `zerobyte`) renders a second document with the provider
swapped for an env file: `when (module.bootstrap) { … }` in the stack, and
`output { files { ["bootstrap.yaml"] = module.file((module) { bootstrap = true }) } }`.

One stack the provider cannot serve, `platform/secrets-manager/infisical`, still takes an
env file at its `include`. Nothing else should.

## More than one file

`output.files` names every file a stack renders; `compose.yaml` is there by default.
`module.file(doc)` renders a compose document, `module.yamlFile(doc)` a plain YAML file.
Real: `platform/edge/pangolin` (four config files from `files/config.pkl`),
`platform/overlay/traefik` (`config/traefik.yaml`).
