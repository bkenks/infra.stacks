# cloudflared

> 📚 The edge/ingress model (per-host Traefik + Cloudflare Tunnel, wildcard TLS, the secrets-flow) lives in Notion → **[Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c)**. This file covers only `stack.node/cloudflared`: how to run it and its quirks.

Per-host Cloudflare Tunnel connector. It joins this host's local `proxy` bridge network and routes public ingress to that host's Traefik (`https://traefik:443`). Because `proxy` is a per-host bridge (not a swarm overlay) and each host's Traefik only knows its own containers, public ingress to a service requires a connector on the **same host** as that service — hence this is a per-host node stack, not a central singleton.

> ⚠️ **Per-host tunnel caveat:** running one connector per host with hostname-based routing means you cannot use replicas of a single tunnel (Cloudflare round-robins replicas of the same tunnel, which would send a host's hostnames to the wrong connector). Per-host ingress needs a **tunnel/token per host**, with each host's hostnames mapped to that host's connector. `CLOUDFLARE_TUNNEL_TOKEN` is rendered to `/dev/shm/cloudflared-bootstrap.env` by the Infisical agent — per-host means a per-host token in Infisical.
