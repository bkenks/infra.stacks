// komodo-mcp: exposes Komodo to MCP clients (Claude Code) via Traefik, guarded by
// basic-auth — the MCP endpoint has no auth of its own and the configured key is full read/write.
local lib = import 'lib.libsonnet';
local reg = lib.registry;
local role = reg.role;

local name = 'komodo-mcp';
// Pinned to upstream release tag v1.4.1 — verify it exists on the mirror before deploying.
local version = '1.4.1';
local port = 8000;

lib.render(
  name,
  lib.Stack(name, function(ref) {
    [role.APP]: lib.Service {
      image: 'fj.' + reg.domains.ktbcloud + '/bkenks/komodo-mcp-server:' + version,
      environment: {
        // Streamable HTTP transport (listens on :8000 inside the container).
        MCP_TRANSPORT: 'http',
        KOMODO_URL: '${HTTP_SCHEME:?must enter http scheme}://${KOMODO_FQDN:?must enter FQDN for Komodo}',
        MCP_ALLOWED_HOSTS: 'komodo-mcp.' + reg.domains.ktbinternal,
        // Trust the first hop (this host's Traefik) to resolve the real client IP from X-Forwarded-*.
        MCP_TRUST_PROXY: '1',
        TZ: 'America/Chicago',
        // Secrets from /dev/shm/komodo-mcp.env — full read/write Komodo service-account key.
        KOMODO_API_KEY: '${KOMODO_API_KEY:?err}',
        KOMODO_API_SECRET: '${KOMODO_API_SECRET:?err}',
      },
      restart: 'on-failure:5',
      expose: [std.toString(port)],
      // No `init: true`: image's own tini is already PID 1; adding Docker's init would nest a
      // second tini as a non-PID-1 child and break zombie reaping.
      labels: lib.komodoSkip,
      ports: ['%s:18007:%s' % [reg.ips.loopback, port]],
    },
  }),
  [lib.Secret('komodo-mcp')],
)
