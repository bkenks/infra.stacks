# Frappe custom image

This directory defines the **custom Frappe image** that the `frappe` stack runs. It is built by GitHub Actions and pushed to GHCR; Komodo only ever *pulls* it.

> 📚 The general homelab image-supply pattern (CI → GHCR → Komodo pulls, moving vs immutable tags, BuildKit secrets, Docker immutability) lives in Notion → [Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c). Below is the **Frappe-specific** detail.

## What's in the image

The Frappe framework (added at build time via `FRAPPE_BRANCH`) plus every app listed in [`apps.json`](apps.json):

| App | Repo | Pin | Why |
| --- | --- | --- | --- |
| Frappe | frappe/frappe | `version-15` (`FRAPPE_BRANCH`) | the framework (base layer, not in apps.json) |
| ERPNext | frappe/erpnext | `version-15` | the ERP suite (includes the built-in CRM module) |
| Frappe HR | frappe/hrms | `version-15` | HR / payroll module |
| Frappe CRM | frappe/crm | `v1.73.0` (tag) | standalone modern CRM SPA at `/crm` |

> **Why Frappe CRM is pinned to a release tag, not a `version-15` branch:** it doesn't follow the `version-N` branch scheme — it ships `v1.x` release tags off `main`. The v1.x line is the stable line compatible with Frappe v15 & v16 (`frappe >=15.0.0,<17.0.0`). The moving `main` HEAD has been bumped to require Frappe **>=16.0.0-dev**, so tracking `main` would fail bench's dependency check on our v15 base. Bump this tag deliberately when upgrading CRM.

**The apps are baked in; they are not all installed everywhere.** Which apps a given site runs is chosen per-site at creation time:

```sh
bench new-site site-a.com --install-app erpnext              # ERP only
bench new-site site-b.com --install-app erpnext --install-app hrms   # ERP + HR
bench new-site site-c.com --install-app erpnext --install-app crm    # ERP + modern CRM
bench new-site site-d.com --install-app crm                  # standalone CRM only
```

## Adding an app / module (e.g. a custom whitelabel app later)

1. Add an entry to `apps.json` (a git repo URL + branch). Private repos: use a tokenised URL — it is passed as a BuildKit **secret**, never baked into a layer.
2. Commit + push. The workflow rebuilds and publishes a new image.
3. Redeploy the stack in Komodo, then run `bench --site <site> install-app <app>` and `bench --site <site> migrate` for any site that should use the new app.

> Apps **cannot** be added to a running production image ("Docker immutability"). Adding an app always means: edit `apps.json` → rebuild → redeploy.

## How the build works

`.github/workflows/frappe-image.yml` (at the repo root) clones `frappe/frappe_docker`, drops this `apps.json` in as a BuildKit secret, and builds `images/layered/Containerfile`, tagging:

- `ghcr.io/ktbgroup-self-hosted/frappe:version-15` (moving)
- `ghcr.io/ktbgroup-self-hosted/frappe:version-15-<commit-sha>` (immutable)

`CACHE_BUST` is set to the commit SHA so a changed `apps.json` always triggers a real rebuild (BuildKit secrets are not part of the layer cache key, so without this an app change could be silently cached — see frappe_docker "Automated Builds" docs).

To pin production to an exact build, set `FRAPPE__IMAGE_TAG` in `../interpolation-envs/production.env` to the immutable `version-15-<sha>` tag.
