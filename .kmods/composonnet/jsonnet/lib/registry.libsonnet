// Single source of truth for names that cross stack boundaries.
// Reference by KEY (reg.endpoints.postgres.host), never raw string — a typo'd key fails at
// compile time; a typo'd string fails silently at runtime (wrong/empty value).

{

  secretPath:: '/dev/shm',

  ips:: {
    loopback: '127.0.0.1',
  },

  role:: {
    // The vocabulary for service keys. A stack picks its keys from here rather than
    // inventing names, so `db` is never also `database` or `postgres` in another stack, and
    // compose.libsonnet derives container/volume names from a role that means one thing.
    
    // User-facing / entry
    APP:: 'app',
    PROXY:: 'proxy',
    WEB:: 'web',
    API:: 'api',
    ASSETS:: 'assets',

    // Network
    DNS:: 'dns',

    // Compute
    SERVER:: 'server',
    AGENT:: 'agent',
    TUNNEL:: 'tunnel',
    WORKER:: 'worker',
    SCHEDULER:: 'scheduler',
    CONSUMER:: 'consumer',
    RUNNER:: 'runner',

    // State
    DB:: 'db',
    CACHE:: 'cache',
    QUEUE:: 'queue',
    SEARCH:: 'search',
    STORAGE:: 'storage',
    VECTOR:: 'vector',

    // Lifecycle
    MIGRATE:: 'migrate',
    SEEDER:: 'seeder',
    BACKUP:: 'backup',

    // Ops
    METRICS:: 'metrics',
    LOGS:: 'logs',
    MAIL:: 'mail',
  },

  domains:: {
    homektb:        'homektb.com',
    stackform:      'stackform.app',
    couchpotatoes:  'couchpotatoes.store',
    ktbinternal:    'ktbinternal.com',
    ktbcloud:       'ktbcloud.com',
  },

  networks:: {
    hostGateway: {
      local scope_hostGateway = self,
      gateway:: "172.28.0.1",
      create(stackName):: {
        [stackName + "_public"]: {
          driver: 'bridge',
          ipam: { config: [ {subnet: "172.28.0.0/24", gateway: scope_hostGateway.gateway} ] },
        },
      },
    },

    shared:: {
      paperlessDB::   "shared__paperless_db",
      postgresDB::    "shared__postgres_db",
      infisicalDB::   "shared__infisical_db",
      forgejoDB::     "shared__forgejo_db",
      tsGateway::     "shared__ts-gateway",
    }
  },

  restartPolicy:: {
    unlessStopped:: "unless-stopped",
    // Defaults
    default:: self.unlessStopped,
  },

  volumes:: {
    dockerSock:: { mount:: "/var/run/docker.sock:/var/run/docker.sock:ro" },
  },

  hosts:: {
    # ── Main cluster ──
    littlebuddy: { ip: '10.100.0.21', aka: ['controlplane'], edge: true },
    paiki: { ip: '10.100.0.22', dns: 'plexyandiknowit', aka: ['plex'], edge: true },
    biggy: { ip: '10.100.0.23' },
    bill: { ip: '10.100.0.25', edge: true },
    # ── VPS ──
    maboi: { ip: '10.100.0.101', edge: true },
    rick: { ip: '10.100.0.102', edge: true },
    # ── NAS ──
    nas: { ip: '100.91.182.94' },
  },

  endpoint:: {
    // Service endpoints are defined by "exposure level"
    // So, 'container' would mean the endpoint inside the actual docker container
    // 'host' would mean an endpoint exposed only to the host machine (bound to loopback ip)
    // 'public' would mean it's exposed all the way through the host's firewall

    postgres:: {
      container:: {
        host::     'postgres-db',
        port::     '5432',
      },
      host:: {
        host::     'host.docker.internal',
        port::     '6109',
      },
    },

    infisical:: {
      container:: {
        host::     'infisical_app',
        port::     '8080',
        },
      host:: {
        // 18006 belongs to authentik (see its README: authentik.ktbcloud.com ->
        // 127.0.0.1:18006 on rick). The two only collide once they share a host,
        // which the lilbud -> rick control-plane move does.
        port::      '18043',
      },
      public:: {
        scheme::    'https',
        sub::       'infisical',
        domain::    $.domains.ktbinternal,
        fqdn::      self.sub + '.' + self.domain,
        url::       self.scheme + '://' + self.fqdn,
        },
    },

    pangolin:: {
      public:: {
        scheme::    'https',
        sub::       'pangolin',
        domain::    $.domains.ktbcloud,
        fqdn::      self.sub + '.' + self.domain,
        url::       self.scheme + '://' + self.fqdn,
      }
    },

    authentik:: {
      name:: "Authentik",
      public:: {
        local pub = self,
        //
        scheme::       "https",
        sub::          'authentik',
        domain::       $.domains.ktbcloud,
        fqdn::         self.sub + "." + self.domain,
        url::          self.scheme + "://" + self.fqdn,
        oidc:: {
          issuer(OIDC_SLUG)::    pub.url + "/application/o/" + OIDC_SLUG + "/",
          uri::                  pub.url + "/application/o/authorize/",
          }
      }}
  },

  dirs:: {
    docker:: {
      root::       '/srv/docker',
      bindMounts:: '/bind-mounts',
    },

    NAS:: {
      docker:: '/volume1/docker',
      backups:: '/volume1/backups',
    },
  },

  infisical:: {
    project:: {
      apps:           '2f0eb3d1-3e2a-4ce7-8060-5e47ad877e47',
      frappe:         '12ed25dd-c0d2-4a78-9b10-472fc09fe554',
      couchPotatoes:  'fb1dd6a7-3924-415b-b6c3-3071fc93aaae',
      stackform:      '15d61370-a2ec-4993-9bbd-3774a63f7b94',
      infra:          '86324d9b-3dd7-49d4-b252-69228c5ee0c7',
    },
    
    catalog:: {
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
      
      arcane:
      { project: 'infra', folder: '/arcane', dest: 'arcane.env', type: 'dump' },

      infisical:
      { project: 'infra', folder: '/infisical', dest: 'infisical.env', type: 'dump' },

      authentik:
      { project: 'infra', folder: '/authentik', dest: 'authentik.env', type: 'dump' },

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
      
      'tsGateway':
      { project: 'infra', folder: '/tailscale/containers', dest: 'ts-gateway.env', type: 'dump' },

      newt:
      { project: 'infra', folder: '/hosts/${AGENT_HOST}/newt', dest: 'newt.env', type: 'dump' },
      
      komodo:
      { project:  'infra', folder: '/komodo', dest: 'komodo_core.env', type: 'dump' },
      
      cloudflared:
      { project:  'infra', folder: '/hosts/${AGENT_HOST}/cloudflared', dest: 'cloudflared.env', type: 'dump' },
      
      databasus:
      { project: 'infra', folder: '/databasus', dest: 'databasus_secret.key', type: 'raw', key: 'SECRET_KEY' },

      homarr:
      { project: 'infra', folder: '/homarr', dest: 'homarr.env', type: 'dump'},
      
      pangolinClient:
      { project: 'infra', folder: '/hosts/${AGENT_HOST}/pangolin_client', dest: 'pangolin_client.env', type: 'dump'},
    },

  },
}
