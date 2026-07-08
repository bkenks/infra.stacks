// Single source of truth for names that cross stack boundaries.
// Reference by KEY (reg.sharedNetworks.proxy), never raw string — a typo'd key fails at
// compile time; a typo'd string fails silently at runtime (wrong/empty network).
{
  server: {
    dir: {
      docker: {
        root: '/srv/docker',
        bindmounts: '/bind-mounts',
      },
    },
    hosts: {
      littlebuddy: { ip: '100.114.137.104' },
      paiki: { ip: '100.126.19.103' },
      maboi: { ip: '100.97.83.95' },
      bill: { ip: '100.79.7.11' },
      rick: { ip: '100.106.170.93' },
    },
  },


  domains: {
    homektb: 'homektb.com',
    stackform: 'stackform.app',
    couchpotatoes: 'couchpotatoes.store',
    ktbinternal: 'ktbinternal.com',
    ktbcloud: 'ktbcloud.com',
  },

  roles: { app: 'app', db: 'db', redis: 'redis' },

  sharedNetworks: {
    proxy: { name: 'shared-proxy', owner: 'traefik' },
    postgres: { name: 'shared-postgres', owner: 'postgres' },
    dbBackups: { name: 'shared-db-backups', owner: 'databasus' },
    infisical: { name: 'shared-infisical', owner: 'infisical' },
    edge: { name: 'shared-edge', owner: 'authentik' },
  },

  envFiles: {
    tailscale: '/srv/docker/files/tailscale.env',
  },

  # Service-to-service endpoints (not user-facing). `container`: internal, on a shared net
  # (`network` references sharedNetworks so the dependency compile-checks). `public`: via
  # Traefik at https://<sub>.<domain>.
  endpoints: {
    postgres: {
      container: {
        host: 'postgres-db',
        port: 5432,
        network: $.sharedNetworks.postgres
      }, 
    },
    infisical: {
      container: {
        host: 'infisical_app',
        port: 8080,
        network: $.sharedNetworks.infisical
      },
      public: {
        sub: 'infisical',
        domain: $.domains.ktbinternal
      },
    },
  },

  infisical: {
    projects: {
      apps: '2f0eb3d1-3e2a-4ce7-8060-5e47ad877e47',
      frappe: '12ed25dd-c0d2-4a78-9b10-472fc09fe554',
      couchPotatoes: 'fb1dd6a7-3924-415b-b6c3-3071fc93aaae',
      stackform: '15d61370-a2ec-4993-9bbd-3774a63f7b94',
      infra: '86324d9b-3dd7-49d4-b252-69228c5ee0c7',
    },
    services: {
      # Catalogue of every stack the Infisical agent can render; services.jsonnet generates
      # one templates/<svc>.yaml fragment per entry, a host opts in via AGENT_SERVICES. Fields:
      #   dest: output file under /dev/shm/ — MUST equal what the consumer reads.
      #   type: dump = whole folder, secret names already match env-var names.
      #         map  = explicit renames via `keys` ({ OUTPUT_ENV_VAR: 'infisical-secret-name' }).
      #         raw  = single secret's raw value (no KEY= prefix) via `key`.
      #   env:  Infisical environment slug; defaults to 'prod' when omitted.
      postgres: { project: 'apps', folder: '/postgres', dest: 'postgres.env', type: 'dump' },
      paperless: { project: 'apps', folder: '/paperless', dest: 'paperless.env', type: 'dump' },
      docuseal: { project: 'apps', folder: '/docuseal', dest: 'docuseal.env', type: 'dump' },
      openproject: { project: 'apps', folder: '/openproject', dest: 'openproject.env', type: 'dump' },
      immich: { project: 'apps', folder: '/immich', dest: 'immich.env', type: 'dump' },
      stream: { project: 'apps', folder: '/stream', dest: 'stream.env', type: 'dump' },
      convertx: { project: 'apps', folder: '/convertx', dest: 'convertx.env', type: 'dump' },
      twenty: { project: 'apps', folder: '/twenty', dest: 'twenty.env', type: 'dump' },
      pangolin: { project: 'apps', folder: '/pangolin', dest: 'pangolin.env', type: 'dump' },
      frappe: { project: 'frappe', folder: '/frappe', dest: 'frappe.env', type: 'dump' },
      'couch-potatoes-website': { project: 'couchPotatoes', folder: '/website', dest: 'client_couch-potatoes_website.env', type: 'dump' },
      'stackform-website': { project: 'stackform', folder: '/website', dest: 'stackform_website.env', type: 'dump' },
      'cloudflare__dns-api-token': { project: 'infra', folder: '/traefik', dest: 'cloudflare__dns-api-token.env', type: 'dump' },
      zerobyte: { project: 'infra', folder: '/zerobyte', dest: 'zerobyte.env', type: 'dump' },
      infisical: { project: 'infra', folder: '/infisical', dest: 'infisical.env', type: 'dump' },
      forgejo: { project: 'infra', folder: '/forgejo', dest: 'forgejo.env', type: 'dump' },
      gitea: { project: 'infra', folder: '/gitea', dest: 'gitea.env', type: 'dump' },
      'komodo-mcp': { project: 'infra', folder: '/komodo-mcp', dest: 'komodo-mcp.env', type: 'dump' },
      woodpecker: { project: 'infra', folder: '/woodpecker', dest: 'woodpecker.env', type: 'dump' },
      komodo: {
        project: 'infra',
        folder: '/komodo',
        dest: 'komodo_core.env',
        type: 'map',
        keys: {
          KOMODO_DATABASE_USERNAME: 'KOMODO_DB_USERNAME',
          KOMODO_DATABASE_PASSWORD: 'KOMODO_DB_PASSWORD',
          KOMODO_WEBHOOK_SECRET: 'WEBHOOK_SECRET',
          KOMODO_JWT_SECRET: 'JWT_SECRET',
          MONGO_INITDB_ROOT_USERNAME: 'KOMODO_DB_USERNAME',
          MONGO_INITDB_ROOT_PASSWORD: 'KOMODO_DB_PASSWORD',
        },
      },
      cloudflared: {
        project: 'infra',
        folder: '/hosts/${AGENT_HOST}/cloudflared',
        dest: 'cloudflared.env',
        type: 'map',
        keys: { CLOUDFLARE_TUNNEL_TOKEN: 'TUNNEL_TOKEN' },
      },
      newt: { project: 'infra', folder: '/hosts/${AGENT_HOST}/newt', dest: 'newt.env', type: 'dump' },
      authentik: {
        project: 'infra',
        folder: '/authentik',
        dest: 'authentik.env',
        type: 'map',
        keys: {
          AUTHENTIK_SECRET_KEY: 'AUTHENTIK_SECRET_KEY',
          AUTHENTIK_POSTGRESQL__PASSWORD: 'PG_PASS',
          POSTGRES_PASSWORD: 'PG_PASS',
          AUTHENTIK_BOOTSTRAP_PASSWORD: 'BOOTSTRAP_PASSWORD',
          AUTHENTIK_BOOTSTRAP_TOKEN: 'BOOTSTRAP_TOKEN',
          AUTHENTIK_BOOTSTRAP_EMAIL: 'BOOTSTRAP_EMAIL',
        },
      },
      'authentik-outpost': { project: 'infra', folder: '/authentik-outpost', dest: 'authentik-outpost.env', type: 'dump' },
      databasus: { project: 'infra', folder: '/databasus', dest: 'databasus_secret.key', type: 'raw', key: 'SECRET_KEY' },
    },
  },


  # "Which host runs X, at what subdomain" for every service the central controller routes —
  # DATA, so controller.jsonnet re-renders controller.yaml automatically on a host move or
  # subdomain change. Fields: home = key into server.hosts (compile-checked); sub = subdomain
  # when it differs from the key (else the key IS the subdomain); direct = { port } for a
  # service reached directly, bypassing Traefik re-encrypt (Plex only); latent = true for
  # catalogued-but-not-yet-deployed (still gets a router; informational only).
  controllerServices: {
    frappe: { home: 'bill' },
    # ── littlebuddy (personal apps + devops) ──
    infisical: { home: 'littlebuddy' },
    komodo: { home: 'littlebuddy', sub: 'komo' },
    'komodo-mcp': { home: 'littlebuddy' },
    forgejo: { home: 'littlebuddy', sub: 'fj' },
    woodpecker: { home: 'littlebuddy', sub: 'peck' },
    termix: { home: 'littlebuddy' },
    docuseal: { home: 'littlebuddy' },
    openproject: { home: 'littlebuddy', sub: 'openprj' },
    paperless: { home: 'littlebuddy', sub: 'paper' },
    scriberr: { home: 'littlebuddy' },
    mazanoke: { home: 'littlebuddy', latent: true },
    convertx: { home: 'littlebuddy', latent: true },
    # ── paiki (media stack) ──
    immich: { home: 'paiki' },
    sonarr: { home: 'paiki' },
    radarr: { home: 'paiki' },
    prowlarr: { home: 'paiki' },
    bazarr: { home: 'paiki' },
    sabnzbd: { home: 'paiki' },
    seerr: { home: 'paiki' },
    # Plex is host-mode on paiki :32400 — NOT behind paiki's Traefik, so it routes
    # straight to the Plex process via a `-direct` backend (see `direct` above).
    plex: { home: 'paiki', direct: { port: 32400 } },
    # ── rick ──
    pangolin: { home: 'rick' },
  },
}
