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
        container:: service.Container { name:: 'postgres-db', port:: '5432' },
        host::      service.Host      { on:: host.littlebuddy, port:: '6109' },
      },

      infisical:: serviceGroup.Service {
        local service = self,
        container:: service.Container { name:: 'infisical-app', port:: '8080' },
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

  infisical:: {
    // Where the infisical-secrets compose provider reaches the server. The control-plane
    // alias rather than the serviceGroup host's own name: every host in the fleet resolves
    // it, including the ones that deploy before they know which box is the control plane.
    address:: 'http://%s:%s' % [
      $.endpoint.hostGroup.controlplane.ref,
      $.endpoint.serviceGroup.infisical.host.port,
    ],

    // The Infisical projects secrets live in. Only the ids are global: a bundle's folder
    // path is read by exactly one stack, so it is written in that stack rather than
    // mirrored here, and lib.SecretsProvider pairs the two.
    project:: {
      apps::          '2f0eb3d1-3e2a-4ce7-8060-5e47ad877e47',
      frappe::        '12ed25dd-c0d2-4a78-9b10-472fc09fe554',
      couchPotatoes:: 'fb1dd6a7-3924-415b-b6c3-3071fc93aaae',
      stackform::     '15d61370-a2ec-4993-9bbd-3774a63f7b94',
      infra::         '86324d9b-3dd7-49d4-b252-69228c5ee0c7',
    },
  },
}
