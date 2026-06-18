# databasus

> 📚 The database topology and backup flow (per-host databases, NAS → B2 offsite) lives in Notion → **[Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c)**. This file covers only `stack.node/databasus`: how to run it and its quirks.

Per-host database backup/admin tool. It backs up this host's databases to the NAS (which then replicates to Backblaze B2). It is a **per-host** stack — and must be, for two reasons:

1. **Network locality (hard constraint):** it joins host-local Docker bridge networks (`postgres-<env>_postgres`, `paperless-<env>-net`, …) by name. Docker bridge networks do not span hosts, so a single central instance physically cannot see databases on other hosts.
2. **Backup resilience:** per-host means each host backs up independently — the control plane (littlebuddy) going down does not stop the other hosts' backups.

## Access (Traefik)

Reached at `https://databasus.<host>.homektb.com` (per-host **dotted** scheme — the host token is `lilbud` / `maboi` / `paiki`), served by that host's `*.<host>.homektb.com` wildcard cert. No host port is published — databasus joins the shared `proxy` network and Traefik fronts the web UI (internal port `4005`) on `websecure` with `tls: true`. This mirrors `zerobyte`.

> **Per-host routing scheme.** Each host runs its own Traefik that only sees its
> own containers — Traefik never routes cross-host. Every internal service is
> reached at `<service>.<host>.homektb.com`, which gives each host its own
> namespace so routing is unambiguous and adding services needs no DNS change:
> - **DNS (AdGuard Home → DNS Rewrites page):** one native wildcard per host,
>   `*.<host>.homektb.com → <host-tailscale-ip>` (e.g. `*.paiki.homektb.com`).
>   These are real leftmost-label wildcards, so the simple Rewrites page handles
>   them. On littlebuddy the legacy `*.homektb.com` catch-all already resolves
>   `*.lilbud.homektb.com` to the right box, so littlebuddy needs no new rewrite.
> - **TLS:** each host's Traefik requests a `*.<host>.homektb.com` wildcard
>   (added as a SAN in `stack.node/traefik/files/configs/<host>.yml`). A two-label
>   name is **not** covered by `*.homektb.com`, so this per-host wildcard cert is
>   required — issued the same way (Cloudflare DNS-01), no new token scope (the
>   `_acme-challenge.<host>.homektb.com` TXT lives in the existing homektb.com zone).

### Per-host deploy (Komodo)

Set one **per-server variable** when deploying to each host:

| Variable          | Value                 | Notes                                                              |
|-------------------|-----------------------|--------------------------------------------------------------------|
| `DATABASUS__HOST` | the host's dotted token | `lilbud` / `maboi` / `paiki` — sets the router host `databasus.<token>.homektb.com`. (littlebuddy's token is `lilbud`, not `littlebuddy`.) Guarded `:?err` so a deploy fails fast if it's missing (mirrors `zerobyte`'s `ZEROBYTE__HOST` and traefik's `AGENT_HOST`). |

The config + DB volume (`databasus_data`) is a **project-scoped managed volume** — it self-creates per host, so a new host needs no pre-existing external volume. On littlebuddy it resolves to the same name as the prior external volume (`databasus-production_databasus_data`), so existing data is adopted in place, not recreated.

> ⚠️ **Backup coverage per host is still a follow-up.** As shipped, the service joins only `default`, `db-backup-shared`, and `proxy` — it does **not** yet attach to any host's database bridge networks (`postgres-<env>_postgres`, `paperless-<env>-net`, …). To actually back up a host's databases, add that host's DB networks (as `external`) to the `databasus` service — and that set differs per host. Standing the stack up (running + reachable via Traefik) does not require this; backing up real databases does.

> ⚠️ **Fresh-volume init bug (image pinned by digest — the `3.42.0` build).** `databasus`'s `start.sh`
> runs Postgres as uid **999** (`PUID=${PUID:-999}`), but the image ships a
> pre-baked `/databasus-data/pgdata` owned by uid **101** with a POSIX ACL. A
> **fresh** volume copies that 101-owned/ACL'd dir, so `initdb` (as 999) hits
> `Permission denied` and the container crash-loops. Hosts that already hold a
> valid cluster are unaffected (start.sh sees `PG_VERSION` and skips init), which
> is why this only bit a host doing a first-time init. If you ever wipe a host's
> `databasus_data` volume, recreate `pgdata` clean before first boot:
> `rm -rf <vol>/_data/pgdata && install -d -m700 <vol>/_data/pgdata && chown 999:999 <vol>/_data/pgdata && setfacl -b <vol>/_data/pgdata`,
> and make sure `<vol>/_data` is `0755` (postgres's gid 999 must be able to
> traverse it). The image is **pinned** so the behaviour can't shift silently;
> revisit when upstream fixes it.
