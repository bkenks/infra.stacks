# woodpecker

[Woodpecker CI](https://woodpecker-ci.org/) — CI/CD `server` + `agent` pair. UI/API at `peck.ktbinternal.com` (port 8000); gRPC on 9000 for the agent. Agent runs pipeline steps as sibling containers via the host Docker socket. State: SQLite (`woodpecker-server-data` volume). Forge: self-hosted Forgejo (`https://fj.ktbinternal.com`).

Source of truth: `refs.libsonnet` (names) + `stack.jsonnet` (the manifest) — don't edit the generated `compose.yaml` / `services.yaml`.

Pipeline authoring: see `pipelines.md`.

## Deploy

Deployed via Komodo. Infisical `/woodpecker` (`WOODPECKER_FORGEJO_CLIENT`, `WOODPECKER_FORGEJO_SECRET`, `WOODPECKER_AGENT_SECRET`) → `/dev/shm/woodpecker.env`. `WOODPECKER_AGENT_SECRET` must match on both `server` and `agent`.

One-time setup: register the OAuth2 app in Forgejo (`/user/settings/applications`, redirect URI `https://peck.ktbinternal.com/authorize`) → client ID/secret into Infisical; generate the agent secret via `openssl rand -hex 32`; point `peck.ktbinternal.com` DNS at the host.

`agent` bind-mounts the host Docker socket (`/var/run/docker.sock`) — required, not removable.
