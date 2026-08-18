// What docker compose discovers. The include is where env_file goes: `${VAR:?err}` inside
// services.yaml resolves from it, which a service-level env_file cannot do — that only
// reaches the container's environment, never the compose document.
(import 'refs.libsonnet').compose
