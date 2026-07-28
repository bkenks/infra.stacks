# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Self-hosted homelab monorepo. Each leaf directory is a **stack** authored in jsonnet, rendered to Docker Compose YAML in place on commit, and deployed by **Komodo** across a fleet of Tailscale-connected hosts.

## The one rule that dominates everything

**Generated files sit beside the `.jsonnet` that produced them, prefixed with its name.**

`src/platform/edge/pangolin/files/configs.jsonnet` writes `configs.config.yaml` into its own directory; every `stack.jsonnet` writes `stack.compose.yaml` + `stack.services.yaml` next to itself. The rule is `<entrypoint-stem>.<key-stem><ext>` — the source name leads, so a directory listing sorts every output under the entrypoint that owns it.

**Never edit a file whose first line is `# GENERATED from … — DO NOT EDIT.`** That header is the ownership marker: the builder deletes every file carrying it before writing the fresh set, which is what makes a rebuild total (a deleted stack or a renamed output leaves nothing behind). A file without the header is hand-written; the build refuses to overwrite one.

Generated output is committed because Komodo clones this repo on the target host and deploys out of `src/` directly. Everything that is not a stack stays out of `src/`: `.config/` (the builder, `mise.toml`, `lefthook.yml`), `lib/` (the jsonnet library), `files/komodo_config/` (the Komodo resource-sync TOML), docs.

## Toolchain (mise)

