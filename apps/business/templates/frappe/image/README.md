# Frappe custom image

Custom Frappe image for the `frappe` stack — built by GitHub Actions, pushed to GHCR; Komodo only pulls it.

## Apps baked in ([`apps.json`](apps.json))

| App | Pin | Why |
| --- | --- | --- |
| Frappe | `version-15` (`FRAPPE_BRANCH`) | framework |
| ERPNext | `version-15` | ERP suite (incl. CRM module) |
| Frappe HR | `version-15` | HR / payroll |
| Frappe CRM | `v1.73.0` (tag) | standalone CRM SPA at `/crm` |

Frappe CRM is pinned to a release tag, not `version-15`: its `main` branch requires Frappe >=16, which breaks bench's dependency check against our v15 base. The v1.x tag line is what's compatible with v15. Bump deliberately.

Apps are baked in but not all installed — chosen per site via `bench new-site --install-app`. Adding an app to the catalog means editing `apps.json`, rebuilding, and redeploying (can't be added to a running image). Private repos: use a tokenized URL in `apps.json` — passed as a BuildKit secret, never baked into a layer.

## Build

`.github/workflows/frappe-image.yml` builds `frappe_docker`'s `images/layered/Containerfile` with `apps.json` as a BuildKit secret, tagging `version-15` (moving) and `version-15-<sha>` (immutable). `CACHE_BUST` is set to the commit SHA so a changed `apps.json` always triggers a real rebuild — BuildKit secrets aren't part of the layer cache key.

Pin production to an exact build via `FRAPPE__IMAGE_TAG` in `../interpolation-envs/production.env`.
