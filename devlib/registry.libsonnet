// Single source of truth for every name that crosses a stack boundary.
//
// Reference by KEY — `reg.endpoint.postgres.host.addr` fails at compile time on a typo,
// where 'host.docker.internal:6109' fails silently at runtime with a wrong or empty value.
local c = import 'collections.libsonnet';
local t = import 'templates.libsonnet';

{
  // The host inventory. `ip` is the WireGuard address: there is no cluster DNS, so a
  // cross-host reference dials it directly.
  hosts:: {
    // ── Main cluster ──
    littlebuddy:: { ip:: '10.100.0.21', aka:: ['controlplane'], edge:: true },
    paiki:: { ip:: '10.100.0.22', dns:: 'plexyandiknowit', aka:: ['plex'], edge:: true },
    biggy:: { ip:: '10.100.0.23' },
    bill:: { ip:: '10.100.0.25', edge:: true },
    // ── VPS ──
    maboi:: { ip:: '10.100.0.101', edge:: true },
    rick:: { ip:: '10.100.0.102', edge:: true },
    // ── NAS ──
    nas:: { ip:: '100.91.182.94' },
  },

  endpoint:: {
    postgres:: {
      // The shared cluster. Its container name is not the <project>_<role> convention —
      // other stacks already dial `postgres-db` — so the stack overrides container_name
      // with this value rather than the other way round.
      container:: t.Endpoint.Container { host:: 'postgres-db', port:: '5432' },
      host:: t.Endpoint.Host { port:: '6109' },
    },

    infisical:: {
      container:: t.Endpoint.Container { host:: 'infisical_app', port:: '8080' },
      // 18006 belongs to authentik (authentik.ktbcloud.com -> 127.0.0.1:18006 on rick).
      // The two only collide once they share a host, which the lilbud -> rick control-plane
      // move does.
      host:: t.Endpoint.Host { port:: '18043' },
      public:: t.Endpoint.Public { sub:: 'infisical', domain:: c.domain.ktbinternal },
    },

    pangolin:: {
      public:: t.Endpoint.Public { sub:: 'pangolin', domain:: c.domain.ktbcloud },
    },

    authentik:: {
      // The display name an OIDC client shows on its login button.
      name:: 'Authentik',
      public:: t.Endpoint.Public { local pub = self,
        sub:: 'authentik',
        domain:: c.domain.ktbcloud,
        oidc:: {
          authorize:: pub.url + '/application/o/authorize/',
          issuer(slug):: pub.url + '/application/o/' + slug + '/',
        },
      },
    },
  },

  // Directories one stack owns and another reads. A path only lives here once a second
  // stack needs it; everything private to a stack stays in that stack's own file.
  dirs:: {
    // file-browser-quantum serves this tree; terraria keeps its world under it.
    fileBrowser:: { local root = c.dirs.rootlessSrv + '/file-browser-quantum',
      root:: root,
      data:: root + '/data',
      shared:: root + '/shared',
      cache:: root + '/cache',
    },
  },

  networks:: {
    shared:: {
      postgresDB:: t.SharedNetwork { base:: 'postgres_db' },
      paperlessDB:: t.SharedNetwork { base:: 'paperless_db' },
      infisicalDB:: t.SharedNetwork { base:: 'infisical_db' },
      forgejoDB:: t.SharedNetwork { base:: 'forgejo_db' },
      tsGateway:: t.SharedNetwork { base:: 'ts-gateway' },
      caddy:: t.SharedNetwork { base:: 'caddy' },
    },
  },

  // Every secret bundle infisical-agent can render, keyed by the name a stack asks for.
  // The value is the filename under collections.dirs.secrets — reach it with lib.Secret,
  // never by retyping the path. Producer side is the agent's own templates/<key>.yaml.
  secrets::
    // The common case: the bundle renders to '<key>.env'.
    {
      [key]: key + '.env'
      for key in [
        'arcane',
        'authentik',
        'cloudflare__dns-api-token',
        'cloudflared',
        'convertx',
        'docuseal',
        'forgejo',
        'frappe',
        'gitea',
        'grist',
        'homarr',
        'immich',
        'infisical',
        'komodo-mcp',
        'newt',
        'openproject',
        'pangolin',
        'paperless',
        'postgres',
        'stream',
        'twenty',
        'woodpecker',
        'zerobyte',
      ]
    }
    // The handful whose output name is not the key: a name another system already reads,
    // or a file that is not an env file at all.
    + {
      'couch-potatoes-website': 'client_couch-potatoes_website.env',
      'stackform-website': 'stackform_website.env',
      komodo: 'komodo_core.env',
      'pangolin-client': 'pangolin_client.env',
      'ts-gateway': 'ts-gateway.env',
      databasus: 'databasus_secret.key',
    },
}
