# ERPNext / Frappe — multi-site, whitelabel

> 📚 System architecture, the secrets-flow, and the CI→GHCR→Komodo image-supply model live in Notion → [Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c). This file covers only the frappe stack: how to deploy/use it and its quirks.

Single bench, many sites (DNS-based multitenancy). One custom image (Frappe +
ERPNext + Frappe HR, built from [`image/apps.json`](image/apps.json)) runs every
Frappe process; each tenant is its own MariaDB database + a directory on the
shared `sites` volume. Apps are baked into the image but chosen **per site** at
creation time, so one site can be ERP-only, another ERP + HR, another bare Frappe.

Reverse proxy is the host's Traefik stack (`stack.node/traefik`); only `frontend`
joins the `proxy` network. Deploy Traefik on the host **before** this stack.

## Layout

| Path | What |
| --- | --- |
| `docker-compose.yml` | include-wrapper (compose/ + interpolation-envs/) |
| `compose/stack.yml` | all services, networks, volumes, Traefik labels |
| `compose/secrets.yml` | interpolated secrets (DB root password) |
| `container-envs/*.env` | literal, non-secret container env |
| `interpolation-envs/general.env` | names, image ref, `FRAPPE__SITES_RULE` |
| `interpolation-envs/production.env` | version pins (image tag, MariaDB, Redis) |
| `image/apps.json` + `image/README.md` | what's in the custom image + how it builds |

## Secrets (Infisical Agent)

Secrets are delivered by the **Infisical agent**, not `infisical run`. How the
agent renders a stack's secrets → Notion: [Bootstrapping a Host from Scratch —
Tier-0 Ordering](https://app.notion.com/p/37931e9a948a8124ad6de974216d93cd) (the
Infisical agent secrets-flow).

This stack's specifics — one key, stored in Infisical under the **`/frappe`**
folder (**`prod`** env), rendered to `/dev/shm/biz-ops_frappe.env` and pulled into
`docker-compose.yml` via `include: -> env_file:`:

| Key | Use |
| --- | --- |
| `FRAPPE_DB_ROOT_PASSWORD` | MariaDB root password (container + `bench new-site`) |

**Deploy ordering:** the Infisical agent must be running and the `/frappe` secret
set in Infisical *before* this stack's `up`, or the `/dev/shm` file won't exist
and `${FRAPPE_DB_ROOT_PASSWORD:?err}` aborts the deploy.

> **`bench new-site`:** the root password is injected into **both** the `db` and
> `backend` containers (see `compose/secrets.yml`), so `bench new-site
> --db-root-password "$FRAPPE_DB_ROOT_PASSWORD"` run via exec on `backend` works
> directly. Trade-off: the root password lives in backend's long-running env
> (visible to `docker inspect`), not just transiently at exec. Day-to-day site
> operation doesn't need root — each site uses its own per-site DB user — so root
> is only used for create/drop.

## Apps: two layers (image vs site)

"Install an app" means two different things at two different layers. This is the
single most common point of confusion, so be precise:

| | `image/apps.json` (build time) | `bench new-site --install-app` (per site) |
| --- | --- | --- |
| **When** | when the **image is built** (GitHub Action) | when you **create each site** |
| **Scope** | the whole image — every site shares it | just that **one site's** database |
| **Does** | downloads the app's **code** into the image | creates the app's **tables** in that site |
| **Analogy** | installing software on a computer | adding it to one user's account |

- `apps.json` makes an app **available**; it does not put it into any site.
- `--install-app` **activates** an available app in one site's database; it cannot
  install code that isn't already in the image.
- **Hard rule:** you can only `--install-app` something that's already in `apps.json`.

So the image is the *menu* (ERPNext + Frappe HR + Frappe CRM are all baked in);
each site *orders* its subset:

```sh
bench new-site acme.com  --install-app erpnext --install-app hrms   # ERP + HR
bench new-site bobco.com --install-app erpnext --install-app crm    # ERP + modern CRM
bench new-site solo.com  --install-app crm                          # standalone CRM only
bench new-site bare.com                                             # bare Frappe
```

All three run off the **same image and bench**. `bobco.com` has no HR even though
the HR code sits in the image — because it was never installed into that site's DB.

Consequences:

- **New app for the catalog** (a custom whitelabel app, `payments`, etc.) → edit
  `apps.json` → rebuild → redeploy. Only then can any site install it.
- **Give an existing client an app already in the image** → no rebuild:
  `bench --site bobco.com install-app hrms && bench --site bobco.com migrate`.
- **Remove an app from one client** → `bench --site bobco.com uninstall-app hrms`;
  the code stays in the image for everyone else.

## One-time bring-up

1. **Build the image first.** Push any change to `image/apps.json` (or run the
   *Build Frappe image* GitHub Action manually). It publishes
   `ghcr.io/ktbgroup-self-hosted/frappe:version-15`. If GHCR packages are private,
   the host's Docker must be logged in to GHCR (or make the package public).
2. **Set `FRAPPE_DB_ROOT_PASSWORD`** in Infisical for this stack.
3. **Set `FRAPPE__SITES_RULE`** in `interpolation-envs/general.env` to your first
   site, e.g. ``Host(`erp.homektb.com`)``. Commit + push.
