// Single source of truth for names that cross stack boundaries.
// Reference by KEY (reg.endpoints.postgres.host), never raw string — a typo'd key fails at
// compile time; a typo'd string fails silently at runtime (wrong/empty value).
//
// DATA vs COMPILER. The human-edited data — hosts, domains, Infisical projects, and the
// secret catalogue — now lives in Grist, pulled to registry.data.json by
// .jsonnet/grist_pull.py. This file is the compiler: it wraps that data with the scalars,
// endpoints, and derived-field logic jsonnet computes. Edit data in Grist and re-run
// grist_pull.py; edit topology/logic (scalars, endpoints, the services comprehension) here.
// registry.data.json is committed, so every render is reproducible and diffable in git.

local data = std.parseJson(importstr 'registry.data.json');

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
    # Edited in Grist (Hosts table) → registry.data.json.
    hosts: data.hosts,
  },

  ////////////

  # Edited in Grist (Domains table) → registry.data.json.
  domains: data.domains,

  ////////////

  roles: { app: 'app', db: 'db', redis: 'redis' },

  ////////////

  envFiles: {
    tailscale: '/srv/docker/files/tailscale.env',
  },

  ////////////

  # Service-to-service endpoints (not user-facing). `container`: the service's own identity
  # (container_name + internal port), used by the stack that owns it. `host`: how OTHER
  # stacks reach it now that the shared Docker networks are gone — the service publishes a
  # port on the host and consumers dial the docker host-gateway, so a consuming service needs
  # `extra_hosts: ['host.docker.internal:host-gateway']`. `public`: the user-facing URL.
  # Kept here (not Grist): heterogeneous nested shape, and `public.domain` references
  # $.domains by key to keep the single-source contract.
  endpoints: {

    postgres: {

      container: {
        host:     'postgres-db',
        port:     5432,
      },

      host: {
        host:     'host.docker.internal',
        port:     6109,
      },
    },

    infisical: {

      container: {
        host:     'infisical_app',
        port:     8080,
      },

      public: {
        sub:      'infisical',
        domain:   $.domains.ktbinternal
      },
    },

  },

  ////////////

  infisical: {
    # Edited in Grist (InfisicalProjects table) → registry.data.json.
    projects: data.infisicalProjects,

    # Catalogue of every stack the Infisical agent can render, edited in Grist (Secrets
    # table) → registry.data.json; services.jsonnet generates one templates/<svc>.yaml
    # fragment per entry, a host opts in via AGENT_SERVICES. Fields:
    #   dest: output filename under /dev/shm/. Reference it as `path` (below), never retype it.
    #   type: dump = whole folder, secret names already match env-var names.
    #         map  = explicit renames via `keys` ({ OUTPUT_ENV_VAR: 'infisical-secret-name' }).
    #         raw  = single secret's raw value (no KEY= prefix) via `key`.
    #   env:  Infisical environment slug; defaults to 'prod' when omitted.
    local catalogue = data.secrets,

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
