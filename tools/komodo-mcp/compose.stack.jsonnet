// komodo-mcp — MP-Tool's Komodo MCP Server: exposes Komodo (servers, stacks,
// deployments, builds, repos, procedures, terminals, ...) to MCP clients like
// Claude Code. Streamable-HTTP via Traefik,
// guarded by basic-auth (the MCP endpoint itself has no built-in auth and the
// configured Komodo key is full read/write).
//
// Source of truth: this file compiles to compose.stack.yaml — do not edit the
// YAML. Joins shared-proxy (traefik owns) to be reachable.
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';

local stack = 'komodo-mcp';
local s = c.stack(stack);
local n = s.names;
local app = reg.roles.app;

// Pinned to the MP-Tool/komodo-mcp-server upstream release tag (v1.4.1),
// VERIFY this tag exists
// on the mirror before deploying (see stack README).
local version = '1.4.1';
local port = 8000;

// traefik.http.middlewares.*.basicauth has no lib.mixins helper; write the 2
// labels manually and merge with proxyAdd's output + komodoSkip below.
local authLabels = {
  'traefik.http.middlewares.komodo-mcp-auth.basicauth.users': '${KOMODO_MCP_BASICAUTH_USERS:?err}',
  'traefik.http.routers.komodo-mcp.middlewares': 'komodo-mcp-auth',
};

{
  name: stack,

  services: {
    [app]: {
      image: 'fj' + reg.domains.ktbinternal + '/bkenks/komodo-mcp-server:' + version,
      container_name: n.container(app),
      environment: {
        // Streamable HTTP transport (listens on :8000 inside the container).
        MCP_TRANSPORT: 'http',
        // Komodo Core API endpoint (behind this host's Traefik). Non-secret.
        KOMODO_URL: 'https://komo.' + reg.domains.ktbinternal,
        MCP_ALLOWED_HOSTS: 'komodo-mcp.' + reg.domains.ktbinternal,
        // Behind one reverse proxy (this host's Traefik) — trust the first
        // hop so the server resolves the real client IP from X-Forwarded-*.
        MCP_TRUST_PROXY: '1',
        TZ: 'America/Chicago',
        // Secrets — interpolated from /dev/shm/komodo-mcp.env (parent include.env_file).
        // Komodo service-account credentials, full read/write key.
        KOMODO_API_KEY: '${KOMODO_API_KEY:?err}',
        KOMODO_API_SECRET: '${KOMODO_API_SECRET:?err}',
      },
      restart: 'on-failure:5',
      expose: [std.toString(port)],
      // No `init: true`: the image already runs tini as its entrypoint (PID 1).
      // Adding Docker's init would nest a second tini as a non-PID-1 child,
      // logging "Tini is not running as PID 1" and disabling zombie reaping.
      // Letting the image's own tini stay PID 1 fixes both.
      networks: {
        // Unused (no peers) but kept for parity with the pre-jsonnet stack.
        default: { aliases: [n.container(app)] },
        [reg.sharedNetworks.proxy.name]: { aliases: [n.container(app)] },
      },
      labels: s.proxy.add('komodo-mcp', 'komodo-mcp', port) + authLabels + s.komodoSkip,
    },
  },

  networks:
    s.network.default
    + s.network.join('proxy'),
}
