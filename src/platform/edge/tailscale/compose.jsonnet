// ts-gateway — exposes containers on the tailnet without hand-editing serve.json.
//
// Three services, started in this order:
//
//   proxy  read-only Docker API (POST denied), so the controller can list
//          containers and watch events without holding root on the host.
//   agent  tsgateway. Watches those events, reads tsgateway.* labels off every
//          container, and writes /config/serve.json into the shared volume.
//   app    tailscale. Reads that generated file via TS_SERVE_CONFIG.
//
// `app` waits on `agent` being healthy rather than merely started, because
// healthy here means "serve.json is on disk" — see the healthcheck baked into
// the tsgateway image. containerboot also watches the file's *directory* with
// fsnotify, which is why /config is a volume and not a bind-mounted file: a
// single-file bind mount never reports changes and routes go stale silently.
//
// serveJSONFile stays the hand-written config, now merged *under* the generated
// routes rather than being the whole thing. It carries what no label can express
// — the raw TCPForward to authentik's database. The base config always wins a
// conflict, so a stray label cannot displace it.

local lib = import 'lib/lib.libsonnet';
local reg = lib.registry;
local role = reg.role;

local name = 'ts-gateway';

// The hand-written base config, supplied per-host by Komodo (authentik.serve.json).
local serveJSONVar = '${serveJSONFile:?err}';
local baseConfigPath = '/base/' + serveJSONVar;

// The generated config, written by `agent` and read by `app` over the shared volume.
local serveConfigPath = '/config/serve.json';

local appVersion = 'v1.98.9';
local agentVersion = '0.1.0';
local proxyVersion = 'v0.4.2';

lib.render(
  name,

  lib.Stack(name, function(ref) {
    [role.APP]: lib.Service {
      image: 'tailscale/tailscale:' + appVersion,

      // Start only once the controller has written the config this reads.
      depends_on: { [role.AGENT]: { condition: 'service_healthy' } },

      volumes_:: { app: '/var/lib/tailscale' },
      // Read-only: `agent` owns this volume, tailscale only consumes it. Written
      // as a mount rather than a volumes_ entry because volumes_ has no place to
      // put the :ro — the volume itself is registered by `agent` below.
      mounts_:: ['config:/config:ro'],
      networks_:: lib.network.join(reg.networks.shared.tsGateway),

      environment: {
        TS_AUTHKEY: '${TS_AUTHKEY:?err}',
        TS_HOSTNAME: 'ts-gateway',
        TS_STATE_DIR: '/var/lib/tailscale',
        TS_USERSPACE: 'true',  // no tun/NET_ADMIN needed for a pure proxy
        TS_SERVE_CONFIG: serveConfigPath,
        TS_EXTRA_ARGS: '--advertise-tags=tag:gateway',
      },

      restart: reg.restartPolicy.default,
    },

    [role.AGENT]: lib.Service {
      image: 'fj.ktbcloud.com/bkenks/tsgateway:' + agentVersion,

      depends_on: [role.PROXY],

      // Owns /config: this is the service that registers the volume both it and
      // `app` mount. The healthcheck `app` gates on ships in the image itself —
      // the binary is distroless and has no shell to run a CMD-SHELL test.
      volumes_:: { config: '/config' },
      mounts_:: [lib.buildFileMount('./' + serveJSONVar, baseConfigPath, 'ro')],

      environment: {
        DOCKER_HOST: 'tcp://' + ref[role.PROXY] + ':2375',
        TSGATEWAY_SERVE_CONFIG: serveConfigPath,
        TSGATEWAY_BASE_CONFIG: baseConfigPath,
      },

      restart: reg.restartPolicy.default,
    },

    [role.PROXY]: lib.Service {
      image: 'tecnativa/docker-socket-proxy:' + proxyVersion,

      // The whole point: the controller never mutates anything, so every write
      // verb stays denied and a compromise of it cannot reach the host.
      environment: {
        CONTAINERS: 1,
        EVENTS: 1,
        POST: 0,
      },

      mounts_:: [lib.buildFileMount('/var/run/docker.sock', '/var/run/docker.sock', 'ro')],

      restart: reg.restartPolicy.default,
    },
  },
                lib.network.create(reg.networks.shared.tsGateway)),

  [lib.Secret('tsGateway')],
)
