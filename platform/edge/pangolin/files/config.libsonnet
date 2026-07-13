// The shape of Pangolin's three config files, parameterized by ONE knob: `urlDomain`,
// the domain this instance is reached at (host = pangolin.<urlDomain>). Two hosts run the
// SAME stack, differing only by this — cloud/ passes ktbcloud, internal/ passes ktbinternal,
// and ../compose.jsonnet mounts whichever the ${PANGOLIN_VARIANT} env var selects.
//
// Everything else is identical across instances: both DNS planes, both wildcard certs, the
// Authentik router. The two instances don't know about each other.
//
// safe_dump strips comments, so the yaml carries only a DO-NOT-EDIT header and all
// operational knowledge lives HERE.
local reg = import 'registry.libsonnet';

// The two DNS planes every instance serves. config.yaml declares them as domain1/domain2;
// dynamic_config.yaml requests one wildcard cert per plane (request once, serve everywhere
// via SNI). Fixed — NOT the per-instance knob, so both instances hold both certs.
local baseDomain = reg.domains.ktbinternal;
local cloudDomain = reg.domains.ktbcloud;

// Named once in traefik_config.yaml's certificatesResolvers, referenced by every https
// router in dynamic_config.yaml.
local certResolver = 'cloudflare';
local cf = { certResolver: certResolver };

function(urlDomain)
  // THE knob. The domain this instance is reached at: config.yaml's dashboard_url and sole
  // CORS origin, gerbil's base_endpoint, and the Host() every dashboard router matches on.
  local host = 'pangolin.' + urlDomain;
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

      // Cert resolver stamped onto routers Pangolin generates for dashboard-created
      // Resources (the @http provider). Defaults to 'letsencrypt' when unset, which no
      // certificatesResolver here defines — must match traefik_config.yaml's 'cloudflare'.
      traefik: {
        cert_resolver: certResolver,
      },

      domains: {
        domain1: {
          base_domain: baseDomain,
        },
        // Public plane (Authentik + *.ktbcloud.com Resources); wildcard cert is
        // requested once by authentik-router in dynamic_config.yaml below.
        domain2: {
          base_domain: cloudDomain,
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
        no_reply: 'pangolin@notify.' + baseDomain,
      },

      flags: {
        require_email_verification: true,
        disable_signup_without_invite: true,
        disable_user_create_org: false,
        allow_raw_resources: true,
      },
    },

    // Backend hostnames stay literal 'pangolin' — see compose.jsonnet's naming-deviation note.
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
                { main: baseDomain, sans: ['*.' + baseDomain] },
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

          // Authentik IdP — the one public entrypoint on the ktbcloud.com plane. RAW
          // router: no badger/SSO (Authentik is break-glass; self-fronting loops).
          // Reaches authentik_server over shared-edge (gerbil joins it in compose.jsonnet;
          // Traefik shares gerbil's netns). Also carries the ktbcloud.com wildcard cert
          // request (request once, serve all via SNI).
          'authentik-router': {
            rule: 'Host(`auth.' + cloudDomain + '`)',
            service: 'authentik-service',
            entryPoints: ['websecure'],
            tls: cf {
              domains: [
                { main: cloudDomain, sans: ['*.' + cloudDomain] },
              ],
            },
          },
        },

        services: {
          'next-service': {
            loadBalancer: { servers: [{ url: 'http://pangolin:3002' }] },  // Next.js server
          },
          'api-service': {
            loadBalancer: { servers: [{ url: 'http://pangolin:3000' }] },  // API/WebSocket server
          },
          'authentik-service': {
            loadBalancer: { servers: [{ url: 'http://authentik_server:9000' }] },  // over shared-edge
          },
        },
      },

      tcp: {
        serversTransports: {
          'pp-transport-v1': { proxyProtocol: { version: 1 } },
          'pp-transport-v2': { proxyProtocol: { version: 2 } },
        },
      },
    },

    // CF_DNS_API_TOKEN is read by the lego cloudflare provider from the container env
    // (compose.jsonnet) — deliberately not set here, so no secret lands in git.
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
        'tcp-22': { address: ":22/tcp" },
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
