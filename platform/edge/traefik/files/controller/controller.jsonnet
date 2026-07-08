// controller.jsonnet — SOURCE for controller.yaml (the central routing table).
//
// Renders (via .jsonnet/render.sh, special-cased to .yml) to controller.yaml,
// which is mounted READ-ONLY on EVERY host at /etc/traefik/dynamic/controller.yaml
// (see platform/edge/traefik/compose.stack.jsonnet). DO NOT edit controller.yaml —
// edit this source (and the catalog it reads) and re-render.
//
// ⚠️ safe_dump strips YAML comments, so the rendered controller.yaml carries only
// the render.sh "GENERATED … DO NOT EDIT" header — ALL the operational knowledge
// (loop-guard mechanism, the 2026-06-29 incident, the priority/portability story)
// now lives HERE, in these jsonnet comments. Read this file, not the YAML.
//
// ── What this table does ────────────────────────────────────────────────────
// It routes each single-label service to whichever host actually runs it,
// re-encrypting to that host's own Traefik on :443.
//
// How it stays loop-free and portable:
//   - Per-service routers are priority:1 (lowest). On ANY host, a service that
//     runs locally is still served by its own docker-label router (default
//     priority, which is higher), so only REMOTE services fall through here.
//   - A host that *.<reg.domains.ktbinternal> DNS isn't pointed at never receives these Host()
//     requests, so the table sits dormant there — harmless. Whichever host DNS
//     points at becomes the active central router.
//   - The table is identical on every host, so promotion is just repointing the
//     *.<reg.domains.ktbinternal> wildcard DNS at another host. No redeploy, no role flag.
//   - The host running each service still serves it locally via its docker
//     labels, unchanged — this only adds the central front door.
//
// ⚠️ The priority story only holds while the local service is UP. If a
// single-label service is stopped/redeployed on its home host its docker router
// vanishes, the request falls through to the priority:1 router here, which points
// back at the SAME host — and loops, melting the host (froze littlebuddy on
// 2026-06-29 via the infisical-agents' polling). The controller-hop middleware +
// priority:2 controller-loop-sink router below break that loop (fast 502).
//
// The service->host map and the host->IP map are DATA now (registry.libsonnet:
// controllerServices + edgeHosts). Add a service / move a host there and re-render.

local reg = import 'registry.libsonnet';

local hosts = reg.server.hosts;
local catalog = reg.controllerServices;

// sub.<reg.domains.ktbinternal> — sub defaults to the service key when not overridden.
local fqdn(svc, cfg) = (if std.objectHas(cfg, 'sub') then cfg.sub else svc) + '.' + reg.domains.ktbinternal;

// Backend id for a service: its dedicated `<svc>-direct` backend when `direct` is
// set (Plex), else the shared `host-<home>` re-encrypt backend.
local backendFor(svc, cfg) = if std.objectHas(cfg, 'direct') then svc + '-direct' else 'host-' + cfg.home;

// Services that carry a `direct` backend (Plex): reached straight, not re-encrypted.
local directSvcs = [svc for svc in std.objectFields(catalog) if std.objectHas(catalog[svc], 'direct')];

{
  http: {
    routers: {
      // ── Loop guard ──────────────────────────────────────────────────────
      // Catches any request that has ALREADY taken the central hop (carries
      // X-Controller-Hop, stamped by controller-hop below) yet is back here with
      // no local docker router to serve it — i.e. the target service is down on
      // its home host. priority:2 beats the priority:1 host routers (so it wins
      // over a second fall-through) but loses to any real docker-label router
      // (priority = rule length ≫ 2), so a healthy service is unaffected.
      // Dead-ends to a fast 502 instead of looping back into the table. Without
      // this, a stopped single-label service melts the host (froze littlebuddy
      // 2026-06-29).
      'controller-loop-sink': {
        rule: 'Header(`X-Controller-Hop`, `1`)',
        entryPoints: ['websecure'],
        service: 'controller-loop-sink',
        priority: 2,
        tls: {},
      },
    } + {
      // ── Per-service routers (generated from controllerServices) ───────────
      // ONE entry per single-label service: rule is its public name, service is
      // the backend for the host that runs it. priority:1 so a locally-run
      // service wins via its own docker router on the controller host.
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
      // Stamps the central re-encrypt hop so the loop guard (controller-loop-sink)
      // can tell a request has already passed through this table once. Attached to
      // every host-routing router above; harmless extra request header on backend.
      'controller-hop': {
        headers: {
          customRequestHeaders: {
            'X-Controller-Hop': '1',
          },
        },
      },
    },

    services: {
      // Dead-end for looped requests (see controller-loop-sink router / header
      // comment). 127.0.0.1:1 has nothing listening, so Traefik fails fast with
      // 502 — no retry, no per-hop connection/goroutine buildup. Better a quick
      // 502 than a host meltdown.
      'controller-loop-sink': {
        loadBalancer: {
          passHostHeader: false,
          servers: [{ url: 'http://127.0.0.1:1' }],
        },
      },
    } + {
      // ── Host backends (one per edgeHosts entry) ───────────────────────────
      // Identical on every host so this file is portable. Re-encrypts to the
      // host's Traefik :443; passHostHeader keeps the original Host so that
      // Traefik matches its own router. Generated for ALL edge hosts (even ones
      // with no routers today, e.g. maboi/bill) so the table stays uniform.
      ['host-' + h]: {
        loadBalancer: {
          passHostHeader: true,
          serversTransport: 'host-reencrypt',
          servers: [{ url: 'https://' + hosts[h].ip + ':443' }],
        },
      }
      for h in std.objectFields(hosts)
    } + {
      // ── Direct backends (Plex) ────────────────────────────────────────────
      // Plex is host-mode on its home host (:32400) — NOT behind that host's
      // Traefik, so it can't use the host-* re-encrypt backend. It routes
      // straight to the Plex process: plain HTTP, NO serversTransport, so no loop
      // path back into this table (the backend is Plex itself, never a host
      // Traefik that could bounce back here). IP derives from the home host in
      // edgeHosts, so a host-IP move follows automatically.
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
      // The controller terminates the public *.<reg.domains.ktbinternal> TLS, then opens a NEW,
      // VERIFIED TLS connection to the target host's Traefik :443. Each host serves
      // its own publicly-trusted Let's Encrypt *.<reg.domains.ktbinternal> wildcard there, so the
      // connection is validated against the system CA roots (LE ships in the Traefik
      // image's trust store) — no insecureSkipVerify, no MITM window on the
      // cross-host hop even within Tailscale.
      //
      // We connect by raw Tailscale IP (no MagicDNS), so the default SNI would be
      // the IP and wouldn't match the cert. `serverName` pins the TLS SNI/validation
      // name to a name the wildcard covers; the upstream presents *.<reg.domains.ktbinternal> for
      // it and verification passes. (It need not resolve in DNS — it's only the
      // SNI.) The HTTP Host header is still the real service name via passHostHeader,
      // which is what the upstream routes on; SNI only selects/validates the cert.
      //
      // serverName follows reg.domains.ktbinternal (node.<reg.domains.ktbinternal>) so the domain migration
      // carries it automatically — the wildcard covers node.<reg.domains.ktbinternal> by
      // definition. REQUIRES each host to keep its ACME *.<reg.domains.ktbinternal> cert (they all
      // request it). Do NOT switch hosts to Traefik's default self-signed cert, or
      // this verification will fail by design.
      'host-reencrypt': {
        serverName: 'node.' + reg.domains.ktbinternal,
      },
    },
  },
}
