# komodo-periphery
Standalone Komodo Periphery agent — one instance runs on **every** host (deployed by `infra.ansible`) so Komodo Core can manage that host's Docker.

## Deploy
- No secrets to start — authenticates Core via PKI (`PERIPHERY_CORE_PUBLIC_KEYS` in `container-envs/periphery.env`).
- `KOMO_VERS` (`interpolation-envs/general.env`) must stay in sync with `stack.infra/komodo`'s image version.
