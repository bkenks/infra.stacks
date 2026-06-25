# databasus

> 📚 The database topology and backup flow (per-host databases, NAS → B2 offsite) lives in Notion → **[Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c)**. This file covers only `stack.node/databasus`: how to run it and its quirks.

Per-host database backup/admin tool. It backs up this host's databases to the NAS (which then replicates to Backblaze B2). It is a **per-host** stack — and must be, for two reasons:

1. **Network locality (hard constraint):** it joins host-local Docker bridge networks (`postgres-<env>_postgres`, `paperless-<env>-net`, …) by name. Docker bridge networks do not span hosts, so a single central instance physically cannot see databases on other hosts.
2. **Backup resilience:** per-host means each host backs up independently — the control plane (littlebuddy) going down does not stop the other hosts' backups.

## Access (direct IP)

Reached **directly by host / Tailscale IP** (e.g. `http://100.114.137.104:4005`) — databasus no longer uses Traefik. The web UI port (`4005`) is published on the host; reach it at `<host-ip>:4005` over Tailscale, MagicDNS, or the LAN.

### Per-host deploy (Komodo)

No per-server variable is needed — the stack is now identical on every host (it just publishes port `4005`). Deploy it to each host as-is.

The config + DB volume (`databasus_data`) is a **project-scoped managed volume** — it self-creates per host, so a new host needs no pre-existing external volume. On littlebuddy it resolves to the same name as the prior external volume (`databasus-production_databasus_data`), so existing data is adopted in place, not recreated.

> ⚠️ **Backup coverage per host is still a follow-up.** As shipped, the service joins only `default` and `db-backups` — it does **not** yet attach to any host's database bridge networks (`postgres-<env>_postgres`, `paperless-<env>-net`, …). To actually back up a host's databases, add that host's DB networks (as `external`) to the `databasus` service — and that set differs per host. Standing the stack up (running + reachable on `<host-ip>:4005`) does not require this; backing up real databases does.

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
