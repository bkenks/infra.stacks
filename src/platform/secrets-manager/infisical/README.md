# Infisical

Self-hosted Infisical: the secrets **store** every other stack reads from. App + Postgres +
Redis, on one host (`rick`, published at `registry.endpoint.serviceGroup.infisical.host`).

Source of truth: `stack.jsonnet` (names + the manifest). Do not edit `compose.yaml` or
`services.yaml` — both carry the generated header.

## How stacks read it

Through the **infisical-secrets** Compose provider, not through this stack. A stack declares
a `secrets` service (`lib.SecretsProvider('<catalog key>')`) and every service that needs a
value declares `depends_on` on it; the provider fetches the bundle at `up` and injects each
secret as an environment variable under its own Infisical name.

Nothing renders secrets to disk any more. The `infisical-agent` that used to write
`/dev/shm/<stack>.env` on every host, its `templates/` fragments and its `entrypoint.sh` are
gone, along with the per-host `AGENT_SERVICES` / `AGENT_HOST` wiring.

## Why this stack is the exception

It still takes its own secrets from an env file attached at the include
(`lib.SecretOrBootstrap('infisical')`), because the provider would have to ask this server
for them before it is running. The control plane writes that file and points
`ANSIBLE_SECRETS_FILE` at it; the default path is `lib.Secret('infisical')`.

Every var uses `${VAR:-}` rather than `${VAR:?err}`: validation is at runtime — the app
rejects an empty `ENCRYPTION_KEY` — so a `config` on a host without the file still resolves.

## Credentials the provider uses

Each host holds its own machine identity in the dotenv file at
`registry.path.file.infisical_creds` (`/mnt/secrets/credentials/infisical.env`), read by
every stack's provider via the `credentials-file` option:

```
INFISICAL_UNIVERSAL_AUTH_CLIENT_ID=…
INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET=…
```

The option holds a path, not a secret, so it is safe in a committed compose document. The
file is not — keep it off version control and readable only by the user running Compose, and
scope each host's identity to just the folders its stacks read.

## Deploy

```
ANSIBLE_SECRETS_FILE=/dev/shm/platform.env   # written by the control plane
```

`tests/render_compose.sh` fakes that file and runs `docker compose config`.
