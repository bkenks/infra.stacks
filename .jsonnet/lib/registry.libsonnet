// Single source of truth for names that cross stack boundaries.
// Reference by KEY (reg.sharedNetworks.proxy), never raw string — a typo'd key fails at
// compile time; a typo'd string fails silently at runtime (wrong/empty network).

{
  secretDir: '/dev/shm',
  loopbackIp: '127.0.0.1',

  composeFiles: {
    parent: 'compose.yaml',
    child:  'compose.stack.yaml',
  },

  server: {
    
    dir: {
      docker: {
        root:       '/srv/docker',
        bindmounts: '/bind-mounts',
      },
    },
    # Every host on the network, keyed by short name. `ip` is the Tailscale address — the
    # controller's contract, it routes over the tailnet. `lan`/`public` are additional
    # addresses served for DNS; `dns` overrides the key when the DNS name differs from it;
    # `aka` are extra aliases; `edge: true` marks hosts running Traefik that the controller
    # builds a re-encrypt backend for. dnsmasq (platform/edge/dnsmasq) renders its hosts
    # file from this map, so a host add/rename/re-IP flows to LAN DNS on re-render.
    hosts: {
      # ── Main cluster (LAN 192.168.30.x + Tailscale) ──
      snaszy: { ip: '100.91.182.94', lan: '192.168.30.20', aka: ['nas'] },
      littlebuddy: { ip: '100.114.137.104', lan: '192.168.30.21', aka: ['controlplane'], edge: true },
      paiki: { ip: '100.126.19.103', lan: '192.168.30.22', dns: 'plexyandiknowit', aka: ['plex'], edge: true },
      biggy: { ip: '100.108.59.105', lan: '192.168.30.23' },
      bill: { ip: '100.79.7.11', lan: '192.168.30.25', edge: true },
      # ── Off-cluster infra ──
      homeassistant: { ip: '100.113.251.34', lan: '192.168.40.20', aka: ['hass'] },
      # ── VPS (Tailscale + public fallback) ──
      maboi: { ip: '100.97.83.95', public: '178.156.222.232', edge: true },
      rick: { ip: '100.106.170.93', public: '64.177.119.246', edge: true },
      # ── Tailscale only ──
      woody: { ip: '100.74.131.20' },
    },
  },

  ////////////

  domains: {
    homektb:        'homektb.com',
    stackform:      'stackform.app',
    couchpotatoes:  'couchpotatoes.store',
    ktbinternal:    'ktbinternal.com',
    ktbcloud:       'ktbcloud.com',
  },

  ////////////

  roles: { app: 'app', db: 'db', redis: 'redis' },

  ////////////

  sharedNetworks: {

    proxy:
    { name: 'shared-proxy', owner: 'traefik' },
    
    postgres:
    { name: 'shared-postgres', owner: 'postgres' },
    
    dbBackups:
    { name: 'shared-db-backups', owner: 'databasus' },
    
    infisical:
    { name: 'shared-infisical', owner: 'infisical' },
    
    edge:
    { name: 'shared-edge', owner: 'authentik' },
  },

  ////////////

  envFiles: {
    tailscale: '/srv/docker/files/tailscale.env',
  },

  ////////////

  # Service-to-service endpoints (not user-facing). `container`: internal, on a shared net
  # (`network` references sharedNetworks so the dependency compile-checks). `public`: via
  # Traefik at https://<sub>.<domain>.
  endpoints: {

    postgres: {

      container: {
        host:     'postgres-db',
        port:     5432,
        network:  $.sharedNetworks.postgres
      }, 
    },

    infisical: {

      container: {
        host:     'infisical_app',
        port:     8080,
        network:  $.sharedNetworks.infisical
      },

      public: {
        sub:      'infisical',
        domain:   $.domains.ktbinternal
      },
    },

  },

  ////////////

  infisical: {
    projects: {
      apps:           '2f0eb3d1-3e2a-4ce7-8060-5e47ad877e47',
      frappe:         '12ed25dd-c0d2-4a78-9b10-472fc09fe554',
      couchPotatoes:  'fb1dd6a7-3924-415b-b6c3-3071fc93aaae',
      stackform:      '15d61370-a2ec-4993-9bbd-3774a63f7b94',
      infra:          '86324d9b-3dd7-49d4-b252-69228c5ee0c7',
    },
    
    local catalogue = {
      # Catalogue of every stack the Infisical agent can render; services.jsonnet generates
      # one templates/<svc>.yaml fragment per entry, a host opts in via AGENT_SERVICES. Fields:
      #   dest: output filename under /dev/shm/. Reference it as `path` (below), never retype it.
      #   type: dump = whole folder, secret names already match env-var names.
      #         map  = explicit renames via `keys` ({ OUTPUT_ENV_VAR: 'infisical-secret-name' }).
      #         raw  = single secret's raw value (no KEY= prefix) via `key`.
      #   env:  Infisical environment slug; defaults to 'prod' when omitted.
      postgres:
      { project: 'apps', folder: '/postgres', dest: 'postgres.env', type: 'dump' },

      paperless:
      { project: 'apps', folder: '/paperless', dest: 'paperless.env', type: 'dump' },

      docuseal:
      { project: 'apps', folder: '/docuseal', dest: 'docuseal.env', type: 'dump' },

      openproject:
      { project: 'apps', folder: '/openproject', dest: 'openproject.env', type: 'dump' },

      immich:
      { project: 'apps', folder: '/immich', dest: 'immich.env', type: 'dump' },

      stream:
      { project: 'apps', folder: '/stream', dest: 'stream.env', type: 'dump' },

      convertx:
      { project: 'apps', folder: '/convertx', dest: 'convertx.env', type: 'dump' },

      twenty:
      { project: 'apps', folder: '/twenty', dest: 'twenty.env', type: 'dump' },

      pangolin:
      { project: 'apps', folder: '/pangolin', dest: 'pangolin.env', type: 'dump' },

      frappe:
      { project: 'frappe', folder: '/frappe', dest: 'frappe.env', type: 'dump' },

      'couch-potatoes-website':
      { project: 'couchPotatoes', folder: '/website', dest: 'client_couch-potatoes_website.env', type: 'dump' },

      'stackform-website':
      { project: 'stackform', folder: '/website', dest: 'stackform_website.env', type: 'dump' },

      'cloudflare__dns-api-token':
      { project: 'infra', folder: '/traefik', dest: 'cloudflare__dns-api-token.env', type: 'dump' },

      zerobyte:
      { project: 'infra', folder: '/zerobyte', dest: 'zerobyte.env', type: 'dump' },

      infisical:
      { project: 'infra', folder: '/infisical', dest: 'infisical.env', type: 'dump' },

      grist:
      { project: 'infra', folder: '/grist', dest: 'grist.env', type: 'dump' },

      forgejo:
      { project: 'infra', folder: '/forgejo', dest: 'forgejo.env', type: 'dump' },

      gitea:
      { project: 'infra', folder: '/gitea', dest: 'gitea.env', type: 'dump' },

      'komodo-mcp':
      { project: 'infra', folder: '/komodo-mcp', dest: 'komodo-mcp.env', type: 'dump' },

      woodpecker:
      { project: 'infra', folder: '/woodpecker', dest: 'woodpecker.env', type: 'dump' },

      newt:
      { project: 'infra', folder: '/hosts/${AGENT_HOST}/newt', dest: 'newt.env', type: 'dump' },
      
      komodo:
      { project:  'infra', folder: '/komodo', dest: 'komodo_core.env', type: 'dump' },
      
      cloudflared:
      { project:  'infra', folder: '/hosts/${AGENT_HOST}/cloudflared', dest: 'cloudflared.env', type: 'dump' },
      
      databasus:
      { project: 'infra', folder: '/databasus', dest: 'databasus_secret.key', type: 'raw', key: 'SECRET_KEY' },

    },

    # Every service gains two derived paths. services.jsonnet emits `path` as the agent's
    # destination-path and the consuming stack references it as env_file (or a bind mount),
    # so the producer and the consumer cannot disagree about the filename. Retyping the
    # literal is what this prevents: `dest` is not always '<name>.env' (komodo renders
    # komodo_core.env), and is not always an env file (databasus renders a raw key).
    #   path:         where infisical-agent writes the secret.
    #   platformPath: same, but the control plane may override it during bootstrap, before
    #                 the agent is running to render anything.
    services: {
      
      [name]: catalogue[name] {

        path::
        $.secretDir + '/' + catalogue[name].dest,
        
        platformPath::
        '${ANSIBLE_SECRETS_FILE:-' + self.path + '}',

      }

      for name in std.objectFields(catalogue)
    },

  },
}
