// registry.libsonnet
//
// SINGLE SOURCE OF TRUTH for every name that crosses stack boundaries.
// Change a value here once and every stack that references it follows.
//
// Reference these by KEY (e.g. reg.sharedNetworks.proxy), never by raw string:
// a typo'd key fails at COMPILE time; a typo'd YAML string fails SILENTLY at
// runtime (wrong/empty network — the class of bug this registry kills).
//
// `$` below means "the root of THIS object" — it lets one section point at
// another (e.g. an endpoint references the sharedNetworks entry it lives on).
{
  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # GLOBAL VARIABLES
  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # notes: Literal independent variables used accross all containers.
  # rootDomain is the default zone; pull any other zone from `domains`.
  rootDomain: $.domains.ktbinternal,
  dockerDir: '/srv/docker',
  dockerVolumes: $.dockerDir + '/bind-mounts',
  # GLOBAL VARIABLES
  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~



  # ============================================================
  # DOMAINS
  # ============================================================
  # notes: Public DNS zones we serve. `public` endpoints + Traefik pull from here
  # so a zone string is written exactly once.
  domains: {
    homektb: 'homektb.com',
    stackform: 'stackform.app',
    couchpotatoes: 'couchpotatoes.store',
    ktbinternal: 'ktbinternal.com',
    ktbcloud: 'ktbcloud.com',
  },
  # DOMAINS
  # ============================================================



  # ============================================================
  # SERVICE ROLES
  # ============================================================
  # notes: Predefined role-name constants for the common service roles, so a typo
  # fails at compile time (same guard as every other registry key). Reference by
  # KEY (roles.app); pass any OTHER role inline as a string when you need one
  # that isn't predefined (container/volume/alias naming just labels intent).
  roles: { app: 'app', db: 'db', redis: 'redis' },
  # SERVICE ROLES
  # ============================================================



  # ============================================================
  # SHARED DOCKER NETWORKS
  # ============================================================
  # notes: Networks shared between containers that don't live in the same stack as
  # each other. The 'shared-' prefix is explicit in `name` so the real Docker
  # network name is obvious here, not hidden in a helper.
  sharedNetworks: {
    proxy: { name: 'shared-proxy', owner: 'traefik' },
    postgres: { name: 'shared-postgres', owner: 'postgres' },
    dbBackups: { name: 'shared-db-backups', owner: 'databasus' },
    infisical: { name: 'shared-infisical', owner: 'infisical' },
    edge: { name: 'shared-edge', owner: 'authentik' },
  },
  # SHARED DOCKER NETWORKS
  # ============================================================



  # ============================================================
  # SERVICE ENDPOINTS
  # ============================================================
  # notes: Service to service communication endpoints. NOT the same as an endpoint
  # for Users to use.
  #   private — container-to-container on a shared net; `network` REFERENCES the
  #             sharedNetworks entry (so the dependency is real + compile-checked).
  #   public  — via Traefik at https://<sub>.<domain>; `domain` pulls from domains.
  endpoints: {
    postgres: {
      private: {
        host: 'postgres-db',
        port: 5432,
        network: $.sharedNetworks.postgres
      }, 
    },
    infisical: {
      private: { host: 'infisical_app', port: 8080, network: $.sharedNetworks.infisical },
      public: { sub: 'infisical', domain: $.domains.ktbinternal },
    },
  },
  # SERVICE ENDPOINTS
  # ============================================================



  # ============================================================
  # INFISICAL PROJECTS
  # ============================================================
  # notes: Infisical project UUIDs, referenced by KEY from agentServices so the
  # raw UUID is written exactly once.
  projects: {
    apps: '2f0eb3d1-3e2a-4ce7-8060-5e47ad877e47',
    frappe: '12ed25dd-c0d2-4a78-9b10-472fc09fe554',
    couchPotatoes: 'fb1dd6a7-3924-415b-b6c3-3071fc93aaae',
    stackform: '15d61370-a2ec-4993-9bbd-3774a63f7b94',
    infra: '86324d9b-3dd7-49d4-b252-69228c5ee0c7',
  },
  # INFISICAL PROJECTS
  # ============================================================



  # ============================================================
  # AGENT SERVICES (secret catalogue)
  # ============================================================
  # notes: The catalogue of every stack the Infisical agent can render. SINGLE
  # SOURCE — services.jsonnet generates one agent-config fragment per service into
  # templates/<svc>.yaml (mounted into the agent); a host opts a service in via
  # AGENT_SERVICES. Fields:
  #   project  key into `projects` (resolved to the UUID in the fragment)
  #   folder   Infisical secret path (may contain ${AGENT_HOST}, substituted at runtime)
  #   dest     output file under /dev/shm/ — MUST equal what the consumer reads
  #            (a stack's parent compose.yaml include.env_file, or a bind mount)
  #   type     dump = whole folder -> KEY=VALUE (Infisical secret names already
  #                   equal the consumer's env-var names)
  #            map  = explicit renames/duplications via the `keys` map
  #                   ({ OUTPUT_ENV_VAR: 'infisical-secret-name', ... })
  #            raw  = a single secret's raw value, NO KEY= prefix, via `key`
  #                   (for non-KEY=VALUE files, e.g. a *.key bind mount)
  #   env      Infisical environment slug; defaults to 'prod' when omitted
  # The per-service templates/ fragments are fully generated from this (with the
  # inline Go template baked in by services.jsonnet); entrypoint.sh only selects
  # and concatenates them — it builds no templates itself.
  agentServices: {
    # --- Apps project ---
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
    # --- Couch-potatoes client project ---
    'couch-potatoes-website': { project: 'couchPotatoes', folder: '/website', dest: 'client_couch-potatoes_website.env', type: 'dump' },
    # --- Stackform project ---
    'stackform-website': { project: 'stackform', folder: '/website', dest: 'stackform_website.env', type: 'dump' },
    # --- Infra project (dump) ---
    # Cloudflare DNS-01 ACME token — shared by any stack whose Traefik needs
    # it, not just platform/edge/traefik (see platform/edge/pangolin).
    'cloudflare__dns-api-token': { project: 'infra', folder: '/traefik', dest: 'cloudflare__dns-api-token.env', type: 'dump' },
    zerobyte: { project: 'infra', folder: '/zerobyte', dest: 'zerobyte.env', type: 'dump' },
    # Ansible seeds these into the /infisical folder during bootstrap (it has to
    # match the live ENCRYPTION_KEY/DB password already in use); the agent then
    # keeps re-rendering infisical.env from there so a tmpfs eviction that isn't a
    # full host reboot doesn't require a manual Ansible re-run.
    infisical: { project: 'infra', folder: '/infisical', dest: 'infisical.env', type: 'dump' },
    forgejo: { project: 'infra', folder: '/forgejo', dest: 'forgejo.env', type: 'dump' },
    gitea: { project: 'infra', folder: '/gitea', dest: 'gitea.env', type: 'dump' },
    'komodo-mcp': { project: 'infra', folder: '/komodo-mcp', dest: 'komodo-mcp.env', type: 'dump' },
    woodpecker: { project: 'infra', folder: '/woodpecker', dest: 'woodpecker.env', type: 'dump' },
    # --- Infra project (map: renamed/duplicated keys) ---
    # komodo renames KOMODO_DB_* -> KOMODO_DATABASE_* and reuses the DB creds for MONGO_INITDB_ROOT_*.
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
    # cloudflared: host-scoped folder + renames TUNNEL_TOKEN -> CLOUDFLARE_TUNNEL_TOKEN.
    cloudflared: {
      project: 'infra',
      folder: '/hosts/${AGENT_HOST}/cloudflared',
      dest: 'cloudflared.env',
      type: 'map',
      keys: { CLOUDFLARE_TUNNEL_TOKEN: 'TUNNEL_TOKEN' },
    },
    # newt: host-scoped Pangolin site creds, same shape as cloudflared above
    # (per-host ${AGENT_HOST} folder). A host opts `newt` into its AGENT_SERVICES
    # and the agent dumps /hosts/${AGENT_HOST}/newt; secret names match the env
    # vars, so type=dump.
    newt: { project: 'infra', folder: '/hosts/${AGENT_HOST}/newt', dest: 'newt.env', type: 'dump' },
    # authentik: renames PG_PASS -> both AUTHENTIK_POSTGRESQL__PASSWORD and
    # POSTGRES_PASSWORD (one secret feeds the app's DSN and the db's own
    # POSTGRES_PASSWORD); bootstrap creds keep their short Infisical names.
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
    # authentik-outpost: single outpost API token; secret name already equals
    # the env var (AUTHENTIK_TOKEN), so type=dump.
    'authentik-outpost': { project: 'infra', folder: '/authentik-outpost', dest: 'authentik-outpost.env', type: 'dump' },
    # --- Infra project (raw: single secret's raw value to a .key file) ---
    databasus: { project: 'infra', folder: '/databasus', dest: 'databasus_secret.key', type: 'raw', key: 'SECRET_KEY' },
  },
  # AGENT SERVICES (secret catalogue)
  # ============================================================

  envFiles: {
    secretsPath(envFilename): '/dev/shm/' + envFilename,
    platform(envFilename):: '${ANSIBLE_SECRETS_FILE:-' + self.secretsPath(envFilename) + '}',
    tailscale: '/srv/docker/files/tailscale.env',
  },

  // ── Shared volumes that cross stack boundaries (e.g. backup targets) ──────
  volumes: {},
}
