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
  rootDomain: $.domains.homektb,
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
  },
  # DOMAINS
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
      private: { host: 'postgres-db', port: 5432, network: $.sharedNetworks.postgres },  // host == the db service's <stack>-<role> name/alias
    },
    infisical: {
      private: { host: 'infisical-app', port: 8080, network: $.sharedNetworks.infisical },
      public: { sub: 'infisical', domain: $.domains.homektb },
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
  # SOURCE — services.yaml (mounted into the agent) is GENERATED from this; a host
  # opts a service in via AGENT_SERVICES. Fields:
  #   project  key into `projects` (resolved to the UUID in services.yaml)
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
  # services.yaml is fully generated from this — there are NO hand-written .tpl
  # files; entrypoint.sh builds each agent template from type + keys/key.
  agentServices: {
    # --- Apps project ---
    postgres: { project: 'apps', folder: '/postgres', dest: 'postgres.env', type: 'dump' },
    paperless: { project: 'apps', folder: '/paperless', dest: 'apps_paperless.env', type: 'dump' },
    docuseal: { project: 'apps', folder: '/docuseal', dest: 'docuseal.env', type: 'dump' },
    openproject: { project: 'apps', folder: '/openproject', dest: 'openproject.env', type: 'dump' },
    immich: { project: 'apps', folder: '/immich', dest: 'immich.env', type: 'dump' },
    stream: { project: 'apps', folder: '/stream', dest: 'stream.env', type: 'dump' },
    # --- Frappe project ---
    frappe: { project: 'frappe', folder: '/frappe', dest: 'biz-ops_frappe.env', type: 'dump' },
    # --- Couch-potatoes client project ---
    'couch-potatoes-website': { project: 'couchPotatoes', folder: '/website', dest: 'client_couch-potatoes_website.env', type: 'dump' },
    # --- Stackform project ---
    'stackform-website': { project: 'stackform', folder: '/website', dest: 'stackform_website.env', type: 'dump' },
    # --- Infra project (dump) ---
    traefik: { project: 'infra', folder: '/traefik', dest: 'node_traefik.env', type: 'dump' },
    zerobyte: { project: 'infra', folder: '/zerobyte', dest: 'node_zerobyte.env', type: 'dump' },
    forgejo: { project: 'infra', folder: '/forgejo', dest: 'forgejo.env', type: 'dump' },
    gitea: { project: 'infra', folder: '/gitea', dest: 'gitea.env', type: 'dump' },
    'komodo-mcp': { project: 'infra', folder: '/komodo-mcp', dest: 'infra_komodo-mcp.env', type: 'dump' },
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
      dest: 'node_cloudflared.env',
      type: 'map',
      keys: { CLOUDFLARE_TUNNEL_TOKEN: 'TUNNEL_TOKEN' },
    },
    # --- Infra project (raw: single secret's raw value to a .key file) ---
    databasus: { project: 'infra', folder: '/databasus', dest: 'databasus_secret.key', type: 'raw', key: 'SECRET_KEY' },
  },
  # AGENT SERVICES (secret catalogue)
  # ============================================================

  // ── Shared volumes that cross stack boundaries (e.g. backup targets) ──────
  volumes: {},
}
