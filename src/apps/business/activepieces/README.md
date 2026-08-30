# activepieces

[Activepieces](https://www.activepieces.com/) — self-hosted workflow automation. Reached at
`activepieces.ktbinternal.com` via Traefik → port 80.

Source of truth: `stack.jsonnet` — don't edit the generated `compose.yaml`.

## Shape

One image run two ways — `app` (API + UI) and five `worker` replicas — over a dedicated
pgvector Postgres (`db`) and a Redis queue (`cache`). Deployed via Komodo on `littlebuddy`,
published on `127.0.0.1:18071`.

`db` is this stack's own Postgres, not the shared cluster: activepieces needs the `vector`
extension, which the shared cluster's image does not carry, and it reads discrete
`AP_POSTGRES_*` values rather than one connection URL.

`worker` has no `container_name` — compose refuses a fixed name on a replicated service.
Workers dial the API as `http://app` over the private bridge; only `app` carries the public
`AP_FRONTEND_URL`. The piece/engine cache is a named volume (`activepieces_engine`) shared by
`app` and every worker, in place of the upstream `./cache` bind.

## Secrets

Infisical project **apps**, environment **prod**, folder **`/activepieces`**, injected under
exactly the names the containers read — the provider injects values, it never renames them:

| Key | Read by | Value |
| --- | --- | --- |
| `POSTGRES_PASSWORD` | `db` | generate once |
| `AP_POSTGRES_PASSWORD` | `app`, `worker` | **the same value as `POSTGRES_PASSWORD`** |
| `AP_ENCRYPTION_KEY` | `app`, `worker` | `openssl rand -hex 16` (32 hex chars) |
| `AP_JWT_SECRET` | `app`, `worker` | `openssl rand -base64 32` |

Optional, same folder: `AP_OPENAI_API_KEY` (only read when `AP_TOOL_SEARCH_ENABLED=true`).

Store all four before the first deploy — Postgres initialises its data directory on first
start, and coming up without a password means destroying the volume to fix it.
