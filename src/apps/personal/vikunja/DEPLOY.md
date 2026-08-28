# Deploying vikunja

Ordered runbook for the first deploy. Steps 1–3 are prerequisites: the stack fails its first
`up` if any is skipped. See [README](./README.md) for what the stack is and why it departs
from the template.

Target: `littlebuddy`, published on `127.0.0.1:18026`.

## 1. Merge to main

The Komodo resource sync (`Global Sync`) reads `files/komodo_config/sync.toml` from the
`forgejo_infra.stacks` linked repo, so the stack does not exist as a Komodo resource until
the entry is on `main`.

## 2. Store the secrets in Infisical

Project **apps**, environment **prod**, folder **`/vikunja`**. Three keys, stored under
exactly the names the containers read — the provider injects values, it never renames them:

| Key | Read by | Value |
| --- | --- | --- |
| `POSTGRES_PASSWORD` | `db` | generate once |
| `VIKUNJA_DATABASE_PASSWORD` | `app` | **the same value as `POSTGRES_PASSWORD`** |
| `VIKUNJA_SERVICE_SECRET` | `app` | generate separately |

```bash
openssl rand -base64 32   # run twice: once for the DB password, once for the service secret
```

`VIKUNJA_SERVICE_SECRET` signs JWTs. Leave it out and Vikunja generates a fresh one on every
start, so every session dies on restart — it is a real secret, not a nicety.

The DB password is stored twice on purpose. Postgres reads it as `POSTGRES_PASSWORD`, Vikunja
as `VIKUNJA_DATABASE_PASSWORD`, and there is no compose-level interpolation left to bridge the
two names.

**Store all three before the first deploy.** Postgres initialises its data directory on first
start; if it comes up without a password the volume has to be destroyed to fix it (see
[Rollback](#rollback)).

## 3. Run the Komodo sync

In Komodo, execute **Global Sync**. It creates the `vikunja` stack resource from the
`[[stack]]` entry. Confirm it appears with server `littlebuddy` before deploying.

## 4. Deploy

Deploy the `vikunja` stack from Komodo. Never `docker compose` it by hand.

`pre_deploy` runs first and is load-bearing:

```bash
mkdir -p /srv/docker/bind-mounts/apps/vikunja/files
chown 1000 /srv/docker/bind-mounts/apps/vikunja/files
```

The image is `FROM scratch` with `USER 1000` and never creates that directory, so without the
`chown` every attachment upload fails with a permission error while the rest of the app looks
healthy. This is the repo's first real use of `pre_deploy.command` — read the deploy log and
confirm both commands ran.

## 5. Verify

On `littlebuddy`:

```bash
docker ps --filter name=vikunja           # vikunja-app and vikunja-db both up
docker logs vikunja-app | head -40        # migrations ran, no database auth errors
curl -fsS http://127.0.0.1:18026/api/v1/info
```

`/api/v1/info` returns JSON including the version. The app service carries **no** healthcheck —
the `scratch` image ships no shell, curl or wget — so `docker ps` showing "healthy" is only
ever `vikunja-db`. Curl from the host is the check.

Confirm the bind mount is writable by the app's uid:

```bash
stat -c '%u %n' /srv/docker/bind-mounts/apps/vikunja/files   # must print: 1000 ...
```

## 6. Publish it

The route is not in this repo — per-app resources are created in the Pangolin dashboard on
`rick`, the same as paperless and docuseal. Add a resource for
`vikunja.ktbinternal.com` targeting `littlebuddy:18026` over the site connector. Pangolin
already holds the `*.ktbinternal.com` wildcard, so no cert work is needed.

`VIKUNJA_SERVICE_PUBLICURL` is already set to `https://vikunja.ktbinternal.com`. It has to
match the hostname you actually serve on, or the frontend calls the wrong API origin.

## 7. Create the account, then close registration

Registration ships **on** so the first account can be made through the UI — Vikunja has no
invite flow, so there is no other way in.

1. Open `https://vikunja.ktbinternal.com`, register.
2. Set `VIKUNJA_SERVICE_ENABLEREGISTRATION: 'false'` in `stack.jsonnet`.
3. `mise run render`, commit, merge, re-run the sync, redeploy.

Leaving it `'true'` leaves the instance self-serve to anyone who reaches the hostname.

## 8. Connect iOS

The official Vikunja iOS app has no Kanban view yet.
[mDone](https://apps.apple.com/us/app/mdone/id6760613430) (free; iPhone, iPad, Mac) does. Point
it at `https://vikunja.ktbinternal.com` — reachable over the tailnet — and log in with the
account from step 7.

## Rollback

```bash
docker compose -p vikunja down          # via Komodo's Destroy
docker volume rm vikunja_db             # DESTROYS all tasks — only when starting over
```

The `vikunja_db` volume holds every task and project; the bind mount at
`/srv/docker/bind-mounts/apps/vikunja/files` holds attachments. Removing the stack leaves both
in place, which is what makes a re-deploy pick up where it left off — and what makes a
"clean slate" retry need the explicit `volume rm`.

## Known gap

The DB port is not published, so `databasus` on `rick` cannot back this up. If the trial
sticks, publish `5432` on loopback, add a `serviceGroup` entry to `src/registry.libsonnet`, and
wire it into the backup stack.
