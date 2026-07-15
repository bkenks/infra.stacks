# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Self-hosted homelab monorepo. Each leaf directory is a **stack** authored in jsonnet, rendered to Docker Compose YAML on commit, and deployed by **Komodo** across a fleet of Tailscale-connected hosts.

## The one rule that dominates everything

**`compose.jsonnet` is the source of truth. Never hand-edit generated YAML.** `compose.yaml`, `compose.stack.yaml`, `files/hosts`, `templates/*.yaml` and similar are all generated — each carries a `# GENERATED … DO NOT EDIT.` header and is overwritten on the next commit. Edit the `.jsonnet`/`.libsonnet` and re-render.

## Render pipeline (exact commands)

`.jsonnet/render.py` is the renderer (a `uv run` self-contained script; needs `jsonnet` on PATH). It runs `jsonnet -J .jsonnet/lib <src>`; the entrypoint must evaluate to `{'<bare-filename>': content, …}` and may only write into its own directory.

```
./.jsonnet/render.py platform/edge/dnsmasq/compose.jsonnet
```

Normally you don't call it directly — **`lefthook.yml` renders on pre-commit**:
- A staged `**/*.jsonnet` → re-render that file, `git add -A` the outputs.
- A staged `**/*.libsonnet` → re-render **every** `.jsonnet` in the repo (a lib edit can touch any stack). This is why editing `registry.libsonnet` alone keeps all generated YAML in sync.

Dict content renders to YAML; string content is written verbatim (Infisical fragments carry Go-template bytes that must not be reparsed). The renderer also sweeps stale generated siblings it (or a now-deleted entrypoint) owns, leaving hand-written files alone.

## The jsonnet libs (`.jsonnet/lib/`, imported by bare name via the `-J` jpath)

- **`registry.libsonnet`** — source of truth for anything crossing stack boundaries. **Reference by KEY, never by string literal**: `reg.endpoints.postgres.host` fails at compile time on a typo; `'host.docker.internal:6109'` fails silently at runtime. Holds: `server.hosts` (the host inventory, keyed by short name, `ip` = Tailscale addr — feeds dnsmasq and the Komodo server list), `domains`, `roles`, `endpoints`, and `infisical.catalogue` (every renderable secret bundle, with derived `.path` under `/dev/shm`).
- **`compose.libsonnet`** — helpers: `stack(name)` (name/container/volume prefixing, `komodoSkip` label, private network), `publish(hostPort, containerPort, bindIp=127.0.0.1)`, `url(endpoint)`, and **`render(name, manifest, envFiles=[])`** — the contract every `compose.jsonnet` ends with. It emits `compose.yaml` (project name + `include:` of the manifest, `env_file:` only when secrets exist) and `compose.stack.yaml` (the real `services`/`networks`/`volumes`).

**Authoring guide with worked examples lives at `.jsonnet/templates/README.md`** — read it before writing a new stack. `.jsonnet/templates/` is the canonical copy-me stack.

## Stack directory convention

| File | Role |
|---|---|
| `compose.jsonnet` | Source of truth — hand-edited, ends in `c.render(...)`. |
| `compose.yaml` | Generated. What `docker compose` loads: project name + `include:` (+ `env_file:`). |
| `compose.stack.yaml` | Generated. The real manifest; **this is the file Komodo watches/diffs**. |
| `files/` | Bind-mounted config; may hold its own nested `.jsonnet` entrypoint (e.g. `files/hosts.jsonnet`). |
| `README.md` | Per-stack deploy notes. |

## Network model (non-obvious)

There are **no shared Docker networks**. Each stack gets only a private `default` bridge. Cross-stack traffic goes over published host ports dialed as `host.docker.internal:<port>` with `extra_hosts: ['host.docker.internal:host-gateway']` on the consumer. The shared Postgres cluster (`databases/postgres`) is single-sourced this way via `reg.endpoints.postgres.host`.

## Secrets (Infisical)

Self-hosted Infisical is the store; the **infisical-agent** runs on every host and renders that host's secrets to `/dev/shm/<stack>.env` (RAM, never disk). To add a secret bundle: register it in `registry.libsonnet` `infisical.catalogue`, which `templates/services.jsonnet` bakes into a per-service agent fragment; a host opts in via its `AGENT_SERVICES` list. In a stack, reference `secrets.<stack>.path` and vars as `${VAR:?err}` so a missing secret aborts the deploy.

## Deployment (Komodo)

All Komodo resources — stacks, servers, variables, procedures — are declared in one authoritative resource-sync file: `platform/container-manager/komodo/files/komodo-config-sync.toml` (`managed = true`). Each stack sets `linked_repo = "infra.stacks"` + `run_directory` + `server`; Komodo clones the repo on the target host and runs `docker compose` there. The same stack dir is deployed to many hosts as separate entries.

**"[Komodo] Commit Sync" commits are Komodo writing UI-side changes back into that TOML** — the sync is bidirectional, so the TOML stays canonical.

## Top-level org

- `apps/` — user-facing apps: `business/`, `media/`, `personal/`.
- `platform/` — infra: `edge/` (dnsmasq, cloudflared, newt, pangolin), `container-manager/` (komodo), `secrets-manager/` (infisical), `backup-manager/`, `grist/`.
- `databases/` — shared data stores (`postgres/`).
- `tools/` — operator tooling: `devops/` (forgejo, gitea, woodpecker), `komodo-mcp/`, `termix/`.
- `.jsonnet/templates/` — canonical stack template + authoring guide. (`template/` and `apps/business/templates/` are separate scaffolding/reference stacks.)
