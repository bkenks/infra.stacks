// STANDARD STACK TEMPLATE — copy this file to start a new stack, change `name`, then
// delete every service and field you do not need.
//
// It exercises every feature the library has, so a lib/ change that breaks the library
// breaks this file and `mise run render` fails on the next commit. That is the point of
// keeping it a real, compiling stack rather than prose.
//
// The render contract (see .mise/tasks/render.py): this file evaluates to
// { '<filename>': <content>, … } and lib.render() does exactly that — emitting
//   compose.yaml        the project + an `include` of the manifest (what Docker loads)
//   compose.stack.yaml  the actual services/networks/volumes manifest
// Never edit those YAMLs; they carry a GENERATED header and are rewritten on commit.

local lib = import 'lib/lib.libsonnet';
local reg = lib.registry;
local role = reg.role;

local name = 'ts-gateway';

local appVersion = 'v1.20';

lib.render(
  name,

  lib.Stack(name, function(ref) {
    // Services are keyed by role, taken from reg.role rather than typed as bare strings —
    // that is what keeps `db` from being `database` in some other stack. A service whose
    // name is genuinely app-specific (guacd, gerbil) uses a plain local instead.
    //
    // `ref` is the stack's own service table: ref[role.DB] is the name the db service will
    // actually carry *if this stack declares one*, and an evaluation error if it does not.
    // Use it for every cross-service reference — a typo fails at the point of the mistake
    // rather than in a container that never starts.
    [role.APP]: lib.Service {
      image: 'tailscale/tailscale:' + appVersion,

      // volumes_ is { key: '/path/in/container' } for volumes this stack owns. The key is
      // the compose-local handle; the real volume is registered at the top level as
      // <name>_<key>, so it is declared once, here, where it is mounted.
      volumes_:: { app: '/var/lib/tailscale'},
      mounts_:: [ lib.buildFileMount('./serve.json', '/config/serve.json', 'ro') ],
      networks_:: lib.network.join(reg.networks.shared.tsGateway),

      environment: {
        TS_AUTHKEY: '${TS_AUTHKEY:?err}',
        TS_HOSTNAME: 'ts-gateway',
        TS_STATE_DIR: '/var/lib/tailscale',
        TS_USERSPACE: "true",        # no tun/NET_ADMIN needed for a pure proxy
        TS_SERVE_CONFIG: '/config/serve.json',
        TS_EXTRA_ARGS: '--advertise-tags=tag:gateway',
      },

      restart: reg.restartPolicy.default,
    },
  },
  lib.network.create(reg.networks.shared.tsGateway)
  ),

  // The env files the parent include interpolates into the manifest. Register the stack in
  // registry.libsonnet's infisical catalogue and reference it by KEY — lib.Secret('example')
  // — so the agent (producer) and this stack (consumer) derive the same path. Until it is
  // registered the literal below is fine. Drop the argument entirely for a no-secrets stack.
  [lib.Secret('tsGateway')],
)
