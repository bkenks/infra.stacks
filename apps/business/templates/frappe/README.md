# frappe — ERPNext / Frappe, multi-site, whitelabel

[Frappe](https://frappeframework.com/) + ERPNext + Frappe HR, single bench, multi-site (DNS-based multitenancy) — each site is its own MariaDB database on the shared `sites` volume, with apps chosen per-site at creation. Reached at `business.stackform.app` (and per-site hostnames) via Traefik → port 8080. Custom image built from [`image/apps.json`](image/apps.json) (see `image/README.md`).

Source of truth: `compose.jsonnet` — don't edit the generated YAML (renders both `compose.yaml` and `compose.stack.yaml`).

## Deploy

Deployed via Komodo. Infisical `/frappe` (`FRAPPE_DB_ROOT_PASSWORD`) → `/dev/shm/frappe.env`, injected into both `db` and `backend` (root password only used for site create/drop). Must be set *before* the first `up`, or `${FRAPPE_DB_ROOT_PASSWORD:?err}` aborts the deploy.

First deploy: build the image, set the Traefik `Host()` rule in `compose.jsonnet` for the first site, deploy, then create the site (site name must equal its domain — Frappe routes by Host header):
```bash
bench new-site <domain> --mariadb-user-host-login-scope='%' \
  --db-root-password "$FRAPPE_DB_ROOT_PASSWORD" --install-app erpnext
```
`--mariadb-user-host-login-scope='%'` is required or DB connections break after a container restart.

### Gotchas
- `configurator` writes `common_site_config.json` first; every other service depends on it — check it first when debugging.
- Traefik's rule must OR every site's hostname, or unlisted sites 404.
- Never expose the websocket to Traefik — nginx already splits `/socket.io` to `frappe-websocket:9000`.
- Apps (ERPNext, HR, CRM) are baked in at image build time; `install-app` only activates what's already in `image/apps.json`.
- Frappe runs as UID 1000 — manually restored files need `chown 1000`.
