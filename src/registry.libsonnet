// Single source of truth for names that cross stack boundaries.
// Reference by KEY (reg.endpoints.postgres.host), never raw string — a typo'd key fails at
// compile time; a typo'd string fails silently at runtime (wrong/empty value).
local t = import "templates.libsonnet";

{
  path:: {
    srv::     '/srv',
    tmpfs::   '/dev/shm',
    docker::  { root:: '/srv/docker', bindMounts:: '/srv/docker/bind-mounts' },
    nas::     { docker:: '/volume1/docker', backups:: '/volume1/backups' },

    // TODO: Refactor out of code, think used in Terraria
    // general:: {
    //   rootlessSrv:: '/rootless-srv',
    // },
  },

  ip:: {
    loopback: '127.0.0.1',
  },

  domain:: {
    homektb:        'homektb.com',
    stackform:      'stackform.app',
    couchpotatoes:  'couchpotatoes.store',
    ktbinternal:    'ktbinternal.com',
    ktbcloud:       'ktbcloud.com',
  },

  network:: {
    shared:: {
      paperlessDB::   "shared__paperless_db",
      postgresDB::    "shared__postgres_db",
      infisicalDB::   "shared__infisical_db",
      forgejoDB::     "shared__forgejo_db",
      tsGateway::     "shared__ts-gateway",
    }
  },

  restartPolicy:: {
    default:: "", // TODO: Point at collections
  },

  // TODO: Move to collections
  // volumes:: {
  //   dockerSock:: { mount:: "/var/run/docker.sock:/var/run/docker.sock:ro" },
  // },

  endpoint:: {
    hostGroup:: t.Endpoint.HostGroup {
      local hostGroup = self,
      zone:: ".internal",

      # ── Main cluster ──
      littlebuddy::     hostGroup.Host { alias:: "littlebuddy" },
      paiki::           hostGroup.Host { alias:: "paiki" },
      biggy::           hostGroup.Host { alias:: "biggy" },
      bill::            hostGroup.Host { alias:: "bill" },
      # ── VPS ──
      maboi::           hostGroup.Host { alias:: "maboi" },
      rick::            hostGroup.Host { alias:: "rick" },
      # ── NAS ──
      nas::             hostGroup.Host { alias:: "snaszy" },
      
      # —— Role-Based ——
      controlplane::    hostGroup.Host { alias:: "controlplane" },
      cinciPlex::       hostGroup.Host { alias:: "cinci-plex" },
      cinciImmich::     hostGroup.Host { alias:: "cinci-immich" },
      cinciStorage::    hostGroup.Host { alias:: "cinci-storage" },
      cinciGames::      hostGroup.Host { alias:: "cinci-games" },
    },

    serviceGroup:: t.Endpoint.ServiceGroup {
      local serviceGroup = self,

      postgres:: serviceGroup.Service {
        local service = self,
        container:: service.Container { name:: 'postgres-db', port:: '5432' },
        host::      service.Host      { port:: '6109' }, // TODO: Check if "name:: 'host.docker.internal'," was used anywhere; just removed it
      },

      infisical:: serviceGroup.Service {
        local service = self,
        container:: service.Container { name:: 'infisical_app', port:: '8080' },
        host::      service.Host      { port:: '18043' },
        proxy::     service.Proxy     { sub:: 'infisical', domain:: $.domains.ktbinternal },
      },

      pangolin:: serviceGroup.Service {
        local service = self,
        proxy:: service.Proxy { sub:: 'pangolin', domain:: $.domains.ktbcloud }
      },

      authentik:: serviceGroup.Service {
        local service = self,
        name:: "Authentik",
        proxy:: service.Proxy {
          local proxy = self,
          sub::          'authentik',
          domain::       $.domains.ktbcloud,
          oidc:: {
            issuer(OIDC_SLUG)::    proxy.url + "/application/o/" + OIDC_SLUG + "/",
            uri::                  proxy.url + "/application/o/authorize/",
          }
        }
      }
    }
  },

  infisical:: { local infisical = self,
    t_InfisProject:: { local infisProject = self,
      id:: error '"id" is a required field of "infisProject"',
      t_Secrets:: {
        service:      error '"service" is a required field of "Secrets"',
        projectId:    infisProject.id,                      // ID of project containing secrets in Infisical
        projectPath:  '/' + self.service,                   // path to secrets folder in Infisical
        outFile:      self.service + ".env",                // i.e. "<service>.env"
        outFilePath:  $.path.tmpfs + "/" + self.outFile,    // i.e. "/dev/shm/<service>.env"
        type:         'dump',                               // e.g. "dump": dump all secrets in projectPath, "raw": one secret -> one file
        key:          '',                                   // Secret Name; required if "type: raw"
      }
    },

    project:: infisical.t_InfisProject { local project = self,
      apps:: {
        id:: '2f0eb3d1-3e2a-4ce7-8060-5e47ad877e47',
        secretsMap:: {
          postgres:     project.t_Secrets { service: 'postgres' },
          paperless:    project.t_Secrets { service: 'paperless' },
          docuseal:     project.t_Secrets { service: 'docuseal'},
          openproject:  project.t_Secrets { service: 'openproject' },
          immich:       project.t_Secrets { service: 'immich' },
          stream:       project.t_Secrets { service: 'stream' },
          convertx:     project.t_Secrets { service: 'convertx' },
          twenty:       project.t_Secrets { service: 'twenty' },
          pangolin:     project.t_Secrets { service: 'pangolin' },
        }
      },
      frappe:: {
        id:: '12ed25dd-c0d2-4a78-9b10-472fc09fe554',
        secretsMap:: {
          frappe: project.t_Secrets { service: 'frappe' },
        }
      },
      couchPotatoes:: {
        id:: 'fb1dd6a7-3924-415b-b6c3-3071fc93aaae',
        secretsMap:: {
          'couch-potatoes-website': project.t_Secrets { service: 'couch-potatoes-website', projectPath: '/website', outFile: 'client_couch-potatoes_website.env' },
        }
      },
      stackform:: {
        id:: '15d61370-a2ec-4993-9bbd-3774a63f7b94',
        secretsMap:: {
          'stackform-website': project.t_Secrets { service: 'stackform-website', projectPath: '/website', outFile: 'stackform_website.env' }, // TODO: Delete, no longer used
        }
      },
      infra:: {
        id:: '86324d9b-3dd7-49d4-b252-69228c5ee0c7',
        secretsMap:: {
          cfApiDnsToken:    project.t_Secrets { service: 'cloudflare__dns-api-token', projectPath: '/traefik' },
          zerobyte:         project.t_Secrets { service: 'zerobyte' },
          arcane:           project.t_Secrets { service: 'arcane' }, // TODO: delete, stale
          infisical:        project.t_Secrets { service: 'infisical' },
          authentik:        project.t_Secrets { service: 'authentik' },
          grist:            project.t_Secrets { service: 'grist' }, // TODO: delete, stale
          forgejo:          project.t_Secrets { service: 'forgejo' },
          gitea:            project.t_Secrets { service: 'gitea' }, // TODO: delete, stale
          komodoMcp:        project.t_Secrets { service: 'komodo-mcp' },
          woodpecker:       project.t_Secrets { service: 'woodpecker' },
          homarr:           project.t_Secrets { service: 'homarr' },
          tsGateway:        project.t_Secrets { service: 'tsGateway', projectPath: '/tailscale/containers', outFile: 'ts-gateway.env' },
          newt:             project.t_Secrets { service: 'newt', projectPath: '/hosts/${AGENT_HOST}/newt' },
          komodo:           project.t_Secrets { service: 'komodo', outFile: 'komodo_core.env' },
          cloudflared:      project.t_Secrets { service: 'cloudflared', projectPath: '/hosts/${AGENT_HOST}/cloudflared' },
          databasus:        project.t_Secrets { service: 'databasus', outFile: 'databasus_secret.key', type: 'raw', key: 'SECRET_KEY' },
          pangolinClient:   project.t_Secrets { service: 'pangolinClient', projectPath: '/hosts/${AGENT_HOST}/pangolin_client', outFile: 'pangolin_client.env' }, // TODO: delete, stale
        }
      },
    },
    
    // TODO: refactor out of code
    // catalog:: {
    //   # Catalogue of every stack the Infisical agent can render; services.jsonnet generates
    //   # one templates/<svc>.yaml fragment per entry, a host opts in via AGENT_SERVICES. Fields:
    //   #   dest: output filename under /dev/shm/. Reference it as `path` (below), never retype it.
    //   #   type: dump = whole folder, secret names already match env-var names.
    //   #         map  = explicit renames via `keys` ({ OUTPUT_ENV_VAR: 'infisical-secret-name' }).
    //   #         raw  = single secret's raw value (no KEY= prefix) via `key`.
    //   #   env:  Infisical environment slug; defaults to 'prod' when omitted.
    //   postgres:
    //   { project: 'apps', folder: '/postgres', dest: 'postgres.env', type: 'dump' },

    //   paperless:
    //   { project: 'apps', folder: '/paperless', dest: 'paperless.env', type: 'dump' },

    //   docuseal:
    //   { project: 'apps', folder: '/docuseal', dest: 'docuseal.env', type: 'dump' },

    //   openproject:
    //   { project: 'apps', folder: '/openproject', dest: 'openproject.env', type: 'dump' },

    //   immich:
    //   { project: 'apps', folder: '/immich', dest: 'immich.env', type: 'dump' },

    //   stream:
    //   { project: 'apps', folder: '/stream', dest: 'stream.env', type: 'dump' },

    //   convertx:
    //   { project: 'apps', folder: '/convertx', dest: 'convertx.env', type: 'dump' },

    //   twenty:
    //   { project: 'apps', folder: '/twenty', dest: 'twenty.env', type: 'dump' },

    //   pangolin:
    //   { project: 'apps', folder: '/pangolin', dest: 'pangolin.env', type: 'dump' },

    //   frappe:
    //   { project: 'frappe', folder: '/frappe', dest: 'frappe.env', type: 'dump' },

    //   'couch-potatoes-website':
    //   { project: 'couchPotatoes', folder: '/website', dest: 'client_couch-potatoes_website.env', type: 'dump' },

    //   'stackform-website':
    //   { project: 'stackform', folder: '/website', dest: 'stackform_website.env', type: 'dump' },

    //   'cloudflare__dns-api-token':
    //   { project: 'infra', folder: '/traefik', dest: 'cloudflare__dns-api-token.env', type: 'dump' },

    //   zerobyte:
    //   { project: 'infra', folder: '/zerobyte', dest: 'zerobyte.env', type: 'dump' },
      
    //   arcane:
    //   { project: 'infra', folder: '/arcane', dest: 'arcane.env', type: 'dump' },

    //   infisical:
    //   { project: 'infra', folder: '/infisical', dest: 'infisical.env', type: 'dump' },

    //   authentik:
    //   { project: 'infra', folder: '/authentik', dest: 'authentik.env', type: 'dump' },

    //   grist:
    //   { project: 'infra', folder: '/grist', dest: 'grist.env', type: 'dump' },

    //   forgejo:
    //   { project: 'infra', folder: '/forgejo', dest: 'forgejo.env', type: 'dump' },

    //   gitea:
    //   { project: 'infra', folder: '/gitea', dest: 'gitea.env', type: 'dump' },

    //   'komodo-mcp':
    //   { project: 'infra', folder: '/komodo-mcp', dest: 'komodo-mcp.env', type: 'dump' },

    //   woodpecker:
    //   { project: 'infra', folder: '/woodpecker', dest: 'woodpecker.env', type: 'dump' },
      
    //   'tsGateway':
    //   { project: 'infra', folder: '/tailscale/containers', dest: 'ts-gateway.env', type: 'dump' },

    //   newt:
    //   { project: 'infra', folder: '/hosts/${AGENT_HOST}/newt', dest: 'newt.env', type: 'dump' },
      
    //   komodo:
    //   { project:  'infra', folder: '/komodo', dest: 'komodo_core.env', type: 'dump' },
      
    //   cloudflared:
    //   { project:  'infra', folder: '/hosts/${AGENT_HOST}/cloudflared', dest: 'cloudflared.env', type: 'dump' },
      
    //   databasus:
    //   { project: 'infra', folder: '/databasus', dest: 'databasus_secret.key', type: 'raw', key: 'SECRET_KEY' },

    //   homarr:
    //   { project: 'infra', folder: '/homarr', dest: 'homarr.env', type: 'dump'},
      
    //   pangolinClient:
    //   { project: 'infra', folder: '/hosts/${AGENT_HOST}/pangolin_client', dest: 'pangolin_client.env', type: 'dump'},
    // },

  },
}
