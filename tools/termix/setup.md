## Stack: Termix

> 📚 System architecture and the secrets-flow live in Notion → **[Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c)**. This file covers only `stack.infra/termix`: how to deploy/use it and its quirks.

Termix — a self-hosted web SSH/terminal and server-management UI. Reached at
**https://termix.homektb.com** (Traefik → container port 8080). Ships
with `guacd` (Apache Guacamole proxy daemon) as a sidecar for remote-desktop
connections; `guacd` is internal-only (no published ports, reached over the
stack's `default` network on 4822).

### Secrets

This stack has **no secrets** — nothing is rendered to `/dev/shm` by the
Infisical agent, and there is no `compose/secrets.yml`. The only config is the
literal `PORT` in `container-envs/termix.env`.

### Services

- **app** (`ghcr.io/lukegus/termix`) — the Termix web UI. Persists state in the
  `termix-data` volume (`/app/data`). Exposed via Traefik on
  `termix.homektb.com`.
- **guacd** (`docker.io/guacamole/guacd`) — Guacamole proxy daemon. Internal
  only; `app` depends on it and talks to it on the `default` network.

Image versions are pinned in `interpolation-envs/production.env`
(`TERMIX__VERS_TAG`, `GUACD__VERS_TAG`).

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

(`compose.yaml` already wires the include + env_file scope; no `-f` /
`--env-file` flags needed. Deploy via Komodo in normal operation.)
