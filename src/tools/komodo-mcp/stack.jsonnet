// komodo-mcp: exposes Komodo to MCP clients (Claude Code) via Traefik, guarded by
// basic-auth — the MCP endpoint has no auth of its own and the configured key is full
// read/write.
local lib = import 'lib.libsonnet';
local refs = lib.Project {
  name:: 'komodo-mcp',

  app:: self.Service { role:: lib.collections.role.APP },
};

// Pinned to upstream release tag v1.4.1 — verify it exists on the mirror before deploying.
local version = '1.4.1';
local port = '8000';

{
  compose: {
    name: refs.name,
    networks: { default: { name: refs.name } },

    services: {
      [lib.collections.role.SECRETS]: lib.SecretsProvider('komodoMcp'),

      [refs.app.key]: {
        container_name: refs.app.ext,
        image: 'fj.%s/bkenks/komodo-mcp-server:%s' % [lib.collections.domain.ktbcloud, version],
        restart: lib.collections.restart.onFailure(5),
        depends_on: lib.secretsReady,
        // KOMODO_URL arrives from infisical-secrets, stored whole: the provider injects
        // values, so there is no compose-level interpolation left to join a scheme to an
        // FQDN. KOMODO_API_KEY and KOMODO_API_SECRET are the full read/write service-account
        // credentials and come from the same bundle.
        environment: {
          // Streamable HTTP transport (listens on :8000 inside the container).
          MCP_TRANSPORT: 'http',
          MCP_ALLOWED_HOSTS: refs.name + '.' + lib.collections.domain.ktbinternal,
          // Trust the first hop (this host's Traefik) to resolve the real client IP from
          // X-Forwarded-*.
          MCP_TRUST_PROXY: '1',
          TZ: 'America/Chicago',
        },
        expose: [port],
        ports: ['%s:18007:%s' % [lib.collections.ip.loopback, port]],
        // No `init: true`: the image's own tini is already PID 1; Docker's init would nest a
        // second tini as a non-PID-1 child and break zombie reaping.
        labels: lib.collections.labels.komodoSkip,
      },
    },
  },
}
