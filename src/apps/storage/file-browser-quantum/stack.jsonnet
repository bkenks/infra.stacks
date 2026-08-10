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

local lib = import 'lib.libsonnet';
local reg = lib.registry;
local role = reg.role;

local name = 'file-brws-quantm';
local publicPort = '18450';
local dirSrv = "/rootless-srv";

local svcFBQ = {
  role: role.APP,
  version: "stable",
  dir: {
    root: dirSrv + '/file-browser-quantum',
    shared: self.root + "/shared",
    cache: self.root + "/cache",
  },
  exposes: '80'
};

local svcInit = {
  role: "init",
  version: "3.24.1",
};

local services(ref) = {
  [svcInit.role]: lib.Service {
    image: 'alpine:' + svcInit.version,
    user: "root",
    volumes: [dirSrv + ":" + dirSrv],
    command: [
      "sh",
      "-c",
      std.join(' && ', [
        "mkdir -p " + svcFBQ.dir.shared,
        "mkdir -p " + svcFBQ.dir.cache,
        "chown -R 1000:0 " + svcFBQ.dir.root,
        "chmod -R 770 " + svcFBQ.dir.root,
      ])
    ],
    healthcheck:{
      test: ["CMD", "curl", "-f", "http://localhost:80/health"],
      interval: "30s",
      timeout: "3s",
      start_period: "30s",
      retries: "3",
    },
    restart: "no"
  },

  [svcFBQ.role]: lib.Service {
    image: 'gtstef/filebrowser:' + svcFBQ.version,

    restart: reg.restartPolicy.unlessStopped,
    depends_on: { [svcInit.role]: { condition: "service_healthy" }},

    ports: [ '%s:%s:%s' % [reg.ips.loopback, publicPort, svcFBQ.exposes] ],
    expose: [std.toString(svcFBQ.exposes)],
    

    mounts_:: [
      './files:/home/filebrowser/data',
      svcFBQ.dir.shared + ':/shared',
      svcFBQ.dir.cache + ':/cache',
    ],

  },
};

lib.render( name, lib.Stack(name, services) )
