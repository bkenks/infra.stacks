// STANDARD STACK TEMPLATE — copy this file to start a new stack, change `name`, then
// delete every service and field you do not need.
//
// It exercises every feature the library has, so a lib/ change that breaks the library
// breaks this file and `mise run render` fails on the next commit. That is the point of
// keeping it a real, compiling stack rather than prose.
//
// The render contract (see .mise/tasks/render.py): this file evaluates to
// { '<filename>': <content>, … } and lib.render() does exactly that — emitting
//   compose.yaml   the project + an `include` of the manifest (what Docker loads)
//   services.yaml  the actual services/networks/volumes manifest
// render.py prefixes each with this file's stem, so they land as stack.compose.yaml and
// stack.services.yaml.
// Never edit those YAMLs; they carry a GENERATED header and are rewritten on commit.

local lib = import 'lib/lib.libsonnet';
local reg = lib.registry;
local role = reg.role;

local name = 'arcane';

local appVersion = 'latest';
local appPort = 3552;

lib.render(
  name,

  lib.Stack(name, function(ref) {
    [role.APP]: lib.Service {
      image: 'ghcr.io/example/example:' + appVersion,

      ports: ['18000:%s' % appPort],
      expose: [std.toString(appPort)],

      // Volumes: "mounts_::" create's entries as well
      volumes_:: { app: '/app/data' },
      mounts_:: [ reg.volumes.dockerSock.mount ],

      environment: {
        ENCRYPTION_KEY: '',
        JWT_SECRET: '',
        TZ: 'EST',
      },
      cgroup: 'host',
      restart: reg.restartPolicy.default,

    },
  }),

  [ lib.SecretOrBootstrap('arcane') ],
)