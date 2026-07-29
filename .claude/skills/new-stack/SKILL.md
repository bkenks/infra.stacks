---
name: new-stack
description: Scaffold a new jsonnet stack in this repo — pick the directory under src/, copy src/.template/stack.jsonnet, wire it to lib/ (Service/Stack/registry/Secret), register secrets and the Komodo sync entry, and render. Use whenever adding, moving, or renaming a stack, or when asked "add <service> to the homelab".
---

# Build a new stack

A stack is one directory under `src/` holding a hand-written `stack.jsonnet` and the YAML it
renders to. `lib/` is the only import; `registry.libsonnet` is the only place a cross-stack
name may be spelled. Follow the steps in order — several of them are compile-time contracts,
not style.

## 0. Read these first

| File | Why |
| --- | --- |
| `src/.template/README.md` | The authoring guide, with a worked example per variation. Read it. |
| `src/.template/stack.jsonnet` | The canonical copy-me stack. It compiles, so it never rots. |
| `lib/registry.libsonnet` | Every key you are allowed to reference. Skim `role`, `endpoint`, `domains`, `dirs`, `networks.shared`, `infisical.catalog`. |
| `CLAUDE.md` | Render pipeline, generated-file rule, network model. |

Look at a real stack of the same shape before writing:

- shared Postgres over the host gateway — `src/apps/business/n8n`
- dedicated DB + secrets — `src/.template`
- overridden container name — `src/databases/postgres` (`postgres-db`)
- shared Docker network — `src/platform/edge/tailscale` (creates `tsGateway`),
  `src/platform/identity/authentik` (attaches to it)
- non-compose entrypoint (renders config beside itself) — `src/platform/edge/pangolin/files/configs.jsonnet`,
  `src/platform/edge/newt/envs/env.jsonnet`

## 1. Pick the directory

`src/<area>/<group>/<stack>/`, one stack per leaf directory:

- `src/apps/{business,media,personal}/` — user-facing
- `src/platform/{edge,identity,container-manager,secrets-manager,backup-manager,dashboard}/` — infra
- `src/databases/` — shared data services
- `src/tools/{devops,komodo-mcp}/` — internal tooling

Nothing that isn't a stack goes under `src/`. If it's ambiguous, ask rather than inventing a
new top-level area.

## 2. Copy the template

```
cp src/.template/stack.jsonnet src/<area>/<group>/<stack>/stack.jsonnet
```

