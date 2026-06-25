# komodo-periphery

> 📚 The Komodo orchestration model (Core + Mongo on `littlebuddy`, a per-host Periphery agent on every host, tier-0 bootstrap order) lives in Notion → **[Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c)**. This file covers only `stack.node/komodo-periphery`: how to run it and its quirks.

The standalone Komodo Periphery agent. One instance runs on **every** host (deployed by `infra.ansible`, like Traefik and the Infisical agent) so Komodo Core can manage that host's Docker. It was previously bundled into `stack.infra/komodo` behind a compose profile; it now lives here because it is a per-host node concern.

- **No profiles** — `docker compose up` brings up the single `komodo-periphery` service.
- **No secrets to start** — it authenticates Komodo Core by PKI (`PERIPHERY_CORE_PUBLIC_KEYS` in `container-envs/periphery.env`, not a secret).
- `KOMO_VERS` (in `interpolation-envs/general.env`) must be kept in sync with `stack.infra/komodo` — Core and Periphery run matching upstream image versions.

> How Komodo Core addresses each host's periphery (the `https://<host-tailscale-ip>:8120` convention, including the same-host case on `littlebuddy`) is an architecture/SOP concern — see Notion → **[Architecture — How It All Connects](https://app.notion.com/p/37931e9a948a819380e7e9ef7d90cf8c)** and the from-scratch bootstrap SOP.
