// Single source of truth for names that cross stack boundaries — the globally scoped
// version of a stack's own `refs` table. If one stack needs a value another stack owns,
// it lives here; values that depend on nothing (defaults, spellings) live in
// collections.libsonnet instead, and are never repeated here.
//
// Reference by KEY (reg.endpoint.serviceGroup.postgres.host.addr), never raw string — a
// typo'd key fails at compile time; a typo'd string fails silently at runtime.
local col = import 'collections.libsonnet';
local tmpl = import 'templates.libsonnet';

{
  path:: {
    file:: {
      infisical_creds:: "/mnt/secrets/credentials/infisical.env"
    },
  },
  network:: {
    // Container-to-container, within one host. The owning stack declares it plain in its
    // top-level networks:, every other stack declares it external — so attaching before
    // the owner exists fails the deploy instead of building a second empty copy.
    shared:: {
      paperlessDB::   tmpl.SharedNetwork { base:: 'paperless_db' },
      postgresDB::    tmpl.SharedNetwork { base:: 'postgres_db' },
      infisicalDB::   tmpl.SharedNetwork { base:: 'infisical_db' },
      forgejoDB::     tmpl.SharedNetwork { base:: 'forgejo_db' },
      tsGateway::     tmpl.SharedNetwork { base:: 'ts-gateway' },
    },
  },

  endpoint:: {
    hostGroup:: tmpl.Endpoint.HostGroup {
      local hostGroup = self,
      zone:: 'internal',

      // ── Main cluster ──
      littlebuddy::     hostGroup.Host { alias:: 'littlebuddy' },
      paiki::           hostGroup.Host { alias:: 'paiki' },
      biggy::           hostGroup.Host { alias:: 'biggy' },
      bill::            hostGroup.Host { alias:: 'bill' },
      // ── VPS ──
      maboi::           hostGroup.Host { alias:: 'maboi' },
      rick::            hostGroup.Host { alias:: 'rick', tailscaleIP:: '100.106.170.93' },
      // ── NAS ──
      nas::             hostGroup.Host { alias:: 'snaszy' },

      // ── Role-based ──
      controlplane::    hostGroup.Host { alias:: 'controlplane' },
      cinciPlex::       hostGroup.Host { alias:: 'cinci-plex' },
      cinciImmich::     hostGroup.Host { alias:: 'cinci-immich' },
      cinciStorage::    hostGroup.Host { alias:: 'cinci-storage' },
      cinciGames::      hostGroup.Host { alias:: 'cinci-games' },
    },

    serviceGroup:: tmpl.Endpoint.ServiceGroup { local host = $.endpoint.hostGroup,
      local serviceGroup = self,

      postgres:: serviceGroup.Service {
        local service = self,
        // The shared cluster's container name is not the <project>_<role> convention —
        // other stacks already dial `postgres-db`, so the stack overrides its own
        // container_name with this rather than the other way round.
        container:: service.Container { name:: 'postgres-db', port:: '5432' },
        host::      service.Host      { on:: host.littlebuddy, port:: '6109' },
      },

      infisical:: serviceGroup.Service {
        local service = self,
        container:: service.Container { name:: 'infisical_app', port:: '8080' },
        // 18006 belongs to authentik, so infisical takes 18043: the two only collide once
        // they share a host, which the littlebuddy -> rick control-plane move does.
        host::      service.Host      { on:: host.rick, port:: '18043' },
        proxy::     service.Proxy     { subdomain:: 'infisical', domain:: col.domain.ktbinternal },
      },

      pangolin:: serviceGroup.Service {
        local service = self,
        proxy:: service.Proxy { subdomain:: 'pangolin', domain:: col.domain.ktbcloud },
      },

      authentik:: serviceGroup.Service {
        local service = self,
        // The display name an OIDC client shows on its login button.
        name:: 'Authentik',
        proxy:: service.Proxy {
          local proxy = self,
          subdomain::    'authentik',
          domain::       col.domain.ktbcloud,
          oidc:: {
            issuer(OIDC_SLUG)::    proxy.url + '/application/o/' + OIDC_SLUG + '/',
            uri::                  proxy.url + '/application/o/authorize/',
          },
        },
      },
    },
  },

  // Directories one stack owns and another reads. A path only lands here once a second
  // stack needs it; everything private to a stack stays in that stack's own refs file.
  dir:: {
    // file-browser-quantum serves this tree; terraria keeps its world under it.
    fileBrowser:: { local root = col.dirs.rootlessSrv + '/file-browser-quantum',
      root:: root,
      data:: root + '/data',
      shared:: root + '/shared',
      cache:: root + '/cache',
    },
  },

  infisical:: { local infisical = self,
    // Where the infisical-secrets compose provider reaches the server. The control-plane
    // alias rather than the serviceGroup host's own name: every host in the fleet resolves
    // it, including the ones that deploy before they know which box is the control plane.
    address:: 'http://%s:%s' % [
      $.endpoint.hostGroup.controlplane.ref,
      $.endpoint.serviceGroup.infisical.host.port,
    ],

    t_InfisProject:: { local infisProject = self,
      id:: error '"id" is a required field of "infisProject"',
      t_Secrets:: {
        service:      error '"service" is a required field of "Secrets"',
        projectId:    infisProject.id,                            // ID of project containing secrets in Infisical
        env:          'prod',                                     // Infisical environment slug
        projectPath:  '/' + self.service,                         // path to secrets folder in Infisical
        // outFile/outFilePath are read only by lib.Secret, and only the Infisical stack
        // itself still uses that — every other stack reads its bundle through the provider.
        outFile:      self.service + '.env',                      // i.e. "<service>.env"
        outFilePath:  col.dirs.secrets + '/' + self.outFile,      // i.e. "/dev/shm/<service>.env"
      },
    },

    project:: {
      apps:: infisical.t_InfisProject { local project = self,
        id:: '2f0eb3d1-3e2a-4ce7-8060-5e47ad877e47',
        secretsMap:: {
          postgres:     project.t_Secrets { service: 'postgres' },
          paperless:    project.t_Secrets { service: 'paperless' },
          docuseal:     project.t_Secrets { service: 'docuseal' },
          openproject:  project.t_Secrets { service: 'openproject' },
          immich:       project.t_Secrets { service: 'immich' },
          stream:       project.t_Secrets { service: 'stream' },
          convertx:     project.t_Secrets { service: 'convertx' },
          twenty:       project.t_Secrets { service: 'twenty' },
          pangolin:     project.t_Secrets { service: 'pangolin' },
          // Only src/templates/stack reads this one — the template is a real compiling
          // stack, so the key it shows has to resolve. No such folder exists in Infisical.
          example:      project.t_Secrets { service: 'example' },
        },
      },
      frappe:: infisical.t_InfisProject { local project = self,
        id:: '12ed25dd-c0d2-4a78-9b10-472fc09fe554',
        secretsMap:: {
          frappe: project.t_Secrets { service: 'frappe' },
        },
      },
      couchPotatoes:: infisical.t_InfisProject { local project = self,
        id:: 'fb1dd6a7-3924-415b-b6c3-3071fc93aaae',
        secretsMap:: {
          'couch-potatoes-website': project.t_Secrets { service: 'couch-potatoes-website', projectPath: '/website', outFile: 'client_couch-potatoes_website.env' },
        },
      },
      stackform:: infisical.t_InfisProject { local project = self,
        id:: '15d61370-a2ec-4993-9bbd-3774a63f7b94',
        secretsMap:: {
          'stackform-website': project.t_Secrets { service: 'stackform-website', projectPath: '/website', outFile: 'stackform_website.env' },  // TODO: Delete, no longer used
        },
      },
      infra:: infisical.t_InfisProject { local project = self,
        id:: '86324d9b-3dd7-49d4-b252-69228c5ee0c7',
        secretsMap:: {
          cfApiDnsToken:    project.t_Secrets { service: 'cloudflare__dns-api-token', projectPath: '/traefik' },
          zerobyte:         project.t_Secrets { service: 'zerobyte' },
          infisical:        project.t_Secrets { service: 'infisical' },
          authentik:        project.t_Secrets { service: 'authentik' },
          forgejo:          project.t_Secrets { service: 'forgejo' },
          komodoMcp:        project.t_Secrets { service: 'komodo-mcp' },
          woodpecker:       project.t_Secrets { service: 'woodpecker' },
          homarr:           project.t_Secrets { service: 'homarr' },
          tsGateway:        project.t_Secrets { service: 'tsGateway', projectPath: '/tailscale/containers', outFile: 'ts-gateway.env' },
          newt:             project.t_Secrets { service: 'newt', projectPath: '/hosts/${AGENT_HOST}/newt' },
          komodo:           project.t_Secrets { service: 'komodo', outFile: 'komodo_core.env' },
          cloudflared:      project.t_Secrets { service: 'cloudflared', projectPath: '/hosts/${AGENT_HOST}/cloudflared' },
          databasus:        project.t_Secrets { service: 'databasus' },
        },
      },
    },

    // Every bundle above, flattened, so lib.SecretsProvider(key) is one lookup and a key
    // can only be spelled one way across the whole repo.
    catalog:: std.foldl(
      function(acc, name) acc + infisical.project[name].secretsMap,
      ['apps', 'frappe', 'couchPotatoes', 'stackform', 'infra'],
      {},
    ),
  },
}
