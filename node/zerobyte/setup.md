# Zerobyte — per-host backup automation

> 📚 System architecture, the secrets-flow, and the deploy model live in Notion →
> **[Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c)**.
> This file covers only `zerobyte`: what it runs and its secret/deploy specifics.
> (Notion = prose/architecture; repo = compose/usage.)

[Zerobyte](https://zerobyte.app) is a Docker-based backup-automation platform
(web UI on `4096`). It runs **on every host** (a `stack.node` member, like
`traefik` and `infisical-agent`): each host backs up its *own* local data to a
remote backend, so no host depends on another for its backups, and a single
host going down takes only its own zerobyte with it.

Reached **directly by host / Tailscale IP** (e.g. `http://100.114.137.104:4096`) —
zerobyte no longer uses Traefik. The web UI port (`4096`) is published on the
host, and the app's own public URL is set per-server via `ZEROBYTE__BASE_URL`.

## Per-host deploy (Komodo)

Deploy this stack to each host with one **per-server variable**:

| Variable            | Value                   | Notes                                            |
|---------------------|-------------------------|--------------------------------------------------|
| `ZEROBYTE__BASE_URL`| the URL you reach it on | e.g. `http://<tailscale-ip>:4096` — sets the app's `BASE_URL` (links/redirects) |

It is intentionally empty in `interpolation-envs/general.env` (`:?err`) so a
deploy fails fast if the per-server value is missing.

## Secrets

One secret — `APP_SECRET`, the 32+ char key that encrypts stored backend
credentials in zerobyte's local DB. It is **never committed**; this host's
`infisical-agent` renders it to `/dev/shm/node_zerobyte.env` and `compose.yaml`'s
`include: -> env_file:` pulls it in.

One-time setup:

1. Generate the secret: `openssl rand -hex 32`.
2. Store it in Infisical under the **`/zerobyte`** folder, key **`ZEROBYTE_APP_SECRET`**
   (env `prod`). A single shared value across hosts is fine — the instances are
   independent and don't share a DB; the secret only needs to be stable per host.
   The agent template blocks read it from project
   `86324d9b-3dd7-49d4-b252-69228c5ee0c7` (the infra project, alongside
   komodo/gitea), folder `/zerobyte`.
3. Scope each host's machine identity in Infisical to read the `/zerobyte` folder.
4. The agent template blocks are already added for all three hosts (a push that
   touches `infisical-agent/files/configs/**` redeploys every agent).

## Backing up data (per host)

Zerobyte only sees what you mount into it. Add read-only source bind mounts in
`compose/stack.yml` (commented examples are there), e.g.
`/var/lib/docker/volumes:/source/docker-volumes:ro`, then pick them as backup
sources in the UI. Note: `cap_add: SYS_ADMIN` + `/dev/fuse` are included so
zerobyte can FUSE-mount **remote** backends (S3/B2/SFTP via rclone). Drop both
for a reduced-privilege, local-only deployment.

`/var/lib/zerobyte` (zerobyte's own config + DB) is a project-scoped **local**
named volume — per upstream docs it must never be a network share.

## Compose Commands

*Local/standalone testing only — in the homelab deploy via Komodo:*

```bash
ZEROBYTE__BASE_URL=http://localhost:4096 docker compose up -d   # needs /dev/shm/node_zerobyte.env present
```

First login at the host's `BASE_URL` (e.g. `http://<tailscale-ip>:4096`) creates the admin account.