`.config/mise.toml` pins the three tools the build needs: `go-jsonnet` (the `jsonnet` binary the builder shells out to), `uv` (the builder's runtime, which resolves its own Python), and `lefthook`. On a fresh clone run **`mise trust && mise install`** — the trust is required per-machine before mise will act on a config, and `install`'s postinstall hook runs `lefthook install` to wire up the git hooks. Both configs live in `.config/`, which mise and lefthook each search natively; mise's config root is still the repo root, so the `-J` jpath is unaffected. `mise run render` is the render task lefthook itself invokes; it is **not declared in `mise.toml`** — mise discovers executables under `.config/mise/tasks/` by filename (extension stripped), so the file `.config/mise/tasks/render.py` *is* the `render` task.

## Render pipeline (exact commands)

`.config/mise/tasks/render.py` is the builder (a `uv run` self-contained script; the `jsonnet` binary comes from mise). It takes **no arguments** and always rebuilds everything — ~0.5s for all 36 entrypoints:

```
mise run render     # or ./.config/mise/tasks/render.py directly
```

It (1) runs `jsonnet -J <repo root>` on every `.jsonnet` under `src/` and builds the full output set in memory, so a jsonnet or YAML failure aborts before anything on disk is touched, (2) deletes every header-marked file that the fresh set no longer contains, (3) writes each output next to its entrypoint as `<entrypoint-stem>.<key-stem><ext>`. An entrypoint must evaluate to `{'<bare-filename>': content, …}`; dict content renders to YAML, string content is written verbatim (Infisical fragments carry Go-template bytes that must not be reparsed).

Hand-written files are never touched: nothing is copied, and an output that would land on a file lacking the generated header is a hard error.

Normally you don't call it directly — **`.config/lefthook.yml` runs `mise run render` on every pre-commit**. The builder prints every path it wrote or removed on **stdout** (the summary goes to stderr), and lefthook pipes that list into `git add`, so a commit stages the generated files and nothing else left unstaged on purpose. There is no glob and no incremental mode: a rebuild is total, so a deleted stack, a renamed output, and a `registry.libsonnet` edit reaching every stack are all handled by the same single job.

Only `*.libsonnet` (imported, never an entrypoint) is ignored. Per-stack `README.md` and `tests/` simply live where they always did, so a stack's `tests/render_compose.sh` runs against the compose file in its own directory.

## The jsonnet library (`lib/`, reached via the repo-root `-J` jpath)

A stack imports exactly one file — `local lib = import 'lib/lib.libsonnet';` — from any depth under `src/`.

- **`lib.libsonnet`** — the single entrypoint. Re-exports `Service`/`Stack`, and adds `render(projectName, stack, envFiles=[])` (the contract every `stack.jsonnet` ends with — emits `stack.compose.yaml` with the project name + `include:`, `env_file:` only when secrets exist, and `stack.services.yaml` with the real manifest), `Secret(key)` / `SecretOrBootstrap(key)`, `komodoSkip`, `toEnv(obj)`, and `registry`.
- **`compose.libsonnet`** — `Service` and `Stack`. `Service` derives `container_name` (`<stack>_<role>`), `restart`, the network alias, and volume mounts from late-bound `self.stack`/`self.role`; `Stack(name, services, networks=null)` binds those in, keys services by bare role, and registers top-level volumes from what mounts them. Every derived field is a plain field, so a stack overrides one by writing it again — that is how `postgres-db`, komodo's `komodo_core` alias, and pangolin's unprefixed `gerbil`/`traefik` survive.
- **`registry.libsonnet`** — source of truth for anything crossing stack boundaries. **Reference by KEY, never by string literal**: `reg.endpoint.postgres.host` fails at compile time on a typo; `'host.docker.internal:6109'` fails silently at runtime. Holds: `hosts` (the host inventory, keyed by short name, `ip` = the host's WireGuard addr — there is no cluster DNS, so a cross-host reference dials it directly), `role` (the service-key vocabulary), `domains`, `endpoint`, `dirs`, `ips`, `networks`, and `infisical.catalog` (every renderable secret bundle).

`Stack` takes the services as `function(ref) {...}`, called twice: once for its keys, once with `ref` — a table mapping each declared role to the name it will actually carry. Cross-service references go through `ref[role.DB]`, so naming a role the stack does not declare fails at evaluation rather than in a container that never starts.

**Authoring guide with worked examples lives at `src/.template/README.md`** — read it before writing a new stack. `src/.template/` is the canonical copy-me stack; it is a real compiling stack, so a lib change that breaks it fails the build.

## Stack directory convention

One directory holds both the sources and what they render to:

| File | Hand-written? | Role |
|---|---|---|
| `stack.jsonnet` | yes | Source of truth — ends in `lib.render(...)`. |
| `stack.compose.yaml` | no | What `docker compose` loads: project name + `include:` (+ `env_file:`). |
| `stack.services.yaml` | no | The real manifest; **this is the file Komodo watches/diffs**. |
| `files/`, `templates/` | both | Bind-mounted config: nested `.jsonnet` entrypoints, their outputs, and hand-written assets (e.g. `files/entrypoint.sh`) side by side. |
| `README.md` | yes | Per-stack deploy notes. |

A bind mount pointing at generated config must spell the generated name — pangolin mounts `./files/configs.config.yaml`, not `./files/config.yaml`.

## Network model (non-obvious)

Each stack gets a private `default` bridge, and **cross-stack traffic goes over published host ports by default** — dialed as `host.docker.internal:<port>` with `extra_hosts: ['host.docker.internal:host-gateway']` on the consumer. The shared Postgres cluster (`databases/postgres`) is single-sourced this way via `reg.endpoint.postgres.host`.

A service can also join a shared Docker network: `networks_:: lib.network.create(reg.networks.shared.<x>)` in the one stack that owns it, `lib.network.attach(...)` in every consumer. `Stack` hoists those definitions to the top-level `networks:` block the same way it hoists `volumes_`, so a network is declared on the service that uses it and nowhere else. `lib.Stack`'s third argument is merged last over that block, so it redefines the private `default` bridge (pangolin's ipv6) without touching hoisted networks; `default` itself is always emitted.

## Secrets (Infisical)

Self-hosted Infisical is the store; the **infisical-agent** runs on every host and renders that host's secrets to `/dev/shm/<stack>.env` (RAM, never disk). To add a secret bundle: register it in `registry.libsonnet` `infisical.catalog`, which `templates/services.jsonnet` bakes into a per-service agent fragment; a host opts in via its `AGENT_SERVICES` list. In a stack, pass `lib.Secret('<catalogue-key>')` to `lib.render` and reference vars as `${VAR:?err}` so a missing secret aborts the deploy. Producer and consumer derive the path from the same catalogue entry, so they cannot disagree; `lib.SecretOrBootstrap(key)` is the same path wrapped in `${ANSIBLE_SECRETS_FILE:-…}` for stacks the control plane brings up before the agent exists.

## Deployment (Komodo)

All Komodo resources — stacks, servers, variables, procedures — are declared in one authoritative resource-sync file: `komodo-config-sync.toml` at the repo root (`managed = true`). It lives outside `src/` because Komodo commits back to it, and generated output must never be a write target. Each stack sets `linked_repo = "infra.stacks"` + `run_directory` + `server`; Komodo clones the repo on the target host and runs `docker compose` there. **`run_directory` is the stack's own source directory** — `./src/platform/edge/cloudflared` — and every entry needs `file_paths = ["stack.compose.yaml"]`, since the parent compose file is not named `compose.yaml` and Komodo's default discovery would miss it. The same stack dir is deployed to many hosts as separate entries.

**"[Komodo] Commit Sync" commits are Komodo writing UI-side changes back into that TOML** — the sync is bidirectional, so the TOML stays canonical.

## Top-level org

- `src/` — every stack. `apps/` (user-facing: `business/`, `media/`, `personal/`), `platform/` (infra: `edge/`, `container-manager/`, `secrets-manager/`, `backup-manager/`, `dashboard/`, `identity/`), `databases/` (`postgres/`), `tools/` (`devops/`, `komodo-mcp/`), and `.template/` — the canonical stack template + authoring guide. (`src/template/` and `src/apps/business/templates/` are separate scaffolding/reference stacks.)
- `.config/` — `mise.toml` (toolchain pins), `lefthook.yml` (the pre-commit hook), and `mise/tasks/render.py`, the builder mise auto-discovers as the `render` task.
- `lib/` — `lib.libsonnet` (the one import), `compose.libsonnet`, `registry.libsonnet`.
- `files/komodo_config/komodo-config-sync.toml` — the Komodo resource-sync file.