Then: rename the `name` local, delete every service and field the stack doesn't need, and
strip the template's teaching comments. Keep comments only where they explain a decision a
future reader would otherwise undo (see n8n's "do NOT set user: 0:0").

`name` is the one string the stack chooses — the compose project, the `<name>_<role>`
container prefix, the `<name>_<key>` volume prefix, and the default network's name. Bind it
once and pass it to both `lib.Stack` and `lib.render`.

## 3. Wire it to `lib/`

```jsonnet
local lib = import 'lib/lib.libsonnet';
local reg = lib.registry;
local role = reg.role;
```

That path resolves from any depth — `render.py` passes the repo root as the jsonnet jpath
(`-J`). `lib/lib.libsonnet` is the **only** entrypoint; never import `compose.libsonnet` or
`registry.libsonnet` directly.

The file ends in exactly one `lib.render(projectName, stack, envFiles)`.

### Helper cheat-sheet

| Need | Use |
| --- | --- |
| A service | `lib.Service { … }` |
| The manifest | `lib.Stack(name, function(ref) { … })` |
| Emit the two YAMLs | `lib.render(name, stack, envFiles)` |
| Owned volume | `volumes_:: { data: '/var/lib/x' }` → mount + top-level `<name>_data` |
| Bind mount / host path | `mounts_:: ['./files/x.yaml:/app/x.yaml:ro']` — verbatim |
| Put a service on a shared network | `networks_:: lib.network.join(reg.networks.shared.<x>)` |
| Define that network — consumer | `lib.Stack(name, fn, lib.network.attach(reg.networks.shared.<x>))` |
| Define it — the one owning stack | `lib.Stack(name, fn, lib.network.create(reg.networks.shared.<x>))` |
| Replace the private bridge | same third arg, keyed `default` (merged last; `default` is always emitted) |
| Publish a port | `ports: ['%s:18000:8080' % reg.ips.loopback]` — loopback-bound, always |
| Env-file path for a secret bundle | `lib.Secret('<catalogue-key>')` |
| …overridable during bootstrap | `lib.SecretOrBootstrap('<catalogue-key>')` |
| Survive Komodo StopAll | `labels: lib.komodoSkip` |
| Render `KEY=value` lines | `lib.toEnv(obj)` |

`lib.Service` derives `container_name`, `restart`, and the `networks` alias block from the
stack/role bound by `lib.Stack`. Every one is a plain field — override by writing it again,
and say in a comment who dials the hard-coded name.

### Two rules that fail loudly if broken

**Key services by role, not by string.** `[role.APP]`, `[role.DB]` — from `reg.role`. A
service whose name is genuinely app-specific (`guacd`, `gerbil`) uses a plain `local` string.
If the role you want isn't in `reg.role`, add it there rather than typing a literal.

**Reference by key, never by string literal.**

```jsonnet
reg.endpoint.postgres.host.host   // ✓ a typo fails at compile time
'host.docker.internal'            // ✗ a typo fails silently at runtime
```

Applies to `reg.role.*`, `reg.domains.*`, `reg.endpoint.*`, `reg.dirs.*`, `reg.ips.*`,
`reg.hosts.*`, `reg.networks.shared.*`, and `lib.Secret('<key>')`. If the value you need
isn't in the registry and crosses a stack boundary, add it to the registry first.

Cross-service references inside the stack go through `ref[role.DB]` — asking for a role the
stack doesn't declare is an evaluation error at the point of the mistake.

## 4. Cross-stack traffic

There is no cluster DNS. Default: publish the port on loopback and dial it from the consumer
at `host.docker.internal:<port>` with `extra_hosts: ['host.docker.internal:host-gateway']`.
Shared Postgres is single-sourced this way at `reg.endpoint.postgres.host`.

A shared Docker network is the exception, not the default. It takes two halves, and every
existing stack writes them the same way:

```jsonnet
lib.Stack(name, function(ref) {
  [role.DB]: lib.Service {
    networks_:: lib.network.join(reg.networks.shared.postgresDB),   // membership
  },
}, lib.network.attach(reg.networks.shared.postgresDB))              // top-level definition
```

`join` on the service says *this container is on it*; the third argument to `lib.Stack` is
the top-level definition. Exactly one stack passes `create` (it owns the network); every
other passes `attach` (`external: true`, so attaching before the owner exists fails the
deploy rather than silently building an empty second network). Real: `platform/edge/tailscale`
creates `tsGateway`, `platform/identity/authentik` attaches.

Note `src/.template/README.md` shows `create`/`attach` inside `networks_` — no stack does
that. Follow the shape above.

`networks_` is incompatible with `network_mode` (a container sharing another's netns has no
network stack of its own) and says so at render time.

## 5. Secrets

Skip this whole step for a stack with no secrets and omit `lib.render`'s third argument.

1. Add an entry to `infisical.catalog` in `lib/registry.libsonnet`:
   `type: 'dump'` (whole folder), `'map'` (explicit renames via `keys`), `'raw'` (single
   value via `key`). `dest` is the filename under `/dev/shm/`.
2. Pass `lib.Secret('<key>')` to `lib.render` — never spell the path. The agent fragment and
   the stack derive it from the same entry, so they can't disagree.
3. Reference each var in `environment:` as `${VAR:?err}` so a missing value aborts the deploy
   instead of interpolating empty.
4. Tell the user the secret must exist in Infisical, and the host must list the stack in its
   `AGENT_SERVICES`, before the first `up`.

Use `lib.SecretOrBootstrap` only for stacks the control plane brings up before the agent
exists (`komodo`, `infisical`, `cloudflared`, `zerobyte`).

Gotcha: some images don't interpolate env-file values into every field — when that happens,
put the literal `${VAR:?err}` in `environment:` (see `apps/media/immich`).

## 6. Write the per-stack `README.md`

Hand-written, short, and about deploying *this* stack: what it is, the URL/port it's reached
at, which env files it needs, and the gotchas a future reader would otherwise re-break.
Don't restate the library — that's `src/.template/README.md`.

## 7. Register with Komodo

Add a `[[stack]]` block to `files/komodo_config/komodo-config-sync.toml`:

```toml
[[stack]]
name = "<stack>"
[stack.config]
server = "<host from reg.hosts>"
linked_repo = "infra.stacks"
run_directory = "./src/<area>/<group>/<stack>"
file_paths = ["stack.compose.yaml"]
```

`file_paths` is mandatory — the parent file is not named `compose.yaml`, so Komodo's default
discovery misses it. `run_directory` is the stack's own source directory. Deploying to
several hosts means several entries. Ask which host before guessing.

That TOML is bidirectional (Komodo commits UI changes back to it), so edit it surgically and
leave unrelated blocks alone.

## 8. Render and verify

```
mise run render          # or ./.config/mise/tasks/render.py
```

Takes no arguments, rebuilds everything, ~0.5s. On a fresh clone run `mise trust && mise
install` first. Failure aborts before touching disk, so a jsonnet error leaves the tree clean.

Then read `stack.services.yaml` and confirm the container names, volume names, ports, and env
references are what you intended.

Optional smoke test — copy `src/apps/business/n8n/tests/render_compose.sh` into
`<stack>/tests/`, adjust the project name and the faked env files, and run it. It runs
`docker compose config` in a container so `/dev/shm` exists.

**Never hand-edit a file whose first line is `# GENERATED from … — DO NOT EDIT.`** The
builder deletes every header-marked file before writing the fresh set, and refuses to
overwrite a file that lacks the header.

Committing re-renders automatically — `.config/lefthook.yml` runs `mise run render` on
pre-commit and stages exactly what it wrote.

## Checklist

- [ ] Directory is `src/<area>/<group>/<stack>/`
- [ ] `stack.jsonnet` imports only `lib/lib.libsonnet`, ends in one `lib.render`
- [ ] Services keyed by `reg.role.*`; cross-service refs via `ref[role.X]`
- [ ] No literal for anything that exists in the registry
- [ ] Published ports bound to `reg.ips.loopback`
- [ ] Secrets registered in `infisical.catalog`, passed as `lib.Secret('<key>')`, read as `${VAR:?err}`
- [ ] `README.md` written
- [ ] `[[stack]]` entry added with `run_directory` + `file_paths`
- [ ] `mise run render` clean; generated YAML reviewed, never hand-edited
