// traefik_config.jsonnet — SOURCE for traefik_config.yaml (Traefik static
// config: entrypoints, providers, ACME resolver, plugins).
//
// Renders (via .jsonnet/render.py) to traefik_config.yaml, mounted read-only
// into the traefik container at /etc/traefik/traefik_config.yml (see
// compose.stack.jsonnet — the container path keeps the .yml name that traefik's
// --configFile flag points at; only the git-tracked source basename is .yaml).
// DO NOT edit traefik_config.yaml — edit this source and re-render.
//
// ⚠️ safe_dump strips YAML comments, so traefik_config.yaml carries only the
// render.py DO-NOT-EDIT header — all operational knowledge lives HERE.
//
// TLS certificates: Cloudflare DNS-01 ACME (Let's Encrypt) — same mechanism as
// this repo's platform/edge/traefik. CF_DNS_API_TOKEN (Zone:DNS:Edit +
// Zone:Read on the ktbinternal.com zone) is read by the lego cloudflare provider
// from the container environment (compose.stack.jsonnet) — deliberately not set
// here, so no secret lands in git. Which (wildcard) cert gets requested is in
// dynamic_config.jsonnet; once issued, Traefik serves it via SNI so every
// router — including ones Pangolin itself adds dynamically for new Resources —
// just needs tls: { certResolver: cloudflare }.
{
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
    cloudflare: {
      acme: {
        email: 'briankenkel.t@gmail.com',
        storage: '/letsencrypt/acme.json',
        dnsChallenge: {
          provider: 'cloudflare',
          // ktbinternal.com resolves to a private (Tailscale) A record
          // internally, so use public resolvers for the _acme-challenge TXT
          // propagation check.
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
        tls: { certResolver: 'cloudflare' },
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
}
