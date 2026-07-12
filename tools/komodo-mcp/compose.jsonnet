// komodo-mcp: exposes Komodo to MCP clients (Claude Code) via Traefik, guarded by
// basic-auth — the MCP endpoint has no auth of its own and the configured key is full read/write.
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';
local secrets = reg.infisical.services;

local stack = 'komodo-mcp';
local s = c.stack(stack);
local n = s.names;
local app = reg.roles.app;

// Pinned to upstream release tag v1.4.1 — verify it exists on the mirror before deploying.
local version = '1.4.1';
local port = 8000;

// basicauth has no lib.mixins helper; labels written manually, merged with proxyAdd + komodoSkip below.
local authLabels = {
  'traefik.http.middlewares.komodo-mcp-auth.basicauth.users': '${KOMODO_MCP_BASICAUTH_USERS:?err}',
  'traefik.http.routers.komodo-mcp.middlewares': 'komodo-mcp-auth',
};

local manifest = {
  name: stack,

  services: {
    [app]: {
      image: 'fj.' + reg.domains.ktbinternal + '/bkenks/komodo-mcp-server:' + version,
      container_name: n.container(app),
      environment: {
        // Streamable HTTP transport (listens on :8000 inside the container).
        MCP_TRANSPORT: 'http',
        KOMODO_URL: 'https://komo.' + reg.domains.ktbinternal,
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
      networks: {
        // default net unused (no peers) but kept for parity with the pre-jsonnet stack.
        default: { aliases: [n.container(app)] },
        [reg.sharedNetworks.proxy.name]: { aliases: [n.container(app)] },
      },
      labels: s.proxy.add('komodo-mcp', 'komodo-mcp', port) + authLabels + s.komodoSkip,
    },
  },

  networks:
    s.network.default
    + s.network.join(reg.sharedNetworks.proxy),
};

c.render(stack, manifest, [secrets['komodo-mcp'].path])
