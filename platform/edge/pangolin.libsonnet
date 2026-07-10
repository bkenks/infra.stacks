// The Pangolin edge, parameterized so it can run on more than one host at once.
//
// A Pangolin instance owns a whole DNS plane: it requests that zone's wildcard cert and
// answers for every Host() under it. Two instances must therefore serve DISJOINT zones —
// give them both the same `baseDomain` and they race each other on the DNS-01 challenge
// and both publish routers for the same names.
//
// `configs(o)` renders the three config files; `compose(o)` renders the compose pair.
// A stack directory is a thin entrypoint over these — see platform/edge/pangolin{,-internal}.
//
// opts:
//   stack            compose project name + default network name.
//   baseDomain       the single DNS plane this instance serves (reg.domains.*).
//   secret           reg.infisical.services entry carrying SERVER_SECRET + EMAIL_SMTP_PASS.
//                    Each instance needs its OWN entry — a shared SERVER_SECRET would let
//                    one instance mint session tokens the other accepts.
//   dataDir          bind-mount dir under <docker root>/bind-mounts. Defaults to `stack`.
//                    Pin it explicitly when an instance already has live state on disk
//                    (Gerbil's WireGuard key, Pangolin's db, acme.json) — renaming it
//                    orphans all three.
//   servesAuthentik  true on the instance colocated with Authentik: joins shared-edge and
//                    publishes the raw auth.<baseDomain> router. Off elsewhere, because
//                    shared-edge is external and owned by the authentik stack — a host
//                    without Authentik has nothing to create it, and compose refuses to
//                    start against a missing external network.
//   noReplyDomain    From: domain for Pangolin's SMTP. NOT derived from baseDomain — it has
//                    to be a domain actually verified with the SMTP provider.
local c = import 'compose.libsonnet';
local reg = import 'registry.libsonnet';

local pangolinVersion = '1.19.4';
local gerbilVersion = '1.4.2';
local traefikVersion = 'v3.6';

// Named once in traefik_config.yaml's certificatesResolvers, referenced by every https
// router in dynamic_config.yaml.
local certResolver = 'cloudflare';
local cf = { certResolver: certResolver };

// Same mirror Pangolin's installer uses (no MaxMind license key needed). Tarball
// extracts to a versioned dir (GeoLite2-<name>_<date>/) — the mv glob below matches that.
local geoliteMirror = 'https://github.com/GitSquared/node-geolite2-redist/raw/refs/heads/master/redist/';
local fetchGeolite(name) =
  'if [ ! -f /mnt/config/GeoLite2-' + name + '.mmdb ]; then ' +
  'wget -qO /tmp/geolite-' + name + '.tar.gz ' + geoliteMirror + 'GeoLite2-' + name + '.tar.gz && ' +
  'tar -xzf /tmp/geolite-' + name + '.tar.gz -C /tmp && ' +
  'mv /tmp/GeoLite2-' + name + '_*/GeoLite2-' + name + '.mmdb /mnt/config/; ' +
  'fi';

// chmod 600 on acme.json MUST run last — a preceding `chmod -R 755 /mnt/config`
// would clobber it back to 755, breaking Traefik ACME.
local initScript =
  'set -e && ' +
  'mkdir -p /mnt/config/traefik/logs /mnt/config/letsencrypt && ' +
  'touch /mnt/config/letsencrypt/acme.json && ' +
  fetchGeolite('Country') + ' && ' +
  fetchGeolite('ASN') + ' && ' +
  'chmod -R 755 /mnt/config && ' +
  'chmod 600 /mnt/config/letsencrypt/acme.json';

local defaults(o) = {
  dataDir: std.get(o, 'dataDir', o.stack),
  servesAuthentik: std.get(o, 'servesAuthentik', false),
  noReplyDomain: std.get(o, 'noReplyDomain', reg.domains.ktbinternal),
};

