# termix

> 📚 System architecture and the secrets-flow live in Notion → **[Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c)**. This file covers only this stack: how to deploy/use it and its quirks.

Termix — a self-hosted web SSH/terminal and server-management UI. Reached at
**https://termix.homektb.com** (Traefik → container port 8080). Ships
with `guacd` (Apache Guacamole proxy daemon) as a sidecar for remote-desktop
connections; `guacd` is internal-only (no published ports, reached over the
stack's `default` network on 4822).

Source of truth: `compose.jsonnet` + `compose.stack.jsonnet` compile to
`compose.yaml` + `compose.stack.yaml` — do not edit the YAML directly.

### Secrets

This stack has **no secrets** — nothing is rendered to `/dev/shm` by the
Infisical agent. The only config is the literal `PORT`, baked directly into
`compose.stack.jsonnet`'s `environment:` block — no `.env` file for it.

### Services

- **app** (`ghcr.io/lukegus/termix`) — the Termix web UI. Persists state in the
  `termix-data` volume (`/app/data`). Exposed via Traefik on
  `termix.homektb.com`.
- **guacd** (`docker.io/guacamole/guacd`) — Guacamole proxy daemon. Internal
  only; `app` depends on it and talks to it on the `default` network.

Image versions are pinned in `compose.stack.jsonnet` (`appVersion`, `guacdVersion`).

### Volume rename on first deploy

The old (pre-jsonnet) volume was the implicit `termix_termix-data`. The
jsonnet version names it explicitly `termix-data`. Before redeploying, migrate
the data:

```bash
.scripts/rename-volume.sh termix_termix-data termix-data
```

### Compose Commands

*Validate the merged config locally (no deploy host needed):*
```bash
tests/render_compose.sh            # render + validate the merged config
tests/render_compose.sh --services # any `docker compose config` flag passes through
```

*Start Stack:*
```bash
docker compose up -d
```

(Deploy via Komodo in normal operation.)
