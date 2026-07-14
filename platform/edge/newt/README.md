# newt
Pangolin **site** connector ([`fosrl/newt`](https://github.com/fosrl/newt)) — dials out to the Pangolin control server (`PANGOLIN_ENDPOINT=https://pangolin.ktbcloud.com`), registers this host as a site, and forwards inbound tunnel traffic to the host's Traefik. Joins `shared-proxy`, same shape as [`cloudflared`](../cloudflared/README.md).

## Deploy
- Secrets: Infisical project **infra**, per-host folder `/hosts/<host>/newt` (`NEWT_ID`, `NEWT_SECRET`, from Pangolin → Sites → create site) → `/dev/shm/newt.env`. See `.env.example`.
- Add `newt` to that host's `infisical-agent_<host>` stack's `AGENT_SERVICES`.
- Host must own `shared-proxy` (i.e. run `platform/edge/traefik`). Do **not** run on the dedicated Pangolin VPS (`platform/edge/pangolin` already terminates ingress there).
- Image pinned to `fosrl/newt:1.14.0` (`version` local in `compose.jsonnet`) — bump there and re-render, don't edit the YAML.