{
  configs(o):: (
    local d = defaults(o);
    // The Pangolin dashboard host — config.yaml's dashboard_url and sole CORS origin, and
    // the Host() every router in dynamic_config.yaml matches on.
    local host = 'pangolin.' + o.baseDomain;

    {
      'config.yaml': {
        gerbil: {
          start_port: 51820,
          base_endpoint: host,
        },

        app: {
          dashboard_url: 'https://' + host,
          log_level: 'info',
          telemetry: {
            anonymous_usage: true,
          },
        },

        // One plane per instance — see the disjoint-zones note at the top of this file.
        domains: {
          domain1: {
            base_domain: o.baseDomain,
          },
        },

        server: {
          // server.secret comes from SERVER_SECRET env (infisical-agent) — must be OMITTED
          // here, not blanked. Pangolin only applies the env override when the key is ABSENT;
          // `secret: ''` counts as "defined" and fails validation before the env var is read.
          cors: {
            origins: ['https://' + host],
            methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'],
            allowed_headers: ['X-CSRF-Token', 'Content-Type'],
            credentials: false,
          },
          maxmind_db_path: './config/GeoLite2-Country.mmdb',
          maxmind_asn_path: './config/GeoLite2-ASN.mmdb',
        },

        email: {
          smtp_host: 'smtp.resend.com',
          smtp_port: 465,
          smtp_user: 'resend',
          // smtp_pass: EMAIL_SMTP_PASS env (infisical-agent) — omitted for the same reason as server.secret.
          no_reply: 'pangolin@notify.' + d.noReplyDomain,
        },

        flags: {
          require_email_verification: true,
          disable_signup_without_invite: true,
          disable_user_create_org: false,
          allow_raw_resources: true,
        },
      },

      // Backend hostnames stay literal 'pangolin' — see the naming-deviation note in compose().
      'dynamic_config.yaml': {
        http: {
          middlewares: {
            badger: {
              plugin: {
                badger: {
                  disableForwardAuth: true,
                },
              },
            },
            'redirect-to-https': {
              redirectScheme: {
                scheme: 'https',
              },
            },
          },

          routers: {
            'main-app-router-redirect': {
              rule: 'Host(`' + host + '`)',
              service: 'next-service',
              entryPoints: ['web'],
              middlewares: ['redirect-to-https', 'badger'],
            },

            // Requests the *.<baseDomain> wildcard here (once) via Cloudflare DNS-01 — same
            // "request once, serve everywhere via SNI" trick as platform/edge/traefik files/host.yml.
            // Every other router then just needs certResolver: cloudflare with no domains block.
            'next-router': {
              rule: 'Host(`' + host + '`) && !PathPrefix(`/api/v1`)',
              service: 'next-service',
              entryPoints: ['websecure'],
              middlewares: ['badger'],
              tls: cf {
                domains: [
                  { main: o.baseDomain, sans: ['*.' + o.baseDomain] },
                ],
              },
            },

            'api-router': {
              rule: 'Host(`' + host + '`) && PathPrefix(`/api/v1`)',
              service: 'api-service',
              entryPoints: ['websecure'],
              middlewares: ['badger'],
              tls: cf,
            },

            'ws-router': {
              rule: 'Host(`' + host + '`)',
              service: 'api-service',
              entryPoints: ['websecure'],
              middlewares: ['badger'],
              tls: cf,
            },
          } + (
            if d.servesAuthentik then {
              // Authentik IdP. RAW router: no badger/SSO (Authentik is break-glass;
              // self-fronting loops). Reaches authentik_server over shared-edge (gerbil
              // joins it in compose(); Traefik shares gerbil's netns). No `domains` block —
              // next-router already requested this zone's wildcard.
              'authentik-router': {
                rule: 'Host(`auth.' + o.baseDomain + '`)',
                service: 'authentik-service',
                entryPoints: ['websecure'],
                tls: cf,
              },
            } else {}
          ),

          services: {
            'next-service': {
              loadBalancer: { servers: [{ url: 'http://pangolin:3002' }] },  // Next.js server
            },
            'api-service': {
              loadBalancer: { servers: [{ url: 'http://pangolin:3000' }] },  // API/WebSocket server
            },
          } + (
            if d.servesAuthentik then {
              'authentik-service': {
                loadBalancer: { servers: [{ url: 'http://authentik_server:9000' }] },  // over shared-edge
              },
            } else {}
          ),
        },

        tcp: {
          serversTransports: {
            'pp-transport-v1': { proxyProtocol: { version: 1 } },
            'pp-transport-v2': { proxyProtocol: { version: 2 } },
          },
        },
      },

      // CF_DNS_API_TOKEN is read by the lego cloudflare provider from the container env
      // (compose()) — deliberately not set here, so no secret lands in git.
      'traefik_config.yaml': {
        api: {
          insecure: true,
          dashboard: true,
        },

        providers: {
          http: {
            endpoint: 'http://pangolin:3001/api/v1/traefik-config',
            pollInterval: '5s',
          },
          file: {
            filename: '/etc/traefik/dynamic_config.yml',
          },
        },

        experimental: {
          plugins: {
            badger: {
              moduleName: 'github.com/fosrl/badger',
              version: 'v1.4.1',
            },
          },
        },

        log: {
          level: 'INFO',
          format: 'common',
          maxSize: 100,
          maxBackups: 3,
          maxAge: 3,
          compress: true,
        },

        certificatesResolvers: {
          [certResolver]: {
            acme: {
              email: 'briankenkel.t@gmail.com',
              storage: '/letsencrypt/acme.json',
              dnsChallenge: {
                provider: 'cloudflare',
                // ktbinternal.com resolves to a private (Tailscale) A record internally, so
                // use public resolvers for the _acme-challenge TXT propagation check.
                resolvers: ['1.1.1.1:53', '1.0.0.1:53'],
              },
            },
          },
        },

        entryPoints: {
          web: { address: ':80' },
          websecure: {
            address: ':443',
            transport: {
              respondingTimeouts: { readTimeout: '30m' },
            },
            http3: { advertisedPort: 443 },
            http: {
              tls: cf,
              encodedCharacters: {
                allowEncodedSlash: true,
                allowEncodedQuestionMark: true,
              },
            },
          },
        },

        serversTransport: {
          insecureSkipVerify: true,
        },

        ping: {
          entryPoint: 'web',
        },
      },
    }
  ),

  // Naming deviation: service keys/container_names are literal ('pangolin', 'gerbil',
  // 'traefik'), not run through the naming helper — Pangolin/Gerbil hardcode each other's
  // hostnames in their startup flags, and configs()'s backend URLs assume these exact names;
  // renaming breaks service discovery. Traefik's `network_mode: service:gerbil` also requires
  // gerbil's compose key to be literally 'gerbil'. Safe across instances because no two run
  // on the same host (they'd collide on 80/443 regardless).
  //
  // Storage: one shared host dir (bind mounts, not named volumes — Pangolin/Gerbil/Traefik
  // expect to read/write this tree by upstream design). `init` creates the tree/perms first;
  // configs()-rendered files layer on as read-only bind mounts (git-tracked); runtime state
  // (keys, certs, GeoLite DBs, logs, db) stays host-only.
  compose(o):: (
    local d = defaults(o);
    local s = c.stack(o.stack);
    local configDir = reg.server.dir.docker.root + reg.server.dir.docker.bindmounts + '/' + d.dataDir + '/config';

    local manifest = {
      name: o.stack,

      services: {
        // One-shot: creates config tree/perms + GeoLite mmdbs (skipped after first run).
        // Doesn't provision files/ content — that's the bind mounts below.
        init: {
          image: 'docker.io/library/busybox:1.37.0',
          container_name: o.stack + '_init',
          volumes: [configDir + ':/mnt/config'],
          command: ['sh', '-c', initScript],
          restart: 'no',
        },

        pangolin: {
          image: 'docker.io/fosrl/pangolin:' + pangolinVersion,
          container_name: 'pangolin',
          restart: 'unless-stopped',
          depends_on: { init: { condition: 'service_completed_successfully' } },
          mem_limit: '2g',
          mem_reservation: '512m',
          volumes: [
            configDir + ':/app/config',
            // files/configs.jsonnet -> config.yaml (git-tracked); container path keeps the
            // .yml name Pangolin expects. privateConfig.yml is hand-maintained (not generated).
            './files/config.yaml:/app/config/config.yml:ro',
            './files/privateConfig.yml:/app/config/privateConfig.yml:ro',
          ],
          environment: {
            // Overrides server.secret / email.smtp_pass (config.yml omits both).
            SERVER_SECRET: '${SERVER_SECRET:?err}',
            EMAIL_SMTP_PASS: '${EMAIL_SMTP_PASS:?err}',
          },
          healthcheck: {
            test: ['CMD', 'curl', '-f', 'http://localhost:3001/api/v1/'],
            interval: '10s',
            timeout: '10s',
            retries: 15,
          },
          networks: { default: { aliases: ['pangolin'] } },
        },

        gerbil: {
          image: 'docker.io/fosrl/gerbil:' + gerbilVersion,
          container_name: 'gerbil',
          restart: 'unless-stopped',
          depends_on: {
            init: { condition: 'service_completed_successfully' },
            pangolin: { condition: 'service_healthy' },
          },
          command: [
            '--reachableAt=http://gerbil:3004',
            '--generateAndSaveKeyTo=/var/config/key',
            '--remoteConfig=http://pangolin:3001/api/v1/',
          ],
          volumes: [configDir + ':/var/config'],
          cap_add: ['NET_ADMIN', 'SYS_MODULE'],
          ports: [
            '51820:51820/udp',
            '21820:21820/udp',
            '443:443',
            '443:443/udp',  // HTTP/3 QUIC
            '80:80',
          ],
          // On the Authentik-colocated instance, also joins shared-edge so Traefik
          // (network_mode: service:gerbil, i.e. it shares gerbil's netns) can reach
          // authentik_server:9000 for the raw auth router in files/dynamic_config.yaml.
          // authentik owns this network; pangolin is a consumer (the external decl is in
          // the top-level networks block below via network.join).
          networks: { default: { aliases: ['gerbil'] } }
                    + (if d.servesAuthentik then s.network.attach(reg.sharedNetworks.edge.name, 'gerbil') else {}),
        },

        // network_mode: service:gerbil — Traefik can't also declare networks: (Compose
        // disallows combining the two on the same service).
        traefik: {
          image: 'docker.io/library/traefik:' + traefikVersion,
          container_name: 'traefik',
          restart: 'unless-stopped',
          network_mode: 'service:gerbil',
          depends_on: {
            init: { condition: 'service_completed_successfully' },
            pangolin: { condition: 'service_healthy' },
          },
          command: ['--configFile=/etc/traefik/traefik_config.yml'],
          environment: {
            // CF_DNS_API_TOKEN for DNS-01 ACME (lego reads from env); shared with
            // platform/edge/traefik, not duplicated into this stack's own env. The token
            // must be scoped to this instance's baseDomain zone.
            CF_DNS_API_TOKEN: '${CF_DNS_API_TOKEN:?err}',
          },
          volumes: [
            // files/configs.jsonnet -> *.yaml; container paths keep the .yml names traefik expects.
            './files/traefik_config.yaml:/etc/traefik/traefik_config.yml:ro',
            './files/dynamic_config.yaml:/etc/traefik/dynamic_config.yml:ro',
            configDir + '/letsencrypt:/letsencrypt',
            configDir + '/traefik/logs:/var/log/traefik',
          ],
        },
      },

      networks: {
        default: { name: o.stack, driver: 'bridge', enable_ipv6: true },
      } + (if d.servesAuthentik then s.network.join(reg.sharedNetworks.edge) else {}),
    };

    c.render(o.stack, manifest, [
      o.secret.path,
      reg.infisical.services['cloudflare__dns-api-token'].path,
    ])
  ),
}