4. **Deploy in Komodo.** Watch `configurator` run to completion (it writes
   `common_site_config.json`), then the rest start.
5. **Create the first site** (see below).
6. **DNS**: point the site's hostname at this host.

## Create a site (tenant onboarding)

Run via Komodo exec on the **backend** container. The site name MUST equal the
domain it will be served on — Frappe routes by Host header.

```sh
# ERP + modern CRM, for example:
bench new-site client-a.com \
  --mariadb-user-host-login-scope='%' \
  --db-root-password "$FRAPPE_DB_ROOT_PASSWORD" \
  --admin-password 'CHANGE_ME' \
  --install-app erpnext \
  --install-app crm

# Pick apps per site:
#   --install-app erpnext                      -> ERP only (incl. built-in CRM module)
#   --install-app erpnext --install-app hrms   -> ERP + HR
#   --install-app erpnext --install-app crm    -> ERP + modern CRM SPA (/crm)
#   --install-app crm                          -> standalone CRM only
#   (omit --install-app)                       -> bare Frappe
```

`--mariadb-user-host-login-scope='%'` lets the per-site DB user connect from any
Docker IP — required, or DB connections break after a container restart.

Then:

1. Add ``Host(`client-a.com`)`` to `FRAPPE__SITES_RULE` in
   `interpolation-envs/general.env` (`A || B || C`). Commit + push.
2. Redeploy in Komodo — only `frontend`'s label changes; DB/workers keep running.
3. Point `client-a.com` DNS at this host.
4. Log in at `https://client-a.com` as `Administrator` and run the setup wizard.

## Whitelabel a site

Allowed: ERPNext/HR are GPLv3 — rebranding the UI is fine; you just can't claim
authorship or relicense the source. No custom app needed for the basics (run via
backend exec or the desk UI):

```sh
# App name in titles / browser tab:
bench --site client-a.com set-config app_name "Acme ERP"

# Website Settings (logo, navbar brand, footer) via the API:
bench --site client-a.com execute frappe.client.set_value \
  --kwargs '{"doctype":"Website Settings","name":"Website Settings","fieldname":"brand_html","value":"Acme ERP"}'
```

Logo upload, custom CSS to hide any residual "ERPNext"/"Frappe" strings, and login
page settings live under **Setup → Website Settings** in the desk. Removing the
desk wordmark at the JS level or replacing the login template needs a small custom
Frappe app — add it to `image/apps.json` later (see `image/README.md`).

## Backups

Don't rely on remembering a command — create a **Komodo scheduled job** that runs,
on the backend container:

```sh
bench --site all backup --with-files
```

Backups land in `sites/<site>/private/backups/` (inside the `sites` volume). For
off-host copies, push them to object storage (frappe_docker `push_backup.py`) or
snapshot the volume.

## Upgrades

1. Bump the branch in `image/apps.json` (and `FRAPPE_BRANCH` in the workflow) if
   doing a major version jump; otherwise just re-run the build to pull app updates.
2. Update `FRAPPE__IMAGE_TAG` in `interpolation-envs/production.env` to the new
   immutable `version-15-<sha>` tag. Commit + push.
3. Redeploy in Komodo, then on the backend container:

   ```sh
   bench --site all set-maintenance-mode on
   bench --site all migrate
   bench --site all set-maintenance-mode off
   ```

   Migrations are required after any image/app change or the sites can break.

## Drop a site

```sh
# Back up first:
bench --site client-a.com backup --with-files
bench drop-site client-a.com \
  --db-root-password "$FRAPPE_DB_ROOT_PASSWORD" \
  --archived-sites-path archived-sites
```

Then remove its `Host()` clause from `FRAPPE__SITES_RULE` and redeploy.

## When to give a client their own stack

Default is one shared bench. Graduate a client to a dedicated copy of this stack
(`stack.biz-ops/frappe-<client>/`) when they need a different version, an SLA with
dedicated resources, data residency/compliance isolation, or their bulk jobs are
starving other tenants' queue workers.

## Gotchas

- **`configurator` is the foundation** — it writes `common_site_config.json`
  (db + redis wiring) to the `sites` volume; every other service reads it. If it
  fails (bad `FRAPPE_DB_ROOT_PASSWORD`, db not healthy), everything fails. Check
  it first when debugging.
- **`$$host` vs `$host`** — in `compose/stack.yml` the escaped form would be
  `$$host`; in `container-envs/frontend.env` it's a literal `$host` (env files
  aren't interpolated). Setting it to a fixed site name routes ALL traffic to one
  site.
- **Never expose websocket to Traefik** — nginx splits `/socket.io` to
  `websocket:9000` internally. A second Traefik router breaks realtime for all sites.
- **`FRAPPE__SITES_RULE` must list every site** — Traefik 404s any Host not in the
  rule. Create a site but forget to add + redeploy → it exists but is unreachable.
- **File permissions** — Frappe runs as UID 1000. If you restore files into the
  `sites` volume manually, `chown` to 1000 or Frappe can't read them.
- **Apps are build-time** — you cannot `install-app` an app that isn't in the
  image. Add it to `image/apps.json`, rebuild, redeploy, then install per site.
