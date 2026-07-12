// Renders to controller.yaml, mounted READ-ONLY on EVERY host at
// /etc/traefik/dynamic/controller.yaml. Edit this source (and the catalog it reads), not the
// yaml — safe_dump strips comments, so all operational knowledge lives HERE.
//
// Routes each single-label service to whichever host actually runs it, re-encrypting to that
// host's own Traefik on :443.
//
// Loop-free & portable: per-service routers are priority:1, so a service running locally is
// still served by its own (higher-priority) docker-label router — only REMOTE requests fall
// through here. The table is identical on every host; promotion = repointing the wildcard
// DNS at another host, no redeploy. A host DNS doesn't point at just sits dormant.
//
// ⚠️ If a single-label service is down on its home host, its docker router vanishes and the
// request falls through to the priority:1 router here, which points back at the SAME host —
// looping (this froze littlebuddy on 2026-06-29). The controller-hop middleware + priority:2
// controller-loop-sink router below break that loop with a fast 502.
//
// service->host map and host->IP map are DATA (registry.libsonnet: controllerServices +
// edgeHosts) — add a service / move a host there and re-render.

local reg = import 'registry.libsonnet';

local hosts = reg.server.hosts;
local catalog = reg.controllerServices;

local fqdn(svc, cfg) = (if std.objectHas(cfg, 'sub') then cfg.sub else svc) + '.' + reg.domains.ktbinternal;

local backendFor(svc, cfg) = if std.objectHas(cfg, 'direct') then svc + '-direct' else 'host-' + cfg.home;

local directSvcs = [svc for svc in std.objectFields(catalog) if std.objectHas(catalog[svc], 'direct')];

{
  'controller.yaml': {
    http: {
      routers: {
        // Catches a request that already took the central hop (carries X-Controller-Hop,
        // stamped by controller-hop below) but is back here with no local docker router —
        // i.e. the target service is down on its home host. priority:2 beats the priority:1
        // host routers but loses to any real docker-label router (priority = rule length ≫ 2).
        // Dead-ends to a fast 502 instead of looping back into the table.
        'controller-loop-sink': {
          rule: 'Header(`X-Controller-Hop`, `1`)',
          entryPoints: ['websecure'],
          service: 'controller-loop-sink',
          priority: 2,
          tls: {},
        },
      } + {
        // One entry per single-label service. priority:1 so a locally-run service still
        // wins via its own docker router on the controller host.
        [svc]: {
          rule: 'Host(`' + fqdn(svc, catalog[svc]) + '`)',
          entryPoints: ['websecure'],
          service: backendFor(svc, catalog[svc]),
          priority: 1,
          middlewares: ['controller-hop'],
          tls: {},
        }
        for svc in std.objectFields(catalog)
      },

      middlewares: {
        // Stamps the central re-encrypt hop so controller-loop-sink can tell a request has
        // already passed through this table once.
        'controller-hop': {
          headers: {
            customRequestHeaders: {
              'X-Controller-Hop': '1',
            },
          },
        },
      },

      services: {
        // 127.0.0.1:1 has nothing listening, so Traefik fails fast with 502 instead of
        // retrying — better a quick 502 than a host meltdown.
        'controller-loop-sink': {
          loadBalancer: {
            passHostHeader: false,
            servers: [{ url: 'http://127.0.0.1:1' }],
          },
        },
      } + {
        // One per edge host (those running Traefik), generated for ALL of them (even ones
        // with no routers today) so the table stays uniform and portable. Non-edge hosts in
        // the registry (NAS, Home Assistant, etc.) are skipped — they have no Traefik to
        // re-encrypt to. passHostHeader keeps the original Host so the target Traefik matches
        // its own router.
        ['host-' + h]: {
          loadBalancer: {
            passHostHeader: true,
            serversTransport: 'host-reencrypt',
            servers: [{ url: 'https://' + hosts[h].ip + ':443' }],
          },
        }
        for h in std.objectFields(hosts)
        if std.objectHas(hosts[h], 'edge') && hosts[h].edge
      } + {
        // Plex is host-mode on its home host (:32400), not behind that host's Traefik, so it
        // can't use the host-* re-encrypt backend — routes straight to the Plex process instead
        // (plain HTTP, no serversTransport, so no loop path back into this table).
        [svc + '-direct']: {
          loadBalancer: {
            passHostHeader: true,
            servers: [{
              url: (if std.objectHas(catalog[svc].direct, 'scheme') then catalog[svc].direct.scheme else 'http')
                   + '://' + hosts[catalog[svc].home].ip + ':' + std.toString(catalog[svc].direct.port),
            }],
          },
        }
        for svc in directSvcs
      },

      serversTransports: {
        // Opens a NEW, VERIFIED TLS connection to the target host's Traefik :443 — each host's
        // own Let's Encrypt wildcard validates against system CA roots, no insecureSkipVerify.
        //
        // We connect by raw Tailscale IP, so the default SNI would be the IP and wouldn't match
        // the cert. serverName pins the SNI to a name the wildcard covers (doesn't need to
        // resolve in DNS — SNI only). The real Host header still reaches the backend via
        // passHostHeader; SNI here only selects/validates the cert.
        //
        // REQUIRES each host to keep requesting its ACME wildcard cert — do NOT switch a host
        // to Traefik's default self-signed cert, or this verification fails by design.
        'host-reencrypt': {
          serverName: 'node.' + reg.domains.ktbinternal,
        },
      },
    },
  },
}
